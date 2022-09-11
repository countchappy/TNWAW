-- Format(): For debugging ... Takes an input and returns a print() safe version of that value.
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

local function Log(text)
	local pf = "TNWAW: "
	if type(text) ~= "string" then
		print(pf .. Format(text))
	else
		print(pf .. text)
	end
end

local function RefreshZombie(zombie)
	local vMod = zombie:getModData();
	zombie:makeInactive(true);
	zombie:makeInactive(false);
	vMod.Ticks = 0;
end
-- ============================================

local Config = {
	-- common
	SpeedLore = 2,
	ZombieUpdateInterval = 500,
	-- night
	ModEnabledNight = false,
	ModSpeedEnabledNight = true,
	SpeedTargetNight = 1,
	PhaseTimeoutNight = 15,
	-- dawn & dusk
	NightStartSpring = 22,
	NightStartSummer = 23,
	NightStartAutumn = 22,
	NightStartWinter = 20,
	NightEndSpring = 6,
	NightEndSummer = 6,
	NightEndAutumn = 6,
	NightEndWinter = 6,
	-- weather
	ModEnabledWeather = false,
	ModSpeedEnabledRain = true,
	SpeedTargetRain = 2,
	PhaseTimeoutRain = 30,
	RainThreshold = 10,
	ModSpeedEnabledFog = true,
	SpeedTargetFog = 2,
	PhaseTimeoutFog = 30,
	FogThreshold = 25,

	-- Methods
	PollTNWAWSetting = function(self, key)
		local s = getSandboxOptions():getOptionByName("TNWAW."..key):getValue() or self[key];
		if self[key] ~= s then
			self[key] = s
			if isDebugEnabled() then Log("Setting '"..key.."' was changed to: " .. Format(s)) end
		end
	end,
}
	
-- ============================================

local ModSpeedManager = {
	Enabled = false,
	NightEnabled = false,
	RainEnabled = false,
	FogEnabled = false,
	CurrentSpeed = -1,
	PhaseChangeActive = false,
	PhaseChangeTimer = 0,

	Log = function(msg) Log("MSM: "..msg) end,

	TargetSpeed = function(self)
		local s = {};

		if Config.ModSpeedEnabledNight and self.NightEnabled then table.insert(s, Config.SpeedTargetNight) end
		if Config.ModSpeedEnabledRain and self.RainEnabled then table.insert(s, Config.SpeedTargetRain) end
		if Config.ModSpeedEnabledFog and self.FogEnabled then table.insert(s, Config.SpeedTargetFog) end

		local r = Config.SpeedLore;
		if s[1] ~= nil then
			table.sort(s);
			r = s[1];
		end
		return r;
	end,

	PhaseTimeout = function(self)
		local t = {};

		if Config.ModSpeedEnabledNight and self.NightEnabled then table.insert(t, Config.PhaseTimeoutNight) end
		if Config.ModSpeedEnabledRain and self.RainEnabled then table.insert(t, Config.PhaseTimeoutRain) end
		if Config.ModSpeedEnabledFog and self.FogEnabled then table.insert(t, Config.PhaseTimeoutFog) end

		local r = 15;
		if t[#t] ~= nil then
			table.sort(t);
			r = t[#t];
		end
		return r;
	end,

	MutationActive = function(self)
		return self.NightEnabled or self.RainEnabled or self.FogEnabled;
	end,

	UpdateSpeed = function(self)
		getSandboxOptions():set("ZombieLore.Speed", self.CurrentSpeed);
	end,

	DoPhaseChange = function(self, targetSpeed)
		if self.CurrentSpeed > targetSpeed then
			if self.CurrentSpeed == 4 then
				self.CurrentSpeed = targetSpeed
				self:UpdateSpeed()
			else
				if self.CurrentSpeed > targetSpeed and self.CurrentSpeed > 1 then
					self.CurrentSpeed = self.CurrentSpeed - 1;
					self:UpdateSpeed()
				end
			end
		else
			if targetSpeed == 4 and self.CurrentSpeed ~= 4 then
				self.CurrentSpeed = targetSpeed
				self:UpdateSpeed()
			else
				if self.CurrentSpeed < targetSpeed and self.CurrentSpeed < 3 then
					self.CurrentSpeed = self.CurrentSpeed + 1;
					self:UpdateSpeed()
				end
			end
		end
	end,
	
	Refresh = function(self)
		Config:PollTNWAWSetting("SpeedLore");

		Config:PollTNWAWSetting("ModSpeedEnabledNight");
		Config:PollTNWAWSetting("PhaseTimeoutNight");
		Config:PollTNWAWSetting("SpeedTargetNight");

		Config:PollTNWAWSetting("ModSpeedEnabledRain");
		Config:PollTNWAWSetting("PhaseTimeoutRain");
		Config:PollTNWAWSetting("SpeedTargetRain");

		Config:PollTNWAWSetting("ModSpeedEnabledFog");
		Config:PollTNWAWSetting("PhaseTimeoutFog");
		Config:PollTNWAWSetting("SpeedTargetFog");

		if self.CurrentSpeed == -1 then
			self.CurrentSpeed = getSandboxOptions():getOptionByName("ZombieLore.Speed"):getValue() or Config.SpeedLore;
		else
			local targetSpeed = self:TargetSpeed();

			if self.CurrentSpeed ~= targetSpeed then
				if self.PhaseChangeActive then
					if self.PhaseChangeTimer <= 0 then
						self.PhaseChangeActive = false;
	
						if self:MutationActive() then
							self:DoPhaseChange(targetSpeed);
							if isDebugEnabled() then self.Log("Phase change complete.") end
						else
							if isDebugEnabled() then self.Log("Phase timeout complete.") end
						end
					end
				else
					self.PhaseChangeActive = true;
					self.PhaseChangeTimer = self:PhaseTimeout();

					if not self:MutationActive() then
						self:DoPhaseChange(targetSpeed);
						if isDebugEnabled() then self.Log("Phase change complete. Timeout=" .. self.PhaseChangeTimer) end
					else
						if isDebugEnabled() then self.Log("Phasing towards target speed " .. targetSpeed .. ". Timeout=" .. self.PhaseChangeTimer) end
					end
	
				end
				self.PhaseChangeTimer = self.PhaseChangeTimer - 1;
			elseif self.PhaseChangeActive or self.PhaseChangeTimer > 0 then
				if isDebugEnabled() then self.Log("Target speed already reached. Cancelling phase timer.") end
				self.PhaseChangeActive = false;
				self.PhaseChangeTimer = 0;
			end
		end
	end,
	
	Toggle = function(enabled)
		if self.Enabled ~= enabled then
			if enabled then
				if isDebugEnabled() then self.Log("Initializing ... loading required settings") end
				self:Refresh();
			else
				if isDebugEnabled() then self.Log("Shutting down ...") end
			end
			self.Enabled = enabled;
		end
	end,
	
	ToggleNight = function(self, isNight)
		if self.NightEnabled ~= isNight then
			if isDebugEnabled() then self.Log("Night is " .. Format(isNight)) end
			self.NightEnabled = isNight;
		end
	end,
	
	ToggleRain = function(self, isRaining)
		if self.RainEnabled ~= isRaining then
			if isDebugEnabled() then self.Log("Rain is " .. Format(isRaining)) end
			self.RainEnabled = isRaining;
		end
	end,

	ToggleFog = function(self, isFoggy)
		if self.FogEnabled ~= isFoggy then
			if isDebugEnabled() then self.Log("Fog is " .. Format(isFoggy)) end
			self.FogEnabled = isFoggy;
		end
	end,

	OnZombieUpdate = function(self, zombie)
		local vMod = zombie:getModData();
		vMod.Speed = vMod.Speed or -1;
		if (vMod.Speed ~= self.CurrentSpeed) then
			vMod.Speed = self.CurrentSpeed;
			RefreshZombie(zombie);
		end
	end,
}
-- ============================================

local NightManager = {
	Enabled = false,
	Refresh = function(self)
		Config:PollTNWAWSetting("NightStartSpring");
		Config:PollTNWAWSetting("NightStartSummer");
		Config:PollTNWAWSetting("NightStartAutumn");
		Config:PollTNWAWSetting("NightStartWinter");
		Config:PollTNWAWSetting("NightEndSpring");
		Config:PollTNWAWSetting("NightEndSummer");
		Config:PollTNWAWSetting("NightEndAutumn");
		Config:PollTNWAWSetting("NightEndWinter");
	end,
	CheckSeason = {
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
		Spring = function(hr) return hr < Config.NightEndSpring or hr > Config.NightStartSpring end,
		Summer = function(hr) return hr < Config.NightEndSummer or hr > Config.NightStartSummer end,
		Autumn = function(hr) return hr < Config.NightEndAutumn or hr > Config.NightStartAutumn end,
		Winter = function(hr) return hr < Config.NightEndWinter or hr > Config.NightStartWinter end,
		IsNight = function(self, month, hour)
			local k = self.Switch[month];
			if (self[k]) then
				return self[k](hour);
			end
			return false;
		end,
	},
	IsNight = function(self)
		local gametime = GameTime:getInstance();
		local month = gametime:getMonth();
		local hour = getGameTime():getTimeOfDay();
	
		return self.CheckSeason:IsNight(month, hour);
	end,
}
-- ============================================

local WeatherManager = {
	Enabled = false,
	LastRain = 0.0,
	IsRaining = false,
	LastFog = 0.0,
	IsFoggy = false,

	Refresh = function(self)
		Config:PollTNWAWSetting("RainThreshold");
		Config:PollTNWAWSetting("FogThreshold");
	end,

	CheckRain = function(self)
		local currentRain = RainManager:getRainIntensity() * 100;

		if self.LastRain ~= currentRain then
			self.LastRain = currentRain;

			self.IsRaining = self.LastRain >= Config.RainThreshold;
	
			if isDebugEnabled() and not self.IsRaining and self.LastRain >= 1 then
				Log("Rain started. Threshold/Amount=" .. Config.RainThreshold .. "/" .. self.LastRain);
			end
		
			if ModSpeedManager.Enabled then ModSpeedManager:ToggleRain(self.IsRaining) end
		end
	end,

	CheckFog = function(self)
		local climateManager = getClimateManager();
		local currentFog = climateManager:getFogIntensity() * 100;

		if self.LastFog ~= currentFog then
			self.LastFog = currentFog;

			self.IsFoggy = self.LastFog >= Config.FogThreshold;

			if isDebugEnabled() and not self.IsFoggy and self.LastFog >= 1 then
				Log("Fog started. Threshold/Amount=" .. Config.FogThreshold .. "/" .. self.LastFog);
			end

			if ModSpeedManager.Enabled then ModSpeedManager:ToggleFog(self.IsFoggy) end
		end
	end,

	OnClimateTick = function(self)
		self:CheckRain();
		self:CheckFog();
	end,
}
-- ============================================

local Core = {
    Enabled = false,
	-- methods
	EvaluateModEnabled = function(self)
		local enabled = Config.ModEnabledNight or Config.ModEnabledWeather;
		if self.Enabled ~= enabled then
			if isDebugEnabled() then Log("Mod " .. Format(enabled)) end
			self.Enabled = enabled;

			ModSpeedManager.Enabled = enabled;
		end
	end,

	EvaluateModEnabledNight = function(self)
		if NightManager.Enabled ~= Config.ModEnabledNight then
			if Config.ModEnabledNight then
				NightManager:Refresh();
			end
			NightManager.Enabled = Config.ModEnabledNight;
			self:EvaluateModEnabled();
		end
	end,
	
	EvaluateModEnabledWeather = function(self)
		if WeatherManager.Enabled ~= Config.ModEnabledWeather then
			if Config.ModEnabledWeather then
				WeatherManager:Refresh();
			end
			WeatherManager.Enabled = Config.ModEnabledWeather;
			self:EvaluateModEnabled();
		end
	end,
	
	Refresh = function(self)
		Config:PollTNWAWSetting("ModEnabledNight");
		Config:PollTNWAWSetting("ModEnabledWeather");
		
		self:EvaluateModEnabledNight();
		self:EvaluateModEnabledWeather();
	end,
}
-- ============================================

local function EveryOneMinute()
    Core:Refresh()

	if NightManager.Enabled then NightManager:Refresh() end
	if WeatherManager.Enabled then WeatherManager:Refresh() end
	if ModSpeedManager.Enabled then ModSpeedManager:Refresh() end
end

local function EveryHours()
	local isNight = NightManager:IsNight();

	if ModSpeedManager.Enabled then ModSpeedManager:ToggleNight(isNight) end
end

local function OnClimateTick()
	if WeatherManager.Enabled then WeatherManager:OnClimateTick() end
end

local function OnZombieUpdate(zombie)
	if ((not isClient() and not isServer()) or (isClient() and not zombie:isRemoteZombie())) then
		local vMod = zombie:getModData();

		vMod.Ticks = vMod.Ticks or -1;
		if (vMod.Ticks >= Config.ZombieUpdateInterval) then
			RefreshZombie(zombie);
		else
			ModSpeedManager:OnZombieUpdate(zombie);
		end

		vMod.Ticks = vMod.Ticks + 1;
	end
end

local function OnStart()
    Core:Refresh()
end
-- ============================================
-- Events
Events.EveryOneMinute.Add(EveryOneMinute);
Events.EveryHours.Add(EveryHours);
Events.OnClimateTick.Add(OnClimateTick);
Events.OnZombieUpdate.Add(OnZombieUpdate);

Events.OnGameStart.Add(OnStart);
Events.OnServerStarted.Add(OnStart);