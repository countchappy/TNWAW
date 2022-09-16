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
-- PrintTable(table, [parent]): For debugging. Prints a table's structure and values. I admit, this is shit. Use PZ's in game debug screen.
local function PrintTable(table, parent)
	for k, v in pairs(table) do
		local p = ""
		if (parent) then p = parent .. ">" end
		p = p .. k
		if type(v) == "table" then
			Log(p)
			PrintTable(v, p)
		else
			Log(p.."="..Format(v))
		end
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
	vMod.Ticks = 0;
end
-- #endregion

-- #region Classes

-- #region Settings Folder
SettingsFolder = {
	Path = nil,
	Parent = nil,
	GetPath = function(self)
		local parentPath = ""
		if (self.Parent ~= nil) then parentPath = self.Parent:GetPath() end
		return parentPath .. self.Path .. ".";
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
function SettingsFolder.new(path, parent)
	local i = setmetatable({},SettingsFolder);
	i.Path = path;
	if parent then i.Parent = parent end
	return i;
end
function SettingsFolder.parseTable(table, parentFolder)
	local returnTable = {};
	for key, val in pairs(table) do
		local folder = {};
		local children = {};
		if parentFolder then
			folder = SettingsFolder.new(key, parentFolder);
		else
			folder = SettingsFolder.new(key);
		end
		if type(val) == "table" then children = SettingsFolder.parseTable(val, folder) end;
		for k,v in pairs(children) do folder[k] = v end
		returnTable[key] = folder;
	end
	return returnTable;
end
-- #endregion

-- #region Zombie Attribute
ZombieAttribute = {
	SettingsManager = {},
	Key = false,
	Lore = -1,
	Default = -1,
	Current = -1,
	Enabled = {},
	Target = {},
	Load = {
		Parent = false,
		Lore = function(self) return self.Parent.SettingsManager.ZombieLore:Load(self.Parent.Key) or self.Parent.Lore end,
		Default = function(self) return self.Parent.SettingsManager.TNWAW.ZombieLore:Load(self.Parent.Key) or self.Parent.Default end,
		Enabled = function(self)
			local r = {};
			for k, v in pairs(self.Parent.Enabled) do
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
		Parent = false,
		Lore = function(self) self.Parent.SettingsManager.ZombieLore:Save(self.Parent.Key, self.Parent.Lore) end,
		All = function(self)
			self:Lore();
		end,
	},
}
ZombieAttribute.__index = ZombieAttribute;
function ZombieAttribute.new(key, activators, settingsManager)
	local i = setmetatable({}, ZombieAttribute);
	i.Key = key;
	local a = {};
	for k, v in pairs(activators) do
		a[k] = false;
	end
	i.Enabled = DeepCopy(a);
	i.Target = DeepCopy(a);
	i.SettingsManager = settingsManager;
	i.Load.Parent = i;
	i.Save.Parent = i;
	return i;
end
-- #endregion

-- #region Mutation Manager

MutationManager = {
	SettingsManager = false,

	Activators = {},
	ZombieAttribute = {},

	PhaseChange = {
		Active = false,
		Timer = 0,
	},

	Log = function(self, msg)
		Log(self.ZombieAttribute.Key.." Manager: "..msg)
	end,
	Enabled = function(self)
		local a = true;
		for k, v in pairs(self.ZombieAttribute.Enabled) do
			a = a and v;
			if a == false then return a end
		end
		return a;
	end,
	MutationActive = function(self)
		local a = false;
		for k, v in pairs(self.Activators) do
			a = a or v.Active;
			if a == true then return a end
		end
		return a;
	end,
	TargetValue = function(self)
		local s = {};
		for k, v in pairs(self.Activators) do
			if v.Active and self.ZombieAttribute.Enabled[k] then 
				table.insert(s, self.ZombieAttribute.Target[k]);
			end
		end
		local r = self.ZombieAttribute.Default;
		if s[1] ~= nil then
			table.sort(s);
			r = s[1];
		end
		return r;
	end,
	PhaseTimeout = function(self)
		local t = {};
		for k, v in pairs(self.Activators) do
			if v.Active and self.ZombieAttribute.Enabled[k] then
				table.insert(t, self.SettingsManager.TNWAW[k]:Load("PhaseTimeout"));
			end
		end
		local r = 15;
		if t[#t] ~= nil then
			table.sort(t);
			r = t[#t];
		end
		return r;
	end,
	DoPhaseChange = function(self, targetValue)
		if self.ZombieAttribute.Current > targetValue then
			if self.ZombieAttribute.Current == 4 then
				self.ZombieAttribute.Current = targetValue;
				self.ZombieAttribute.Lore = targetValue;
				self.ZombieAttribute.Save:Lore();
			else
				if self.ZombieAttribute.Current > targetValue and self.ZombieAttribute.Current > 1 then
					self.ZombieAttribute.Current = self.ZombieAttribute.Current - 1;
					self.ZombieAttribute.Lore = self.ZombieAttribute.Current;
					self.ZombieAttribute.Save:Lore();
				end
			end
		else
			if targetValue == 4 and self.ZombieAttribute.Current ~= 4 then
				self.ZombieAttribute.Current = targetValue
				self.ZombieAttribute.Lore = targetValue;
				self.ZombieAttribute.Save:Lore();
			else
				if self.ZombieAttribute.Current < targetValue and self.ZombieAttribute.Current < 3 then
					self.ZombieAttribute.Current = self.ZombieAttribute.Current + 1;
					self.ZombieAttribute.Lore = self.ZombieAttribute.Current;
					self.ZombieAttribute.Save:Lore();
				end
			end
		end
	end,
	CheckPhaseChange = function(self)
		self.ZombieAttribute.Load:All();

		if self.ZombieAttribute.Current == -1 then
			self.ZombieAttribute.Current = self.ZombieAttribute.Lore or self.ZombieAttribute.Default;
		else
			local targetValue = self:TargetValue();

			if self.ZombieAttribute.Current ~= targetValue then
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
						if isDebugEnabled() then self:Log("Phasing towards target strength " .. targetValue .. ". Timeout=" .. self.PhaseChange.Timer) end
					end
	
				end
				self.PhaseChange.Timer = self.PhaseChange.Timer - 1;
			elseif self.PhaseChange.Active or self.PhaseChange.Timer > 0 then
				if isDebugEnabled() then self:Log("Target already reached. Cancelling phase timer.") end
				self.PhaseChange.Active = false;
				self.PhaseChange.Timer = 0;
			end
		end
	end,
	OnZombieUpdate = function(self, zombie)
		local vMod = zombie:getModData();
		vMod[self.Key] = vMod[self.Key] or -1;
		if (vMod[self.Key] ~= self.ZombieAttribute.Current) then
			vMod[self.Key] = self.ZombieAttribute.Current;
			RefreshZombie(zombie);
		end
	end,
}
MutationManager.__index = MutationManager;
function MutationManager.new(key, zombieAttribute, activators, settings)
	local i = setmetatable({}, MutationManager);
	i.Key = key;
	i.ZombieAttribute = zombieAttribute;
	i.Activators = activators;
	i.SettingsManager = settings;
	return i;
end
-- #endregion

-- #region Activator - Abstract

AbstractActivator = {
	Key = false,
	Active = false,
	SettingsManager = {},
}

AbstractActivator.__index = AbstractActivator;

function AbstractActivator:Log(msg)
	Log(self.Key.." Activator: "..msg)
end
function AbstractActivator:Enabled()
	return self.SettingsManager.TNWAW[self.Key]:Load("Enabled") or false;
end

-- #endregion

-- #region Activator - Night
NightActivator = {
	GameTime = false,

	NightTime = {
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
	},

	Season = {
		Parent = false,
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
		for phase, tbl in pairs(self.NightTime) do
			for season, val in pairs(tbl) do
				local settingFolder = self.SettingsManager.TNWAW.Night[phase];
				local phaseTable = self.NightTime[phase];
				phaseTable[season] = settingFolder:Load(season) or phaseTable[season];
			end
		end
	end,

	EveryOneMinute = function(self)
		self:Refresh();
	end,

	EveryHours = function(self)
		self:Refresh();

		local month = self.GameTime:getMonth();
		local hour = getGameTime():getTimeOfDay();
	
		self.Active = self.Season:IsNight(month, hour) and self:Enabled();
	end,
}
NightActivator.__index = NightActivator;
setmetatable(NightActivator, AbstractActivator);
function NightActivator.new(settings)
	local i = setmetatable({}, NightActivator);
	i.Active = false;
	i.SettingsManager = settings;
	i.GameTime = GameTime:getInstance();
	i.Season.Parent = i;
	i.Key = "Night";
	i:EveryHours();
	return i;
end
-- #endregion

-- #region Activator - Rain
RainActivator = {
	Threshold = 0.0,
	LastRain = 0.0,

	Refresh = function(self)
		self.Threshold = self.SettingsManager.TNWAW.Rain:Load("Threshold") or 1;
	end,

	OnClimateTick = function(self)
		self:Refresh();

		local currentRain = RainManager:getRainIntensity() * 100;

		if self.LastRain ~= currentRain then
			self.LastRain = currentRain;

			self.Active = (self.LastRain >= self.Threshold) and self:Enabled();
	
			if isDebugEnabled() and not self.Active and self.LastRain >= 1 then
				self:Log("Detected. Threshold/Amount=" .. self.Threshold .. "/" .. self.LastRain);
			end
		end
	end,
}
RainActivator.__index = RainActivator;
setmetatable(RainActivator, AbstractActivator);
function RainActivator.new(settings)
	local i = setmetatable({}, RainActivator);
	i.Active = false;
	i.SettingsManager = settings;
	i.Key = "Rain";
	i:OnClimateTick();
	return i;
end
-- #endregion

-- #region Activator - Fog
FogActivator = {
	Threshold = 0.0,
	LastFog = 0.0,
	ClimateManager = false,

	Refresh = function(self)
		self.Threshold = self.SettingsManager.TNWAW.Fog:Load("Threshold") or 1;
	end,

	OnClimateTick = function(self)
		self:Refresh();
		local currentFog = self.ClimateManager:getFogIntensity() * 100;

		if self.LastFog ~= currentFog then
			self.LastFog = currentFog;

			self.Active = (self.LastFog >= self.Threshold) and self:Enabled();

			if isDebugEnabled() and not self.Active and self.LastFog >= 1 then
				self:Log("Detected. Threshold/Amount=" .. self.Threshold .. "/" .. self.LastFog);
			end
		end
	end,
}
FogActivator.__index = FogActivator;
setmetatable(FogActivator, AbstractActivator);
function FogActivator.new(settings)
	local i = setmetatable({}, FogActivator);
	i.Active = false;
	i.SettingsManager = settings;
	i.ClimateManager = getClimateManager();
	i.Key = "Fog";
	i:OnClimateTick();
	return i;
end
-- #endregion

-- #endregion

local ZombieUpdateInterval = 500;

local SettingsList = {
	ZombieLore = {},
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
}

local MutationsList = {
	Speed = false,
	Cognition = false,
}

-- ============================================

local Settings = nil
local Activators = {
	Night = false,
	Rain = false,
	Fog = false,
}
local Attributes = DeepCopy(MutationsList);
local AttributeManagers = DeepCopy(MutationsList);

function ValidateAndDoInit()
	if Settings == nil then Settings = SettingsFolder.parseTable(SettingsList) end
	if Activators.Night == false then Activators.Night = NightActivator.new(Settings) end
	if Activators.Rain == false then Activators.Rain = RainActivator.new(Settings) end
	if Activators.Fog == false then Activators.Fog = FogActivator.new(Settings) end
end

function EveryOneMinute()
	ValidateAndDoInit();

	for k, activator in pairs(Activators) do
		if type(activator) == "table" and type(activator.EveryOneMinute) == "function" then
			activator:EveryOneMinute()
		end
	end

	for attributeKey, attribute in pairs(Attributes) do
		if type(attribute) ~= "table" then
			Attributes[attributeKey] = ZombieAttribute.new(attributeKey, Activators, Settings);
		else
			AttributeManagers[attributeKey]:CheckPhaseChange();
		end
	end

	for attributeKey, attrManager in pairs(AttributeManagers) do
		if type(attrManager) ~= "table" then
			AttributeManagers[attributeKey] = MutationManager.new(attributeKey, Attributes[attributeKey], Activators, Settings);
		end
	end
end

local function EveryHours()
	ValidateAndDoInit();
	
	for activatorKey, activator in pairs(Activators) do
		if type(activator.EveryHours) == "function" then
			activator:EveryHours();
		end
	end
end

local function OnClimateTick()
	ValidateAndDoInit();

	for activatorKey, activator in pairs(Activators) do
		if type(activator.OnClimateTick) == "function" then
			activator:OnClimateTick();
		end
	end
end

local function OnZombieUpdate(zombie)
	if ((not isClient() and not isServer()) or (isClient() and not zombie:isRemoteZombie())) then
		local vMod = zombie:getModData();

		vMod.Ticks = vMod.Ticks or -1;
		if (vMod.Ticks >= ZombieUpdateInterval) then
			RefreshZombie(zombie);
		else
			for attributeKey, attrManager  in pairs(AttributeManagers) do
				if type(attrManager) == "table" and type(attrManager.OnZombieUpdate) == "function" then
					attrManager:OnZombieUpdate(zombie);
				end
			end
		end

		vMod.Ticks = vMod.Ticks + 1;
	end
end

function OnStart()
	ValidateAndDoInit()
end

Events.EveryOneMinute.Add(EveryOneMinute);
Events.EveryHours.Add(EveryHours);
Events.OnClimateTick.Add(OnClimateTick);
Events.OnZombieUpdate.Add(OnZombieUpdate);

Events.OnGameStart.Add(OnStart);
Events.OnServerStarted.Add(OnStart);