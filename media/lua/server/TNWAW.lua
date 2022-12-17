-- #region Global Methods

-- Format(field): For debugging ... Takes an input and returns a print() safe version of that value.
local function Format(field)
	local s_tbl = {
		["string"] = function() return field end,
		["number"] = function() return field end,
		["function"] = function() return "<function>" end,
		["nil"] = function() return "<nil>" end,
		["boolean"] = function()
			if field then
				return "enabled";
			else 
				return "disabled";
			end
		end,
		["table"] = function() return "<table>" end,
	}
	local m_func = s_tbl[type(field)];
	if (m_func) then
		return m_func();
	end
	return "<unk>";
end
-- Log(text): For debugging. Prefixes any text with TNWAW before printing.
local function Log(text)
	local pf = "TNWAW: "
	if type(text) ~= "string" then
		print(pf .. Format(text))
	else
		print(pf .. text)
	end
end
-- DeepCopy(original): Copies a table.
local function DeepCopy(original)
	local copy = {}
	for k, v in pairs(original) do
		if type(v) == "table" then
			v = DeepCopy(v)
		end
		copy[k] = v
	end
	return copy
end

local function RefreshZombie(zombie)
	local vMod = zombie:getModData();
	zombie:makeInactive(true);
	zombie:makeInactive(false);
	zombie:DoZombieStats();
	vMod.Ticks = 0;
end
-- #endregion

-- #region Classes

-- #region Settings Folder
SettingsFolder = {
	GetPath = function(self)
		local parentPath = ""
		if (self.Parent ~= nil) then parentPath = self.Parent:GetPath() end
		return parentPath .. self.Path .. self.Separator;
	end,
	Load = function(self, key)
		local option = getSandboxOptions():getOptionByName(self:GetPath() .. key);
		if option then
			return option:getValue();
		end
		return nil;
	end,
	Save = function(self, key, value)
		getSandboxOptions():set(self:GetPath() .. key, value);
	end,
}
SettingsFolder.__index = SettingsFolder;
function SettingsFolder.new(path, parent, separatorOveride)
	local i = setmetatable({},SettingsFolder);
	i.Path = path;
	if parent then i.Parent = parent end
	if separatorOveride then i.Separator = separatorOveride
	else i.Separator = "_" end
	return i;
end
function SettingsFolder.parseTable(table, parentFolder)
	local returnTable = {};
	for key, val in pairs(table) do
		local folder = {};
		local children = {};
		if parentFolder then
			if type(val) == "string" then
				folder = SettingsFolder.new(key, parentFolder, val);
			else
				folder = SettingsFolder.new(key, parentFolder);
			end
		else
			if type(val) == "string" then
				folder = SettingsFolder.new(key, nil, val);
			else
				folder = SettingsFolder.new(key);
			end
		end
		if type(val) == "table" then children = SettingsFolder.parseTable(val, folder) end;
		for k,v in pairs(children) do folder[k] = v end
		returnTable[key] = folder;
	end
	return returnTable;
end
-- #endregion

-- #region Zombie Mutation
ZombieMutation = {
	Load = {
		Lore = function(self) return self.Parent.SettingsManager.ZombieLore:Load(self.Parent.Key) or self.Parent.Lore end,
		Default = function(self) return self.Parent.SettingsManager.TNWAW.ZombieLore:Load(self.Parent.Key) or self.Parent.Default end,
		Enabled = function(self)
			local r = {};
			for k, v in pairs({Night = false, Rain = false, Fog = false,}) do
				local s = self.Parent.SettingsManager.TNWAW[k].MutationEnabled:Load(self.Parent.Key);
				if s then r[k] = s end
			end
			return r;
		end,
		Target = function(self)
			local r = {};
			for k, v in pairs(self.Parent.Target) do
				local s = self.Parent.SettingsManager.TNWAW[k].Target:Load(self.Parent.Key);
				if s then r[k] = s end
			end
			return r;
		end,
		All = function(self)
			self.Parent.Lore = self:Lore();
			self.Parent.Default = self:Default();
			self.Parent.Enabled = self:Enabled();
			self.Parent.Target = self:Target();
		end,
	},
	Save = {
		Lore = function(self) self.Parent.SettingsManager.ZombieLore:Save(self.Parent.Key, self.Parent.Lore) end,
		All = function(self)
			self:Lore();
		end,
	}
}
ZombieMutation.__index = ZombieMutation;
ZombieMutation.Load.__index = ZombieMutation.Load;
ZombieMutation.Save.__index = ZombieMutation.Save;
function ZombieMutation.new(key, activators, settingsManager)
	local i = setmetatable({}, ZombieMutation);

	i.Load = setmetatable({}, ZombieMutation.Load);
	i.Save = setmetatable({}, ZombieMutation.Save);

	i.Key = key;

	local a = {};
	for k, v in pairs(activators) do
		if (type(v) == "table") then
			a[k] = false;
		end
	end
	i.Enabled = DeepCopy(a);
	i.Target = DeepCopy(a);

	i.Lore = -1;
	i.Default = -1;
	i.Current = -1;

	i.SettingsManager = settingsManager;

	i.Load.Parent = i;
	i.Save.Parent = i;

	return i;
end
-- #endregion

-- #region Mutation Manager

MutationManager = {
	Log = function(self, msg)
		Log(self.Mutation.Key.." Manager: "..msg)
	end,
	Enabled = function(self)
		local a = true;
		for k, v in pairs(self.Mutation.Enabled) do
			a = a and v;
			if a == false then return a end
		end
		return a;
	end,
	MutationActive = function(self)
		local a = false;
		if (self.CEnabled) then
			for k, v in pairs(self.Activators) do
				if type(v) == "table" then
					a = a or v.Active;
					if a == true then return a end
				end
			end
		end
		return a;
	end,
	TargetValue = function(self)
		local s = {};
		local r = self.Mutation.Default;
		if (self.CEnabled) then
			for k, v in pairs(self.Activators) do
				if type(v) == "table" and v.Active and self.Mutation.Enabled[k] then 
					table.insert(s, self.Mutation.Target[k]);
				end
			end
			if s[1] ~= nil then
				table.sort(s);
				r = s[1];
			end
		end
		return r;
	end,
	PhaseTimeout = function(self)
		local r = 0;
		if (self.CEnabled) then
			local t = {};
			for k, v in pairs(self.Activators) do
				if type(v) == "table" and v.Active and self.Mutation.Enabled[k] then
					table.insert(t, self.SettingsManager.TNWAW[k]:Load("PhaseTimeout"));
				end
			end
			r = 15;
			if t[#t] ~= nil then
				table.sort(t);
				r = t[#t];
			end
		end
		return r;
	end,
	DoPhaseChange = function(self, targetValue)
		if self.Mutation.Current > targetValue then
			if self.Mutation.Current == 4 then
				self.Mutation.Current = targetValue;
				self.Mutation.Lore = targetValue;
				self.Mutation.Save:Lore();
			else
				if self.Mutation.Current > targetValue and self.Mutation.Current > 1 then
					self.Mutation.Current = self.Mutation.Current - 1;
					self.Mutation.Lore = self.Mutation.Current;
					self.Mutation.Save:Lore();
				end
			end
		else
			if targetValue == 4 and self.Mutation.Current ~= 4 then
				self.Mutation.Current = targetValue
				self.Mutation.Lore = targetValue;
				self.Mutation.Save:Lore();
			else
				if self.Mutation.Current < targetValue and self.Mutation.Current < 3 then
					self.Mutation.Current = self.Mutation.Current + 1;
					self.Mutation.Lore = self.Mutation.Current;
					self.Mutation.Save:Lore();
				end
			end
		end
	end,
	EveryOneMinute = function(self)
		self.Mutation.Load:All();

		self.CEnabled = self:Enabled();

		if self.Mutation.Current == -1 then
			self.Mutation.Current = self.Mutation.Lore or self.Mutation.Default;
		else
			local targetValue = self:TargetValue();

			if self.Mutation.Current ~= targetValue then
				if self.PhaseChange.Active then
					if self.PhaseChange.Timer <= 0 then
						self.PhaseChange.Active = false;
	
						if self:MutationActive() then
							self:DoPhaseChange(targetValue);
							if isDebugEnabled() then self:Log("Phase change complete.") end
						else
							if isDebugEnabled() then self:Log("Phase timeout complete.") end
						end
					end
				else
					self.PhaseChange.Active = true;
					self.PhaseChange.Timer = self:PhaseTimeout();

					if not self:MutationActive() then
						self:DoPhaseChange(targetValue);
						if isDebugEnabled() then self:Log("Phase change complete. Timeout=" .. self.PhaseChange.Timer) end
					else
						if isDebugEnabled() then self:Log("Phasing towards target " .. self.Key .. " " .. targetValue .. ". Timeout=" .. self.PhaseChange.Timer) end
					end
	
				end
				self.PhaseChange.Timer = self.PhaseChange.Timer - 1;
			elseif self.PhaseChange.Active or self.PhaseChange.Timer > 0 then
				if isDebugEnabled() then self:Log("Target " .. self.Key .. " already reached. Cancelling phase timer.") end
				self.PhaseChange.Active = false;
				self.PhaseChange.Timer = 0;
			end
		end
	end,
	OnZombieUpdate = function(self, zombie, mutationList)
		local vMod = zombie:getModData();
		vMod[self.Key] = vMod[self.Key] or -1;
		if (vMod[self.Key] ~= self.Mutation.Current) then
			vMod[self.Key] = self.Mutation.Current;

			RefreshZombie(zombie);
			-- do something custom for the zombie stats that need to be handled differently
		end
		local command = mutationList[self.Key]
		if (type(command) == "function") then
			command(self, zombie)
		end
	end,
}
MutationManager.__index = MutationManager;
function MutationManager.new(key, mutation, activators, settings)
	local i = setmetatable({}, MutationManager);

	i.Key = key;

	i.Mutation = mutation;
	i.Activators = activators;
	i.SettingsManager = settings;

	i.CEnabled = false;

	i.PhaseChange = {
		Active = false,
		Timer = 0,
	}
	return i;
end
-- #endregion

-- #region Activator - Abstract

AbstractActivator = {
	Log = function(self, msg)
		Log(self.Key.." Activator: "..msg)
	end,
	Enabled = function(self)
		return self.SettingsManager.TNWAW[self.Key]:Load("Enabled") or false;
	end,
}
AbstractActivator.__index = AbstractActivator;

-- #endregion

-- #region Activator - Night
NightActivator = {
	Season = {
		Switch = {
			[0] = "Winter",
			[1] = "Winter",
			[2] = "Spring",
			[3] = "Spring",
			[4] = "Spring",
			[5] = "Summer",
			[6] = "Summer",
			[7] = "Summer",
			[8] = "Fall",
			[9] = "Fall",
			[10] = "Fall",
			[11] = "Winter",
		},
		Spring = function(self, hr) return hr < self.Parent.NightTime.End.Spring or hr > self.Parent.NightTime.Start.Spring end,
		Summer = function(self, hr) return hr < self.Parent.NightTime.End.Summer or hr > self.Parent.NightTime.Start.Summer end,
		Autumn = function(self, hr) return hr < self.Parent.NightTime.End.Autumn or hr > self.Parent.NightTime.Start.Autumn end,
		Winter = function(self, hr) return hr < self.Parent.NightTime.End.Winter or hr > self.Parent.NightTime.Start.Winter end,
		IsNight = function(self, month, hour)
			local k = self.Switch[month];
			if (self[k]) then
				return self[k](self, hour);
			end
			return false;
		end,
	},

	Refresh = function(self)
		self.CEnabled = self:Enabled()
		if (self.CEnabled) then
			for phase, tbl in pairs(self.NightTime) do
				for season, val in pairs(tbl) do
					local settingFolder = self.SettingsManager.TNWAW.Night[phase];
					local phaseTable = self.NightTime[phase];
					phaseTable[season] = settingFolder:Load(season) or phaseTable[season];
				end
			end
		end
	end,

	EveryOneMinute = function(self)
		self:Refresh(); 
	end,

	EveryHours = function(self)
		if (self.CEnabled) then
			self:Refresh();

			local month = self.GameTime:getMonth();
			local hour = getGameTime():getTimeOfDay();
		
			local a = self.Season:IsNight(month, hour) and self:Enabled();
			if a ~= self.Active then
				self:Log("Mutation activator "..Format(a));
				self.Active = a;
			end
		end
	end,
}
NightActivator.__index = NightActivator;
NightActivator.Season.__index = NightActivator.Season;
setmetatable(NightActivator, AbstractActivator);
function NightActivator.new(settings)
	local i = setmetatable({}, NightActivator);
	i.Season = setmetatable({}, NightActivator.Season);

	i.Key = "Night";
	i.Active = false;

	i.SettingsManager = settings;
	i.GameTime = GameTime:getInstance();
	
	i.NightTime = {
		Start = {
			Spring = 22,
			Summer = 23,
			Autumn = 22,
			Winter = 20,
		},
		End = {
			Spring = 6,
			Summer = 6,
			Autumn = 6,
			Winter = 6,
		},
	};

	i.Season.Parent = i;

	i.CEnabled = false;
	
	i:EveryHours();

	return i;
end
-- #endregion

-- #region Activator - Rain
RainActivator = {
	Refresh = function(self)
		self.Threshold = self.SettingsManager.TNWAW.Rain:Load("Threshold") or 1;
	end,

	OnClimateTick = function(self)
		if (self:Enabled()) then
			self:Refresh();

			local currentRain = RainManager:getRainIntensity() * 100;

			if self.LastRain ~= currentRain then
				self.LastRain = currentRain;

				local a = (self.LastRain >= self.Threshold) and self:Enabled();
				if a ~= self.Active then
					self:Log("Mutation activator "..Format(a));
					self.Active = a;
				end
		
				if isDebugEnabled() and not self.Active and self.LastRain >= 1 then
					self:Log("Detected. Threshold/Amount=" .. self.Threshold .. "/" .. self.LastRain);
				end
			end
		end
	end,
}
RainActivator.__index = RainActivator;
setmetatable(RainActivator, AbstractActivator);
function RainActivator.new(settings)
	local i = setmetatable({}, RainActivator);

	i.Key = "Rain";
	i.Active = false;
	
	i.SettingsManager = settings;

	i.Threshold = 0.0;
	i.LastRain = 0.0;
	
	i:OnClimateTick();
	return i;
end
-- #endregion

-- #region Activator - Fog
FogActivator = {
	Refresh = function(self)
		self.Threshold = self.SettingsManager.TNWAW.Fog:Load("Threshold") or 1;
	end,

	OnClimateTick = function(self)
		if (self:Enabled()) then
			self:Refresh();
			local currentFog = self.ClimateManager:getFogIntensity() * 100;

			if self.LastFog ~= currentFog then
				self.LastFog = currentFog;

				local a = (self.LastFog >= self.Threshold) and self:Enabled();
				if a ~= self.Active then
					self:Log("Mutation activator "..Format(a));
					self.Active = a;
				end

				if isDebugEnabled() and not self.Active and self.LastFog >= 1 then
					self:Log("Detected. Threshold/Amount=" .. self.Threshold .. "/" .. self.LastFog);
				end
			end
		end
	end,
}
FogActivator.__index = FogActivator;
setmetatable(FogActivator, AbstractActivator);
function FogActivator.new(settings)
	local i = setmetatable({}, FogActivator);

	i.Key = "Fog";
	i.Active = false;

	i.SettingsManager = settings;
	i.ClimateManager = getClimateManager();

	i.Threshold = 0.0;
	i.LastFog = 0.0;
	
	i:OnClimateTick();
	return i;
end
-- #endregion

-- #endregion

local ZombieUpdateInterval = 500;

local MutationsList = {
	Speed = true,
--	Strength = true,
--	Toughness = true,
--	Cognition = true, -- Not possible without java modifications
	Memory = true, -- Probably not possible without java modifications
	Sight = true,
	Hearing = true,
}

-- ============================================

local ModData = {
	Settings = {
		Init = function(self)
			if (self.__data == nil) then
				self.__data = SettingsFolder.parseTable({
					ZombieLore = ".",
					TNWAW = {
						ZombieLore = {},
						Night = {
							Target = {},
							MutationEnabled = {},
							Start = {},
							End = {},
						},
						Rain = {
							Target = {},
							MutationEnabled = {},
						},
						Fog = {
							Target = {},
							MutationEnabled = {},
						},
					},
				})
			end
		end,

		Get = function(self)
			self:Init()
			return self.__data;
		end,
	},
	JClassFieldData = {
		Speed = false,
		Cognition = false,
		Init = function(self, zombie)
			if (self.Speed == false or self.Cognition == false) then	
				for i = 0, getNumClassFields(zombie) - 1 do
					local javaField = getClassField(zombie, i)
					if luautils.stringEnds(tostring(javaField), '.' .. "speedType") then
						self.Speed = javaField;
					end
					if luautils.stringEnds(tostring(javaField), '.' .. "cognition") then
						self.Cognition = javaField;
					end
				end
			end
		end,
	},
	Activators = {
		Init = function (self, settings)
			if (self.Night == nil) then
				self.Night = NightActivator.new(settings)
			end
			if (self.Rain == nil) then
				self.Rain = RainActivator.new(settings)
			end
			if (self.Fog == nil) then
				self.Fog = FogActivator.new(settings)
			end
		end,
	},
	Mutations = {
		__list = DeepCopy(MutationsList),
		Init = function (self, activators, settings)
			for mutKey, mutation in pairs(self.__list) do
				if type(mutation) ~= "table" then
					self.__list[mutKey] = ZombieMutation.new(mutKey, activators, settings)
				end
			end
		end,
		Get = function(self)
			return self.__list;
		end,
	},
	MutationManagers = {
		__list = DeepCopy(MutationsList),
		Init = function(self, mutations, activators, settings)
			for mutMgrKey, mutationManager in pairs(self.__list) do
				if type(mutationManager) ~= "table" then
					self.__list[mutMgrKey] = MutationManager.new(mutMgrKey, mutations[mutMgrKey], activators, settings)
				end
			end
		end,
		EveryOneMinute = function (self)
			for mutMgrKey, mutationManager in pairs(self.__list) do
				mutationManager:EveryOneMinute()
			end
		end,
		Get = function(self)
			return self.__list;
		end,
	}
}

function Init()
	ModData.Settings:Init()
	ModData.Activators:Init(ModData.Settings:Get())

	ModData.Mutations:Init(ModData.Activators, ModData.Settings:Get())
	ModData.MutationManagers:Init(ModData.Mutations:Get(), ModData.Activators, ModData.Settings:Get())

	ModData.JClassFieldData:Init(IsoZombie.new(nil))
end

function EveryOneMinute()
	Init()

	if (type(ModData.Activators.Night) == "table") then
		ModData.Activators.Night:EveryOneMinute();
	end

	ModData.MutationManagers:EveryOneMinute()
end

local function EveryHours()
	Init()
	if (type(ModData.Activators.Night) == "table") then
		ModData.Activators.Night:EveryHours();
	end
end
 
local function OnClimateTick()
	Init()
	if (type(ModData.Activators.Fog) == "table") then
		ModData.Activators.Fog:OnClimateTick();
	end

	if (type(ModData.Activators.Rain) == "table") then
		ModData.Activators.Rain:OnClimateTick();
	end
end

local function OnZombieUpdate(zombie)
	if ((not isClient() and not isServer()) or (isClient() and not zombie:isRemoteZombie())) then
		local vMod = zombie:getModData();

		vMod.Ticks = vMod.Ticks or -1;
		if (vMod.Ticks >= ZombieUpdateInterval) then
			RefreshZombie(zombie);
		else
			for mutKey, mutationManager  in pairs(ModData.MutationManagers:Get()) do
				if type(mutationManager) == "table" and type(mutationManager.OnZombieUpdate) == "function" then
					mutationManager:OnZombieUpdate(zombie, ModData);
				end
			end
		end

		vMod.Ticks = vMod.Ticks + 1;
	end
end

Events.EveryOneMinute.Add(EveryOneMinute);
Events.EveryHours.Add(EveryHours);
Events.OnClimateTick.Add(OnClimateTick);
Events.OnZombieUpdate.Add(OnZombieUpdate);

Events.OnGameStart.Add(Init);
Events.OnServerStarted.Add(Init);