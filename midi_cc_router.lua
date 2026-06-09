ardour {
	["type"]    = "dsp",
	name        = "MIDI CC Router",
	category    = "Utility",
	license     = "MIT",
	author      = "sollapse",
	description = [[
Routes incoming MIDI CC messages to any automation parameter in real time.
All 16 MIDI channels x 128 CC numbers are supported (2048 possible mappings).
Configure mappings with the "MIDI CC Map Editor" EditorAction script.
Place this plugin on a MIDI track/bus that receives your hardware controller.
Config file: <session_folder>/midi_cc_map.lua
Config reloads automatically every 5 seconds while playing.
**Code generated using Claude Sonnet 4.6 & Opus 4.8**
]]
}

function dsp_ioconfig ()
	return { { midi_in = 1, midi_out = 1, audio_in = 0, audio_out = 0 } }
end

function dsp_params ()
	return {
		{ ["type"] = "input", name = "Active", min = 0, max = 1, default = 1,
		  integer = true, toggled = true, logarithmic = false },
	}
end

-- ── module-level state ────────────────────────────────────────────────────────

local samplerate     = 48000
local config_path    = nil
-- maps[ch_key][cc] = list of { ac=AutomationControl, p_min=float, scale=float }
--   ch_key 0..15 = MIDI channel 0-based
--   ch_key 16    = any-channel wildcard (config ch=0)
local maps           = {}
local reload_count   = 0
local RELOAD_SAMPLES = 0   -- set in dsp_init (samplerate * 5)

-- ── helpers ───────────────────────────────────────────────────────────────────

local function nilobj (x)
	if x == nil then return true end
	local ok, r = pcall (function () return x:isnil () end)
	return ok and r or false
end

-- Look up strip-level AutomationControl by display label.
local function find_strip_ac (r, name)
	if     name == "Fader (Gain)"  then return r:gain_control ()
	elseif name == "Trim"          then return r:trim_control ()
	elseif name == "Mute"          then return r:mute_control ()
	elseif name == "Pan (Azimuth)" then return r:pan_azimuth_control ()
	elseif name == "Pan (Width)"   then return r:pan_width_control ()
	else
		-- Send: <label>
		local sname = name:match ("^Send: (.+)$")
		if sname then
			for si = 0, 31 do
				local sc = r:send_level_controllable (si, false)
				if nilobj (sc) then break end
				local n = r:send_name (si)
				local key = (n ~= "" and n or tostring (si + 1))
				if key == sname then return sc end
			end
		end
	end
	return nil
end

-- Find an AutomationControl for a plugin parameter by display name.
-- Returns ac, lo, hi
-- param_name format: "PluginDisplayName > ParamLabel"
local function find_plugin_ac (r, param_name)
	local pname, plabel = param_name:match ("^(.+) > (.+)$")
	if not pname then return nil end

	local pi = 0
	while true do
		local proc = r:nth_plugin (pi)
		if nilobj (proc) then break end

		if proc:display_name () == pname then
			local ins = proc:to_insert ()
			if not nilobj (ins) then
				local plug = ins:plugin (0)
				if not nilobj (plug) then
					local n_in = 0
					for j = 0, plug:parameter_count () - 1 do
						if plug:parameter_is_control (j) and plug:parameter_is_input (j) then
							if plug:parameter_label (j) == plabel then
								-- Build Evoral.Parameter for this control-input index,
								-- then get the real AutomationControl from to_automatable()
								local eparam = Evoral.Parameter (
									ARDOUR.AutomationType.PluginAutomation, 0, n_in)
								local auto = proc:to_automatable ()
								if not nilobj (auto) then
									local ac = auto:automation_control (eparam, false)
									if not nilobj (ac) then
										local _, _, desc = ARDOUR.LuaAPI.plugin_automation (ins, n_in)
										local lo = (desc and type(desc.lower)=="number") and desc.lower or 0.0
										local hi = (desc and type(desc.upper)=="number") and desc.upper or 1.0
										return ac, lo, hi
									end
								end
							end
							n_in = n_in + 1
						end
					end
				end
			end
		end
		pi = pi + 1
	end
	return nil
end

-- Find a setter closure + range for a route+param entry.
-- Returns setter_fn, lower, upper
local function find_ac (route_name, param_name)
	local r = Session:route_by_name (route_name)
	if nilobj (r) then return nil end

	-- plugin parameter ("Plugin > Param" format)
	if param_name:find (" > ", 1, true) then
		local ac, lo, hi = find_plugin_ac (r, param_name)
		if ac then
			return function (v)
				ac:set_value (v, PBD.GroupControlDisposition.NoGroup)
			end, lo, hi
		end
		return nil
	end

	-- strip control
	local ac = find_strip_ac (r, param_name)
	if ac and not nilobj (ac) then
		local lo_ok, lo = pcall (function () return ac:lower () end)
		local hi_ok, hi = pcall (function () return ac:upper () end)
		return function (v)
			ac:set_value (v, PBD.GroupControlDisposition.NoGroup)
		end,
		(lo_ok and type(lo)=="number" and lo or nil),
		(hi_ok and type(hi)=="number" and hi or nil)
	end

	return nil
end

-- ── config loading ────────────────────────────────────────────────────────────

local function load_config ()
	if not config_path then return end

	local content = ARDOUR.LuaAPI.file_get_contents (config_path)
	if type (content) ~= "string" or content == "" then maps = {}; return end
	local fn = load (content)
	if type (fn) ~= "function" then maps = {}; return end
	local ok2, data = pcall (fn)
	if not ok2 or type (data) ~= "table" then maps = {}; return end

	local new_maps = {}

	for _, m in ipairs (data) do
		local ok3, setter, ret_lo, ret_hi = pcall (find_ac, m.route, m.param)
		if ok3 and type (setter) == "function" then
			-- prefer explicit range from config, then descriptor, then safe defaults
			local p_min = (m.min ~= nil)              and m.min
			           or (type(ret_lo)=="number"     and ret_lo)
			           or 0.0
			local p_max = (m.max ~= nil)              and m.max
			           or (type(ret_hi)=="number"     and ret_hi)
			           or 1.0
			-- ch=0 in config → any channel, stored under key 16
			-- ch=1..16 → 0-based key 0..15
			local ch_key = (m.ch == 0) and 16 or (m.ch - 1)
			local cc     = m.cc

			if not new_maps[ch_key]     then new_maps[ch_key]     = {} end
			if not new_maps[ch_key][cc] then new_maps[ch_key][cc] = {} end
			table.insert (new_maps[ch_key][cc], {
				setter = setter,
				p_min  = p_min,
				scale  = (p_max - p_min) / 127.0,
			})
		end
	end

	maps = new_maps
end

-- ── apply mappings for one CC value ──────────────────────────────────────────

local function apply (mlist, val)
	for _, m in ipairs (mlist) do
		m.setter (m.p_min + m.scale * val)
	end
end

-- ── DSP callbacks ─────────────────────────────────────────────────────────────

function dsp_init (rate)
	samplerate     = rate
	RELOAD_SAMPLES = rate * 5   -- reload every 5 seconds
	config_path    = Session:path () .. "/midi_cc_map.cfg"
	pcall (load_config)
end

function dsp_run (_, _, n_samples)
	local ctrl   = CtrlPorts:array ()
	local active = ctrl[1] > 0.5

	-- periodic config reload
	reload_count = reload_count + n_samples
	if reload_count >= RELOAD_SAMPLES then
		reload_count = 0
		pcall (load_config)
	end

	-- midiin is a flat array of events: midiin[i] = { time = T, data = {b1,b2,b3} }
	local n = #midiin
	for i = 1, n do
		local ev = midiin[i]
		-- passthrough
		midiout[i] = ev

		if active then
			local d = ev["data"]
			if d and #d == 3 and (d[1] & 0xF0) == 0xB0 then
				local ch  = d[1] & 0x0F   -- 0-based MIDI channel
				local cc  = d[2]
				local val = d[3]
				local cm  = maps[ch]
				if cm and cm[cc] then pcall (apply, cm[cc], val) end
				local am  = maps[16]       -- any-channel wildcard
				if am and am[cc] then pcall (apply, am[cc], val) end
			end
		end
	end
end
