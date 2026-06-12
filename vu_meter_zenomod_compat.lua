ardour {
	["type"]    = "dsp",
	name        = "VU Meter - Compat",
	category    = "Metering",
	license     = "MIT",
	author      = "ZenoMOD",
	description = [[Dual-needle VU meter with inline display and 11 color themes.
Gradients emulated via slicing / concentric circles (standard Cairo only).

Metering:
- 3 channel modes: Stereo, Summed (L+R or L||R), Mid/Side
- Second-order ballistics with adjustable Rise Time and Overshoot
- Configurable reference level (-60 to 0 dB) for VU calibration
- Peak LED indicators per channel with adjustable Warn Level threshold
- Adjustable peak hold and needle hold timeout (1–10 s)
- Needle hold display: Off, On, Arc, or Needle
- Volume trim (-18 to +18 dB) with smooth gain ramping
- Mono track auto-detection (single needle, mirrored input)

Display:
- Single arc meter with distinct cool-blue (L/Mid) and warm-red (R/Side) needles
- 11 built-in color themes from the original ZenoMOD JSFX
- Theme-adaptive 3D gloss reflection and metallic pivot cap
- dB scale markings (-20 to +3), reference level marker, over-zone arc
- Antialiased rendering throughout
- Original JSFX code by ZenoMOD. Ported to Ardour Lua by sollapse via DeepSeek v4 Pro and Claude Opus 4.8]]
}

--------------------------------------------------------------------------------
-- Gradient Emulation Library
-- Recreates linear/radial gradient effects using only standard Cairo calls:
-- thin slices for linear, concentric circles for radial.
--------------------------------------------------------------------------------
local GRAD_STEPS = 24  -- slices/circles per gradient (quality vs CPU)

-- Fill a rect with a vertical linear gradient via horizontal slices.
-- x,y,w,h: rect bounds. c1/c2: RGBA 0..1 at top and bottom.
local function fill_lin_grad_v(ctx, x, y, w, h, r1,g1,b1,a1, r2,g2,b2,a2)
	local sh = h / GRAD_STEPS
	for i = 0, GRAD_STEPS - 1 do
		local t = (i + 0.5) / GRAD_STEPS
		ctx:rectangle(x, y + i * sh, w, sh + 0.5)  -- +0.5 to avoid hairline gaps
		ctx:set_source_rgba(
			r1 + (r2 - r1) * t,
			g1 + (g2 - g1) * t,
			b1 + (b2 - b1) * t,
			a1 + (a2 - a1) * t)
		ctx:fill()
	end
end

-- Fill a line segment with a linear gradient along its length.
-- Draws the line as overlapping short segments with interpolated color.
local function stroke_lin_grad(ctx, x1,y1, x2,y2, wd, r1,g1,b1,a1, r2,g2,b2,a2)
	local segs = math.max(6, math.floor(GRAD_STEPS * 0.5))
	local prev_x, prev_y = x1, y1
	for i = 1, segs do
		local t = i / segs
		local sx = x1 + (x2 - x1) * t
		local sy = y1 + (y2 - y1) * t
		ctx:begin_new_path()
		ctx:move_to(prev_x, prev_y)
		ctx:line_to(sx, sy)
		ctx:set_source_rgba(
			r1 + (r2 - r1) * (t - 0.5/segs),
			g1 + (g2 - g1) * (t - 0.5/segs),
			b1 + (b2 - b1) * (t - 0.5/segs),
			a1 + (a2 - a1) * (t - 0.5/segs))
		ctx:set_line_width(wd)
		ctx:stroke()
		prev_x, prev_y = sx, sy
	end
end

-- Fill a circle with a radial gradient via concentric filled circles.
-- Drawn largest-to-smallest: each ring's color (at full opacity) replaces
-- what's underneath, producing the correct radial falloff.
-- For alpha-fading gradients (glow), the concentric approximation is
-- close enough visually.
--
-- cx0,cy0,r0: inner circle definition (colour-stop offset 0.0)
-- cx1,cy1,r1: outer circle definition (colour-stop offset 1.0)
-- stops: array of {offset, r, g, b, a} tables, sorted by offset ascending
--        (offset 0.0 = inner circle, offset 1.0 = outer circle).
local function fill_radial_gradient(ctx, cx0,cy0,r0, cx1,cy1,r1, stops)
	local steps = GRAD_STEPS
	for i = 1, steps do
		local t = (i - 0.5) / steps          -- 1.0 = inner,  0.0 = outer
		-- interpolate circle geometry
		local cx = cx0 * t + cx1 * (1 - t)
		local cy = cy0 * t + cy1 * (1 - t)
		local r  = r0  * t + r1  * (1 - t)
		if r < 0.05 then r = 0.05 end
		-- interpolate colour between stops at offset (1 - t)
		local off = 1 - t                    -- 0.0 = inner,  1.0 = outer
		local cr, cg, cb, ca
		if #stops == 1 then
			cr, cg, cb, ca = stops[1][2], stops[1][3], stops[1][4], stops[1][5]
		else
			local lo, hi = 1, #stops
			for s = 2, #stops do
				if stops[s][1] >= off then hi = s; lo = s - 1; break end
			end
			if lo == hi then
				cr, cg, cb, ca = stops[lo][2], stops[lo][3], stops[lo][4], stops[lo][5]
			else
				local frac = (off - stops[lo][1]) / (stops[hi][1] - stops[lo][1])
				cr = stops[lo][2] + (stops[hi][2] - stops[lo][2]) * frac
				cg = stops[lo][3] + (stops[hi][3] - stops[lo][3]) * frac
				cb = stops[lo][4] + (stops[hi][4] - stops[lo][4]) * frac
				ca = stops[lo][5] + (stops[hi][5] - stops[lo][5]) * frac
			end
		end
		ctx:arc(cx, cy, r, 0, math.pi * 2)
		ctx:set_source_rgba(cr, cg, cb, ca)
		ctx:fill()
	end
end

--------------------------------------------------------------------------------
-- Color Themes (from ZenoMOD JSFX, 0xRRGGBB hex)
--------------------------------------------------------------------------------
local themes = {
	{  1, "Classic",   0x1E3C6E,0xFFFFB3,0x000000,0xF20000,0x333333,0xFF0000,0x000000,0x999999,0xFDB119,0xFDB119,0xFFFFB3,0xF21A1A,0xFFFFFF,0x000000,0x000000,0x000000,0xFAA802,0x285094,0x000000,0x000000 },
	{  2, "Knight",    0x121212,0x2F2F33,0xFFFFFF,0xF252BA,0xFFFFFF,0xF252BA,0x72DBFF,0x121218,0xBBBBCB,0x9898A5,0x252527,0xF252BA,0xFFFFFF,0xF252BA,0x72DBFF,0xFFFFFF,0x9898A5,0x505059,0x000000,0x000000 },
	{  3, "Purple",    0x100A1A,0x241738,0xA375FF,0xA375FF,0xA375FF,0xA375FF,0x2BBBFF,0x140D1F,0xFE51FF,0xFE51FF,0x140D1F,0xF051FC,0xBDB9C3,0x4F64D6,0x4F64D6,0x4F64D6,0xA375FF,0x513584,0x261C3C,0x261C3C },
	{  4, "Moss",      0x0A1912,0x132D22,0x698F7E,0x8F7E69,0x698F7E,0x8F7E69,0xBECFC8,0x091611,0x9966CC,0x9966CC,0x0E2219,0xAD84D6,0xC3D2CB,0x4B665A,0x5E8071,0x698F7E,0x8F7E69,0x23533E,0x10261C,0x173427 },
	{  5, "Moo",       0x474B57,0xDCE5E8,0x1D1F24,0x1D1F24,0x1D1F24,0x1D1F24,0x1D1F24,0xB1B4BB,0x9A9A9A,0x9A9A9A,0xD1D4D3,0xFF01CC,0xFFFFFF,0x1D1F24,0x1D1F24,0x1D1F24,0x1D1F24,0x666B7D,0xA7ACB2,0xD1D4D3 },
	{  6, "Warm",      0x1A1915,0xFFC353,0x000000,0xD01618,0x333333,0xD01618,0x603112,0xDF7E15,0x53FFC3,0x53FFC3,0xEFB343,0xFF0F1C,0xFF9ED4,0x000000,0x000000,0x000000,0xFFEDCB,0x6B5328,0xDF7E15,0xFFE189 },
	{  7, "Ivory",     0xCCC7B4,0xDDDAC7,0x5C5950,0xE44B3D,0x5C5950,0xE44B3D,0x545148,0xC6C4B3,0xFDB119,0xFDB119,0xD0CBB8,0xE44B2D,0xFFFFFF,0x68655C,0x68655C,0x68655C,0xFFFFFF,0xA19E91,0x000000,0x000000 },
	{  8, "Trooper",   0x757572,0x191919,0xD8D9DB,0xF43232,0xD8D9DB,0xD8D9DB,0xA3A29E,0x252525,0xDFE0E2,0xDFE0E2,0x2A2A2A,0xF43232,0xFFFFFF,0xA90000,0x9E9E9C,0xACADAF,0xBABABA,0x676765,0x222324,0x1E1F20 },
	{  9, "Ultimate",  0x2E2E2E,0x8D8D8D,0x2E2E2E,0x2E2E2E,0x2E2E2E,0x2E2E2E,0x2E2E2E,0x6D6D6D,0x00FE95,0x00FE95,0x7D7D7D,0x00FE95,0xD5D5D5,0x2E2E2E,0x2E2E2E,0x2E2E2E,0xD5D5D5,0x555555,0x6D6D6D,0x000000 },
	{ 10, "Mooncake",  0x2A2B31,0x161818,0x8F919B,0x04C373,0x5F6271,0x05F490,0x05F490,0x1A1B2B,0x989FB4,0x989FB4,0x272828,0x05F490,0xD4D4D5,0x3F414B,0x5F6271,0x989FB4,0x989FB4,0x3F4148,0x000000,0x000000 },
	{ 11, "Black",     0x000000,0x1A1A1A,0xFFFFFF,0xFFFFFF,0xFFFFFF,0xFFFFFF,0xFFFFFF,0x1A1A1A,0x00BFF5,0x00BFF5,0x262626,0x00BFF5,0xE5F8FE,0xE5F8FE,0xE5F8FE,0xCCCCCC,0xE5F8FE,0x5D5D76,0x1A1A26,0x22222D },
}

local C = { frame=3, meter=4, arc1=5, arc2=6, scl1=7, scl2=8,
            ndl=9, ndlshdw=10, ndlhold=11, archold=12, pk0=13, pk1=14,
            fontch=15, fontvu=16, fontpk=17, fontvol=18,
            dspl=19, botb=20, shdw3d=21, lght3d=22 }

local scale_dB  = { -20, -10, -7, -5, -3, -2, -1, 0, 1, 2, 3 }
local scale_pos = { 0, 0.165, 0.2641, 0.3519, 0.4626, 0.5284, 0.6022, 0.6849, 0.7779, 0.8822, 1.0 }

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local LN10 = math.log(10)
local function log10(x) return math.log(x) / LN10 end

local function hex2rgb(hex)
	return ((hex >> 16) & 0xFF) / 255,
	       ((hex >> 8)  & 0xFF) / 255,
	       ( hex        & 0xFF) / 255
end

local function db_to_pos(db)
	if db <= -20 then return 0 end
	if db >= 3   then return 1 end
	for i = 1, #scale_dB - 1 do
		if db <= scale_dB[i+1] then
			local t = (db - scale_dB[i]) / (scale_dB[i+1] - scale_dB[i])
			return scale_pos[i] + t * (scale_pos[i+1] - scale_pos[i])
		end
	end
	return 1
end

--------------------------------------------------------------------------------
-- Parameters
--------------------------------------------------------------------------------
function dsp_params()
	return {
		{ ["type"] = "input", name = "Theme",      min = 1, max = 11, default = 1,  integer = true, enum = true, scalepoints = {
			["Classic"]=1,["Knight"]=2,["Purple"]=3,["Moss"]=4,["Moo"]=5,
			["Warm"]=6,["Ivory"]=7,["Trooper"]=8,["Ultimate"]=9,["Mooncake"]=10,["Black"]=11 } },
		{ ["type"] = "input", name = "Mode",       min = 0, max = 2,  default = 0,  integer = true, enum = true, scalepoints = {
			["Stereo"]=0,["Summed"]=1,["Mid / Side"]=2 } },
		{ ["type"] = "input", name = "Ref Level",  min =-60,max = 0,  default =-18, unit = "dB" },
		{ ["type"] = "input", name = "Rise Time",  min = 50,max = 1000,default = 300,unit = "ms" },
		{ ["type"] = "input", name = "Overshoot",  min = 0, max = 5,   default = 1.25,unit = "%" },
		{ ["type"] = "input", name = "Volume",     min =-18,max = 18,  default = 0,   unit = "dB" },
		{ ["type"] = "input", name = "Needle Hold",min = 0, max = 3,   default = 3,   integer = true, enum = true, scalepoints = {
			["Off"]=0,["On"]=1,["Arc"]=2,["Needle"]=3 } },
		{ ["type"] = "input", name = "Peak Hold",       min = 1, max = 10,  default = 3,   unit = "s" },
		{ ["type"] = "input", name = "Needle Hold",     min = 1, max = 10,  default = 2,   unit = "s" },
		{ ["type"] = "input", name = "Warn Level", min =-20,max = 0,   default =-6,   unit = "dB" },
	}
end

function dsp_ioconfig()
	return { { audio_in = 2, audio_out = 2 }, { audio_in = 1, audio_out = 1 } }
end

--------------------------------------------------------------------------------
-- DSP state (identical to vu_meter_zenomod.lua)
--------------------------------------------------------------------------------
local AMP_DB_i = 1.0 / 8.68588963806504
local sr = 48000
local dt, damp, mom, dt_div_mom = 0, 0, 0, 0
local offset = 0.0074
local fact_up = 0.0
local ref_cached = nil

local nd_posL, nd_posR = 0, 0
local nd_speedL, nd_speedR = 0, 0

local peakL, peakR = -60, -60
local peak_holdL, peak_holdR = -60, -60
local peak_hold_cntL, peak_hold_cntR = 0, 0

local smp_sum_L, smp_sum_R = 0, 0
local smp_cnt = 0

local nd_holdL, nd_holdR = -60, -60
local nd_hold_cntL, nd_hold_cntR = 0, 0

local overL, overR = 0, 0
local led_hold_smps = 0
local warn_lin = 0.5012
local warn_cached = nil

local disp_dbL, disp_dbR = -60, -60

local gain_db = 0
local gain_lin = 1.0

local dpy_wr, dpy_hz = 0, 0

--------------------------------------------------------------------------------
local function nd2db(nd)
	local amp = nd * 0.1 + offset
	if amp > 0 then return 20.0 * log10(amp / 0.07589) end
	return -20.2
end

function dsp_init(rate)
	sr = rate
	dt = 10.0 / sr
	dpy_hz = sr / 30
	led_hold_smps = sr * 0.1
	update_ballistics(300, 1.25)
end

function update_ballistics(rise_ms, overshoot_pct)
	local zeta
	if overshoot_pct > 0.01 then
		local ln_os = math.log(overshoot_pct / 100)
		zeta = -ln_os / math.sqrt(math.pi * math.pi + ln_os * ln_os)
	else
		zeta = 1.0
	end
	local alpha  = -3.060 * zeta + 4.017
	local t_corr = (rise_ms * alpha) / 1000.0
	local wn
	if zeta < 1.0 then
		wn = -math.log(0.01 * math.sqrt(1 - zeta * zeta)) / (zeta * t_corr)
	else
		wn = 5.8 / t_corr
	end
	mom = 0.1 / (wn * wn)
	damp = math.exp(-2 * zeta * wn * (10.0 / sr))
	dt_div_mom = dt / math.max(mom, 0.00001)
end

function dsp_configure(ins, outs)
	self:shmem():allocate(7)
	self:shmem():clear()
end

--------------------------------------------------------------------------------
-- dsp_run (identical to vu_meter_zenomod.lua)
--------------------------------------------------------------------------------
function dsp_run(ins, outs, n_samples)
	local ctrl = CtrlPorts:array()
	if not ctrl then return end
	local mode      = math.floor(ctrl[2] or 0)
	local ref_level = ctrl[3] or -18
	local rise_ms   = ctrl[4] or 300
	local overshoot = ctrl[5] or 1.25
	local vol       = ctrl[6] or 0
	local pk_hold_s = ctrl[8] or 3
	local nd_hold_s = ctrl[9] or 2
	local warn_db   = ctrl[10] or -6

	if warn_db ~= warn_cached then
		warn_cached = warn_db
		warn_lin = 10 ^ (warn_db / 20)
	end
	if ref_level ~= ref_cached then
		ref_cached = ref_level
		fact_up = 10 ^ ((-ref_level - 10) / 20) * 0.3785
	end
	if vol ~= gain_db then
		gain_db = vol
		gain_lin = math.exp(gain_db * AMP_DB_i)
	end

	update_ballistics(rise_ms, overshoot)

	if not ins[1] then return end
	local mono = (ins[2] == nil)
	local il  = ins[1]:array()
	local ir  = mono and il or ins[2]:array()
	local ol  = outs[1] and outs[1]:array() or nil
	local orr = outs[2] and outs[2]:array() or nil
	local block_peakL, block_peakR = 0, 0

	for i = 1, n_samples do
		local sl = il[i] * gain_lin
		local sr = ir[i] * gain_lin
		if ol  then ol[i] = sl end
		if orr then orr[i] = sr end

		local mL, mR
		if mode == 2 then
			mL = (sl + sr) * 0.5; mR = (sl - sr) * 0.5
		elseif mode == 1 then
			mL = (sl + sr) * 0.5; mR = mL
		else
			mL = sl; mR = sr
		end

		local absL = mL >= 0 and mL or -mL
		local absR = mR >= 0 and mR or -mR

		smp_sum_L = smp_sum_L + absL
		smp_sum_R = smp_sum_R + absR
		smp_cnt = smp_cnt + 1

		if absL > block_peakL then block_peakL = absL end
		if absR > block_peakR then block_peakR = absR end

		if absL > warn_lin then overL = led_hold_smps end
		if absR > warn_lin then overR = led_hold_smps end
		overL = overL - 1
		overR = overR - 1

		if smp_cnt >= 10 then
			local smpL = smp_sum_L * 0.1
			local smpR = smp_sum_R * 0.1
			local force = smpL * fact_up - (nd_posL * 0.1 + offset)
			nd_speedL = nd_speedL + force * dt_div_mom
			nd_speedL = nd_speedL * damp
			nd_posL = nd_posL + nd_speedL * dt
			if nd_posL < 0 then nd_posL = 0; nd_speedL = 0 end
			if nd_posL > 1 then nd_posL = 1; nd_speedL = 0 end
			local forceR = smpR * fact_up - (nd_posR * 0.1 + offset)
			nd_speedR = nd_speedR + forceR * dt_div_mom
			nd_speedR = nd_speedR * damp
			nd_posR = nd_posR + nd_speedR * dt
			if nd_posR < 0 then nd_posR = 0; nd_speedR = 0 end
			if nd_posR > 1 then nd_posR = 1; nd_speedR = 0 end
			smp_sum_L, smp_sum_R = 0, 0
			smp_cnt = 0
		end
	end

	if block_peakL > 0 then
		local dbL = 20.0 * log10(math.max(block_peakL, 1e-7))
		if dbL > peakL then peakL = dbL end
	end
	if block_peakR > 0 then
		local dbR = 20.0 * log10(math.max(block_peakR, 1e-7))
		if dbR > peakR then peakR = dbR end
	end

	local pk_smps = pk_hold_s * sr
	if peakL > peak_holdL then peak_holdL = peakL; peak_hold_cntL = pk_smps end
	if peakR > peak_holdR then peak_holdR = peakR; peak_hold_cntR = pk_smps end
	peak_hold_cntL = peak_hold_cntL - n_samples
	peak_hold_cntR = peak_hold_cntR - n_samples
	if peak_hold_cntL <= 0 then peak_holdL = -60; peak_hold_cntL = 0 end
	if peak_hold_cntR <= 0 then peak_holdR = -60; peak_hold_cntR = 0 end

	disp_dbL = nd2db(nd_posL)
	disp_dbR = nd2db(nd_posR)

	local nd_smps = nd_hold_s * sr
	if disp_dbL > nd_holdL then nd_holdL = disp_dbL; nd_hold_cntL = nd_smps end
	if disp_dbR > nd_holdR then nd_holdR = disp_dbR; nd_hold_cntR = nd_smps end
	nd_hold_cntL = nd_hold_cntL - n_samples
	nd_hold_cntR = nd_hold_cntR - n_samples
	if nd_hold_cntL <= 0 then nd_holdL = -60; nd_hold_cntL = 0 end
	if nd_hold_cntR <= 0 then nd_holdR = -60; nd_hold_cntR = 0 end

	local sm = self:shmem():to_float(0):array()
	sm[1] = disp_dbL; sm[2] = disp_dbR
	sm[3] = nd_holdL; sm[4] = nd_holdR
	sm[5] = (overL > 0) and 1.0 or 0.0
	sm[6] = (overR > 0) and 1.0 or 0.0
	sm[7] = mono and 1.0 or 0.0

	dpy_wr = dpy_wr + n_samples
	if dpy_wr > dpy_hz then
		dpy_wr = dpy_wr % dpy_hz
		self:queue_draw()
	end

	peakL = peakL - n_samples * 0.0002
	if peakL < -60 then peakL = -60 end
	peakR = peakR - n_samples * 0.0002
	if peakR < -60 then peakR = -60 end
end

--------------------------------------------------------------------------------
-- Inline Display — all gradient effects emulated, drawn directly per-frame
--------------------------------------------------------------------------------
function render_inline(ctx, w, max_h)
	local ctrl = CtrlPorts:array()
	local sm = self:shmem():to_float(0):array()

	local theme_idx  = math.floor(ctrl[1] or 1)
	local ref_level  = ctrl[3] or -18
	local hold_mode  = math.floor(ctrl[7] or 3)
	local needle_dbL = sm[1] or -60
	local needle_dbR = sm[2] or -60
	local hold_dbL   = sm[3] or -60
	local hold_dbR   = sm[4] or -60
	local led_L      = (sm[5] or 0) > 0.5
	local led_R      = (sm[6] or 0) > 0.5
	local is_mono    = (sm[7] or 0) > 0.5

	if theme_idx < 1 then theme_idx = 1 end
	if theme_idx > 11 then theme_idx = 11 end

	local h = math.floor(w * 0.62)
	if h > max_h then h = max_h end
	if h < 40 then h = 40 end

	local cx = w * 0.5
	local cy = h * 0.84
	local radius = math.min(w * 0.46, h * 0.64)
	local arc_r = radius * 0.85

	-- Cairo enum aliases
	local AA_BEST  = 6
	local CAP_ROUND = 1

	local angle_min = math.pi * 0.25
	local angle_max = math.pi * 0.75
	local angle_range = angle_max - angle_min

	local function db_to_angle(db)
		return angle_max - db_to_pos(db) * angle_range
	end
	local function ang_xy(ang, r)
		return cx + r * math.cos(ang), cy - r * math.sin(ang)
	end

	local function set_hex_source(c, hex, alpha)
		local r, g, b = hex2rgb(hex)
		c:set_source_rgba(r, g, b, alpha or 1.0)
	end

	--------------------------------------------------------------------------------
	-- Static layer (drawn directly every frame — ImageSurface not available
	-- in the inline-display sandbox)
	--------------------------------------------------------------------------------
	local th = themes[theme_idx]

	-- 1. Frame background
	ctx:rectangle(0, 0, w, h)
	set_hex_source(ctx, th[C.frame])
	ctx:fill()

	-- 2. Meter background rounded rect
	local mw = w * 0.93
	local my = h * 0.06
	local mh = cy - my
	local mx = (w - mw) * 0.5
	local cr = math.min(mw, mh) * 0.1

	ctx:begin_new_sub_path()
	ctx:arc(mx + mw - cr, my + cr, cr, -math.pi*0.5, 0)
	ctx:arc(mx + mw - cr, my + mh - cr, cr, 0, math.pi*0.5)
	ctx:arc(mx + cr, my + mh - cr, cr, math.pi*0.5, math.pi)
	ctx:arc(mx + cr, my + cr, cr, math.pi, math.pi*1.5)
	ctx:close_path()
	set_hex_source(ctx, th[C.meter])
	ctx:fill()

	-- 3. 3D lighting (shadow + gloss)
	local shdw_r, shdw_g, shdw_b = hex2rgb(th[C.shdw3d])

	-- top shadow (clipped to meter rect)
	ctx:save()
	ctx:rectangle(mx, my, mw, mh)
	ctx:clip()
	for i = 0, 2 do
		local alpha = 0.08 + i * 0.025
		local shadow_h = mh * (0.28 - i * 0.04)
		fill_lin_grad_v(ctx, mx, my, mw, shadow_h,
			shdw_r, shdw_g, shdw_b, alpha,
			shdw_r, shdw_g, shdw_b, 0)
	end
	ctx:restore()

	-- gloss highlight: soft warm reflection tinted by the meter background.
	-- blend ratio adapts to background brightness — subtle on dark themes,
	-- more visible on light themes.
	local gloss_cx = cx
	local gloss_cy = cy - arc_r * 0.55
	local gloss_r = arc_r * 0.85
	local mbr, mbg, mbb = hex2rgb(th[C.meter])
	-- perceived luminance of the meter background
	local lum = 0.299 * mbr + 0.587 * mbg + 0.114 * mbb
	-- blend: on dark backgrounds mostly meter-bg, on light backgrounds more white
	local blend = 0.12 + lum * 0.55  -- 0.12 (dark) .. 0.67 (light)
	local gir = math.min(mbr * (1 - blend) + blend, 1)
	local gig = math.min(mbg * (1 - blend) + blend, 1)
	local gib = math.min(mbb * (1 - blend) + blend, 1)
	for i = 0, 2 do
		local alpha = 0.03 + i * 0.02
		local gr = gloss_r * (0.94 - i * 0.06)
		fill_radial_gradient(ctx,
			gloss_cx, gloss_cy, gr * 0.4,    -- wide inner circle for soft falloff
			gloss_cx, gloss_cy, gr,
			{{0, gir, gig, gib, alpha},
			 {1, gir, gig, gib, 0}})
	end

	-- 4. Arc rings
	ctx:set_antialias(AA_BEST)
	ctx:set_line_width(1.2)
	ctx:begin_new_sub_path()
	ctx:arc(cx, cy, arc_r, -angle_max, -angle_min)
	set_hex_source(ctx, th[C.arc1])
	ctx:stroke()

	local over_ang = db_to_angle(0)
	set_hex_source(ctx, th[C.arc2])
	for i = 1, 3 do
		ctx:begin_new_sub_path()
		ctx:arc(cx, cy, arc_r + i, -over_ang, -angle_min)
		ctx:stroke()
	end

	-- 5. Scale markings + labels
	ctx:set_antialias(AA_BEST)
	ctx:set_font_size(math.min(w * 0.04, 10))
	for i = 1, #scale_dB do
		local dbv = scale_dB[i]
		local ang = db_to_angle(dbv)
		local x1, y1 = ang_xy(ang, arc_r)
		local x2, y2 = ang_xy(ang, arc_r * 1.1)
		ctx:begin_new_path()
		ctx:move_to(x1, y1)
		ctx:line_to(x2, y2)
		if dbv >= 0 then set_hex_source(ctx, th[C.scl2]) else set_hex_source(ctx, th[C.scl1]) end
		ctx:set_line_width(1.0)
		ctx:stroke()
		if i % 2 == 1 or dbv == 0 or dbv == 3 then
			local lx, ly = ang_xy(ang, arc_r * 1.18)
			ctx:move_to(lx - 8, ly - 3)
			if dbv >= 0 then set_hex_source(ctx, th[C.scl2]) else set_hex_source(ctx, th[C.scl1]) end
			ctx:show_text(tostring(dbv))
		end
	end

	-- 6. Arc rings (continued)
	-- (cap moved to dynamic section — must draw over needles)

	--------------------------------------------------------------------------------
	-- Dynamic elements drawn every frame below this point (always on ctx)
	--------------------------------------------------------------------------------
	local th2 = themes[theme_idx]

	-- Local aliases (re-declared here for clarity; same values as cache build)
	local mw = w * 0.93
	local my = h * 0.06
	local mh = cy - my
	local mx = (w - mw) * 0.5

	-- 6. Reference level dashed line
	--------------------------------------------------------------------------------
	ctx:save()
	local r_ang = db_to_angle(ref_level)
	local rx1, ry1 = ang_xy(r_ang, arc_r * 0.93)
	local rx2, ry2 = ang_xy(r_ang, arc_r * 1.13)
	set_hex_source(ctx, th2[C.arc2], 0.55)
	ctx:set_line_width(2.0)
	local dx, dy = rx2 - rx1, ry2 - ry1
	local seg_len, gap_len = 3.0, 4.0
	local total = math.sqrt(dx*dx + dy*dy)
	local n_seg = math.floor(total / (seg_len + gap_len))
	if n_seg > 0 then
		local ux, uy = dx / total, dy / total
		for s = 0, n_seg - 1 do
			local t0 = s * (seg_len + gap_len)
			local t1 = t0 + seg_len
			if t1 > total then t1 = total end
			ctx:begin_new_path()
			ctx:move_to(rx1 + ux * t0, ry1 + uy * t0)
			ctx:line_to(rx1 + ux * t1, ry1 + uy * t1)
			ctx:stroke()
		end
	end
	ctx:restore()

	--------------------------------------------------------------------------------
	-- 7. Hold lines
	--------------------------------------------------------------------------------
	local ndlr, ndlg, ndlb = hex2rgb(th2[C.ndl])
	local ndl_Lr = ndlr * 0.5
	local ndl_Lg = ndlg * 0.85
	local ndl_Lb = math.min(ndlb * 1.3, 1.0)
	local lbl_Lr = math.max(ndl_Lr, 0.35)
	local lbl_Lg = math.max(ndl_Lg, 0.60)
	local lbl_Lb = math.max(ndl_Lb, 0.75)
	local ndl_Rr = math.min(ndlr * 1.4, 1.0)
	local ndl_Rg = ndlg * 0.35
	local ndl_Rb = ndlb * 0.3
	local lbl_Rr = math.max(ndl_Rr, 0.70)
	local lbl_Rg = math.max(ndl_Rg, 0.25)
	local lbl_Rb = math.max(ndl_Rb, 0.20)

	if hold_mode >= 2 then
		if hold_dbL > -20 then
			local ha = db_to_angle(hold_dbL)
			local hx, hy = ang_xy(ha, arc_r * 0.87)
			ctx:save()
			ctx:begin_new_path(); ctx:move_to(cx, cy); ctx:line_to(hx, hy)
			ctx:set_source_rgba(ndl_Lr, ndl_Lg, ndl_Lb, 0.5)
			ctx:set_line_width(2.5); ctx:set_line_cap(CAP_ROUND); ctx:stroke()
			ctx:restore()
		end
		if not is_mono and hold_dbR > -20 then
			local ha = db_to_angle(hold_dbR)
			local hx, hy = ang_xy(ha, arc_r * 0.84)
			ctx:save()
			ctx:begin_new_path(); ctx:move_to(cx, cy); ctx:line_to(hx, hy)
			ctx:set_source_rgba(ndl_Rr, ndl_Rg, ndl_Rb, 0.4)
			ctx:set_line_width(2.0); ctx:set_line_cap(CAP_ROUND); ctx:stroke()
			ctx:restore()
		end
	end

	--------------------------------------------------------------------------------
	-- 8. Needles — emulated linear gradient along the needle line
	--------------------------------------------------------------------------------
	local function draw_needle(db, len_ratio, width, r, g, b, shadow_alpha)
		local ang = db_to_angle(math.max(db, -20))
		local nx, ny = ang_xy(ang, arc_r * len_ratio)

		-- shadow
		ctx:save()
		ctx:begin_new_path(); ctx:move_to(cx + 1.5, cy - 1.5); ctx:line_to(nx + 1.5, ny - 1.5)
		set_hex_source(ctx, th2[C.ndlshdw], shadow_alpha)
		ctx:set_line_width(width * 0.8); ctx:set_line_cap(CAP_ROUND); ctx:stroke()
		ctx:restore()

		-- needle with emulated linear gradient (overlapping line segments)
		stroke_lin_grad(ctx, cx, cy, nx, ny, width,
			r, g, b, 1.0,
			math.min(r*1.15,1), g*0.75, b*0.7, 0.85)
	end

	draw_needle(needle_dbL, 0.89, 2.5, ndl_Lr, ndl_Lg, ndl_Lb, 0.35)
	if not is_mono then
		draw_needle(needle_dbR, 0.84, 2.0, ndl_Rr, ndl_Rg, ndl_Rb, 0.25)
	end

	--------------------------------------------------------------------------------
	-- 9. Center pivot cap — emulated radial metallic gradient
	--------------------------------------------------------------------------------
	-- 8. Center pivot cap (theme-derived metallic dome — over needle bases)
	--    Colours are derived from the meter background so the dome looks like
	--    polished metal reflecting the meter face on every theme.
	local cap_r = radius * 0.16
	local mbr, mbg, mbb = hex2rgb(th2[C.meter])
	-- dark edge: strongly darkened meter-bg (keeps the theme's hue)
	local dkr, dkg, dkb = mbr * 0.12, mbg * 0.12, mbb * 0.14
	-- mid-tone: mix dark + bright
	local mdr, mdg, mdb = mbr * 0.28, mbg * 0.28, mbb * 0.32
	-- highlight: bright metallic reflection (meter-bg + white)
	local hlr, hlg, hlb = math.min(mbr * 0.55 + 0.45, 1), math.min(mbg * 0.55 + 0.45, 1), math.min(mbb * 0.55 + 0.45, 1)

	ctx:save()
	ctx:arc(cx, cy, cap_r * 1.12, 0, math.pi * 2)
	ctx:set_source_rgba(dkr * 0.4, dkg * 0.4, dkb * 0.4, 1.0)  -- rim slightly darker than dome edge
	ctx:fill()
	ctx:save()
	ctx:arc(cx, cy, cap_r, 0, math.pi * 2)
	ctx:clip()
	fill_radial_gradient(ctx,
		cx - cap_r*0.35, cy - cap_r*0.35, cap_r*0.25,
		cx, cy, cap_r * 1.2,
		{{0.0, hlr, hlg, hlb, 1.0},
		 {0.5, mdr, mdg, mdb, 1.0},
		 {1.0, dkr, dkg, dkb, 1.0}})
	ctx:restore()
	ctx:restore()

	--------------------------------------------------------------------------------
	-- 9. Peak LEDs — emulated radial gradients
	--------------------------------------------------------------------------------
	local led_r = radius * 0.05
	local led_y = cy - radius * 0.38
	local p0r, p0g, p0b = hex2rgb(th2[C.pk0])
	local p1r, p1g, p1b = hex2rgb(th2[C.pk1])

	local function draw_led(lx, ly, is_on)
		-- dark bezel
		ctx:save()
		ctx:arc(lx, ly, led_r * 1.3, 0, math.pi * 2)
		ctx:set_source_rgba(0.05, 0.05, 0.06, 1.0)
		ctx:fill()
		ctx:restore()

		-- halo when lit
		if is_on then
			fill_radial_gradient(ctx,
				lx, ly, 0,              -- inner (point at LED centre)
				lx, ly, led_r * 2.8,    -- outer (glow radius)
				{{0, p1r, p1g, p1b, 0.85},
				 {1, p1r, p1g, p1b, 0}})
		end

		-- lamp body
		local br, bg, bb
		if is_on then br, bg, bb = p1r, p1g, p1b else br, bg, bb = p0r*0.5, p0g*0.5, p0b*0.5 end
		fill_radial_gradient(ctx,
			lx - led_r*0.35, ly - led_r*0.35, led_r*0.05,  -- inner (highlight offset)
			lx, ly, led_r,                                   -- outer
			{{0, math.min(br*1.4,1), math.min(bg*1.4,1), math.min(bb*1.4,1), 1.0},
			 {1, br*0.5, bg*0.5, bb*0.5, 1.0}})
	end

	if is_mono then
		draw_led(cx, led_y, led_L)
	else
		draw_led(cx - radius * 0.74, led_y, led_L)
		draw_led(cx + radius * 0.74, led_y, led_R)
	end

	--------------------------------------------------------------------------------
	-- 11. Labels
	--------------------------------------------------------------------------------
	if w > 50 then
		local pk_font = math.min(w * 0.045, 9)
		local pkw = pk_font * 2.4
		local pky = led_y + led_r + pk_font + 1
		ctx:save()
		ctx:set_font_size(pk_font)
		set_hex_source(ctx, th2[C.fontpk])
		if is_mono then
			ctx:move_to(cx - pkw * 0.5, pky)
			ctx:show_text("PEAK")
		else
			ctx:move_to(cx - radius * 0.74 - pkw * 0.5, pky)
			ctx:show_text("PEAK")
			ctx:move_to(cx + radius * 0.74 - pkw * 0.5, pky)
			ctx:show_text("PEAK")
		end
		ctx:restore()

		-- channel labels
		ctx:save()
		ctx:set_font_size(math.min(w * 0.05, 11))
		local cly = h - 3
		if is_mono then
			set_hex_source(ctx, th2[C.fontch])
			ctx:move_to(mx + 3, cly)
			ctx:show_text("MONO")
		else
			local mode_idx = math.floor(ctrl[2] or 0)
			local llab, rlab = "L", "R"
			if mode_idx == 2 then llab, rlab = "M", "S" end
			ctx:set_source_rgba(lbl_Lr, lbl_Lg, lbl_Lb, 1.0)
			ctx:move_to(mx + 3, cly)
			ctx:show_text(llab)
			ctx:set_source_rgba(lbl_Rr, lbl_Rg, lbl_Rb, 1.0)
			ctx:move_to(mx + mw - 9, cly)
			ctx:show_text(rlab)
		end
		ctx:restore()
	end

	return { w, h }
end
