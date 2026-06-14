-- ============================================================
--  midi_cc_map.lua  --  EditorAction
--  UI for configuring MIDI CC -> automation parameter mappings.
--  Saves <session_folder>/midi_cc_map.cfg
--  Config format: { ch=N, cc=N, route="name", param="label", min=N, max=N }
--  ch: 0 = any channel, 1-16 = specific. min/max nil = natural range.
-- ============================================================
ardour {
  ["type"]    = "EditorAction",
  name        = "MIDI CC Map Editor",
  license     = "MIT",
  author      = "sollapse ",
  description = [[
    Add, edit and save MIDI CC -> automation parameter mappings
    for the MIDI CC Router DSP plugin. Saves midi_cc_map.cfg inside
    the session folder. The DSP plugin auto-reloads it every 5 sec.
    **Code generated using Claude Sonnet 4.6 & Opus 4.8**
  ]]
}

function icon (params) return function (ctx, width, height, fg)
  local cx  = width  * 0.5
  local cy  = height * 0.5
  local r   = math.min (width, height)

  local function rrect (x, y, w, h, rr)
    ctx:move_to (x + rr, y)
    ctx:line_to (x + w - rr, y)
    ctx:arc (x + w - rr, y + rr,      rr,  -math.pi/2, 0)
    ctx:line_to (x + w, y + h - rr)
    ctx:arc (x + w - rr, y + h - rr,  rr,  0,          math.pi/2)
    ctx:line_to (x + rr, y + h)
    ctx:arc (x + rr,     y + h - rr,  rr,  math.pi/2,  math.pi)
    ctx:line_to (x, y + rr)
    ctx:arc (x + rr,     y + rr,      rr, -math.pi,   -math.pi/2)
    ctx:close_path ()
  end

  -- fill background
  rrect (0, 0, width, height, r * 0.10)
  ctx:set_source_rgba (0.15, 0.15, 0.18, 1.0)
  ctx:fill ()

  -- vertical centers for the 3 rows (dots)
  local dot_cys = { cy - r * 0.21, cy, cy + r * 0.21 }

  -- === LEFT side: 3 blue input port dots ===
  local dot_r = r * 0.058
  local lx    = cx - r * 0.28
  for _, dy in ipairs (dot_cys) do
    ctx:arc (lx, dy, dot_r, 0, 2 * math.pi)
    ctx:set_source_rgba (0.45, 0.75, 1.0, 1.0)
    ctx:fill ()
  end

  -- === RIGHT side: 3 green bars (shifted down from dot rows) ===
  local bx      = cx + r * 0.30
  local bw      = r  * 0.085
  local bh      = r  * 0.16
  local bar_off = r  * 0.10               -- bars sit below corresponding dots
  local bar_cys = {}                      -- bar center Ys
  for i = 1, 3 do
    local bcy = dot_cys[i] + bar_off
    bar_cys[i] = bcy
    local by = bcy - bh * 0.5
    rrect (bx - bw * 0.5, by, bw, bh, bw * 0.22)
    ctx:set_source_rgba (0.30, 0.88, 0.45, 0.95)
    ctx:fill ()
  end

  -- === center arrow (points at gap between top & middle bar) ===
  local arrow_y = (bar_cys[1] + bar_cys[2]) * 0.5
  local ax1 = cx - r * 0.10
  local ax2 = cx + r * 0.22
  local ah  = r  * 0.09
  local aw  = r  * 0.09
  ctx:set_line_width (r * 0.055)
  ctx:set_source_rgba (0.90, 0.90, 0.92, 0.80)
  ctx:move_to (ax1, arrow_y)
  ctx:line_to (ax2 - aw * 0.6, arrow_y)
  ctx:stroke ()
  ctx:move_to (ax2 - aw, arrow_y - ah)
  ctx:line_to (ax2,      arrow_y)
  ctx:line_to (ax2 - aw, arrow_y + ah)
  ctx:close_path ()
  ctx:fill ()
end end

function factory () return function ()
  local ok, err = pcall (function ()

  -- ── nil-safe helper ──────────────────────────────────────────────────
  local function nilobj (x)
    if x == nil then return true end
    local ok2, r = pcall (function () return x:isnil () end)
    return ok2 and r or false
  end

  -- ── config file path ─────────────────────────────────────────────────
  local function cfg_path ()
    local p = Session:path ()
    if p:sub (-1) ~= "/" and p:sub (-1) ~= "\\" then p = p .. "/" end
    return p .. "midi_cc_map.cfg"
  end

  -- ── load / save ───────────────────────────────────────────────────────
  local function load_cfg ()
    local ok2, loader = pcall (loadfile, cfg_path ())
    if not ok2 or type (loader) ~= "function" then return {} end
    local ok3, t = pcall (loader)
    return (ok3 and type (t) == "table") and t or {}
  end

  local function save_cfg (list)
    local f = io.open (cfg_path (), "w")
    if not f then
      LuaDialog.Message ("MIDI CC Map Editor",
        "Could not write:\n" .. cfg_path (),
        LuaDialog.MessageType.Error, LuaDialog.ButtonType.Close):run ()
      return false
    end
    f:write ("return {\n")
    for _, m in ipairs (list) do
      local min_s = (m.min ~= nil) and tostring (m.min) or "nil"
      local max_s = (m.max ~= nil) and tostring (m.max) or "nil"
      f:write (string.format (
        "  { ch=%d, cc=%d, route=%q, param=%q, min=%s, max=%s },\n",
        m.ch, m.cc, m.route, m.param, min_s, max_s))
    end
    f:write ("}\n")
    f:close ()
    return true
  end

  -- ── enumerate routes and their automatable params ─────────────────────
  local STRIP_PARAMS = {
    "Fader (Gain)", "Trim", "Mute", "Pan (Azimuth)", "Pan (Width)"
  }
  local route_params = {}   -- route_name -> { label, ... }

  for r in Session:get_routes ():iter () do
    if not (r:is_monitor () or r:is_auditioner ()) then
      local rn = r:name ()
      route_params[rn] = {}
      local function add (lbl) table.insert (route_params[rn], lbl) end

      local strip_fns = {
        ["Fader (Gain)"]  = function () return r:gain_control () end,
        ["Trim"]          = function () return r:trim_control () end,
        ["Mute"]          = function () return r:mute_control () end,
        ["Pan (Azimuth)"] = function () return r:pan_azimuth_control () end,
        ["Pan (Width)"]   = function () return r:pan_width_control () end,
      }
      for _, lbl in ipairs (STRIP_PARAMS) do
        if not nilobj (strip_fns[lbl]()) then add (lbl) end
      end
      for si = 0, 31 do
        local sc = r:send_level_controllable (si, false)
        if nilobj (sc) then break end
        local sn = r:send_name (si)
        add ("Send: " .. (sn ~= "" and sn or tostring (si + 1)))
      end
      local pi = 0
      while true do
        local proc = r:nth_plugin (pi)
        if nilobj (proc) then break end
        local ins = proc:to_insert ()
        if not nilobj (ins) then
          local plug = ins:plugin (0)
          if not nilobj (plug) then
            local n = 0
            for j = 0, plug:parameter_count () - 1 do
              if plug:parameter_is_control (j) then
                local lbl = plug:parameter_label (j)
                if plug:parameter_is_input (j) and lbl ~= "hidden"
                    and lbl:sub (1, 1) ~= "#" then
                  add (proc:display_name () .. " > " .. lbl)
                end
                n = n + 1
              end
            end
          end
        end
        pi = pi + 1
      end
    end
  end

  -- ── helpers ───────────────────────────────────────────────────────────
  -- Build the hub dropdown: "  [+ New mapping]"=0, "01. CC7 ch:1 -> ..."=idx
  local function make_sel_opts (list)
    local opts = { ["  [+ New mapping ]"] = 0 }
    for i, m in ipairs (list) do
      local ch_s  = (m.ch == 0) and "any" or tostring (m.ch)
      local sc_s  = (m.min ~= nil) and string.format (" [%.3g..%.3g]", m.min, m.max) or ""
      local key   = string.format ("%02d. CC%d ch:%s  ->  %s / %s%s",
                      i, m.cc, ch_s, m.route, m.param, sc_s)
      opts[key] = i
    end
    return opts
  end

  local function dup_except (list, skip_idx, ch, cc, route, param)
    for i, m in ipairs (list) do
      if i ~= skip_idx and m.ch == ch and m.cc == cc
          and m.route == route and m.param == param then
        return true
      end
    end
    return false
  end

  -- Open the add/edit form. existing=nil → add new; existing=table → edit.
  -- Returns new mapping table on confirm, nil on cancel.
  local function open_form (rn, existing)
    local plist = route_params[rn] or {}
    if #plist == 0 then
      LuaDialog.Message ("MIDI CC Map Editor",
        "No automatable parameters found on: " .. rn,
        LuaDialog.MessageType.Warning, LuaDialog.ButtonType.Close):run ()
      return nil
    end

    -- parameter dropdown
    -- for edits, prepend "(keep current)" so it sorts first (leading space)
    local param_opts = {}
    for _, lbl in ipairs (plist) do param_opts[lbl] = lbl end
    local keep_key = nil
    if existing then
      keep_key = "  (keep:  " .. existing.param .. ")"
      param_opts[keep_key] = "__keep__"
    end

    local title   = existing and ("Edit Mapping  [" .. rn .. "]")
                              or ("Add Mapping  [" .. rn .. "]")
    local def_cc  = existing and existing.cc  or 0
    local def_ch  = existing and existing.ch  or 0
    local def_min = existing and (existing.min or 0) or 0
    local def_max = existing and (existing.max or 0) or 0

    local rv = LuaDialog.Dialog (title, {
      { type = "label",   title = "Track / Bus:  " .. rn, align = "left" },
      { type = "number",  key = "cc",
        title = "CC Number  (0-127)",
        min = 0, max = 127, default = def_cc, step = 1, digits = 0 },
      { type = "number",  key = "ch",
        title = "MIDI Channel  (0 = any, 1-16 = specific)",
        min = 0, max = 16, default = def_ch, step = 1, digits = 0 },
      { type = "dropdown", key = "param",
        title = "Automation Parameter",
        values = param_opts },
      { type = "heading", title = "Scale override  (0 = natural range)",
        align = "left" },
      { type = "number",  key = "min",
        title = "Value at CC=0   (0 = use parameter minimum)",
        min = -1e9, max = 1e9, default = def_min, step = 0.001, digits = 6 },
      { type = "number",  key = "max",
        title = "Value at CC=127 (0 = use parameter maximum)",
        min = -1e9, max = 1e9, default = def_max, step = 0.001, digits = 6 },
    }):run ()
    if rv == nil then return nil end

    local pn = rv["param"]
    if pn == "__keep__" then pn = existing.param end

    return {
      ch    = math.floor (rv["ch"]),
      cc    = math.floor (rv["cc"]),
      route = rn,
      param = pn,
      min   = (rv["min"] ~= 0) and rv["min"] or nil,
      max   = (rv["max"] ~= 0) and rv["max"] or nil,
    }
  end

  -- ── main loop ─────────────────────────────────────────────────────────
  local mappings = load_cfg ()

  while true do
    local rv = LuaDialog.Dialog ("MIDI CC Map Editor", {
      { type = "label",    title = "File:  " .. cfg_path (),  align = "left" },
      { type = "dropdown", key = "sel",
        title = "Mapping",
        values = make_sel_opts (mappings) },
      { type = "dropdown", key = "action",
        title = "Action",
        default = "edit",
        values = {
          ["Edit / Add"]          = "edit",
          ["Delete"]              = "delete",
          ["Save"]                = "save",
          ["Exit without saving"] = "exit",
        }
      },
    }):run ()

    if rv == nil then break end

    local action = rv["action"]
    local idx    = rv["sel"]   -- 0 = new, ≥1 = existing index

    if action == "exit" then
      break

    elseif action == "save" then
      if save_cfg (mappings) then
        LuaDialog.Message ("MIDI CC Map Editor",
          string.format ("Saved %d mapping(s).\nDSP plugin reloads within 5 seconds.", #mappings),
          LuaDialog.MessageType.Info, LuaDialog.ButtonType.Close):run ()
      end
      break

    elseif action == "delete" then
      if idx == 0 then
        LuaDialog.Message ("MIDI CC Map Editor",
          "Select an existing mapping to delete.",
          LuaDialog.MessageType.Warning, LuaDialog.ButtonType.Close):run ()
      else
        table.remove (mappings, idx)
      end

    elseif action == "edit" then
      if idx == 0 then
        -- ── Add: read selected Ardour track ────────────────────────────
        local sel = Editor:get_selection ().tracks:routelist ()
        local r   = (not nilobj (sel)) and sel:front () or nil
        if nilobj (r) then
          LuaDialog.Message ("MIDI CC Map Editor",
            "Select a track or bus in Ardour first, then choose Edit / Add.",
            LuaDialog.MessageType.Warning, LuaDialog.ButtonType.Close):run ()
          goto continue
        end
        local rn  = r:name ()
        local new = open_form (rn, nil)
        if new == nil then goto continue end
        if dup_except (mappings, 0, new.ch, new.cc, new.route, new.param) then
          LuaDialog.Message ("MIDI CC Map Editor",
            string.format ("Mapping already exists:\n  CC%d ch:%s -> %s / %s",
              new.cc, (new.ch==0 and "any" or tostring(new.ch)), new.route, new.param),
            LuaDialog.MessageType.Warning, LuaDialog.ButtonType.Close):run ()
          goto continue
        end
        table.insert (mappings, new)

      else
        -- ── Edit: pre-fill form with existing values ────────────────────
        local existing = mappings[idx]
        local new = open_form (existing.route, existing)
        if new == nil then goto continue end
        if dup_except (mappings, idx, new.ch, new.cc, new.route, new.param) then
          LuaDialog.Message ("MIDI CC Map Editor",
            string.format ("Another mapping already uses:\n  CC%d ch:%s -> %s / %s",
              new.cc, (new.ch==0 and "any" or tostring(new.ch)), new.route, new.param),
            LuaDialog.MessageType.Warning, LuaDialog.ButtonType.Close):run ()
          goto continue
        end
        mappings[idx] = new
      end
    end

    ::continue::
  end   -- while

  end)  -- pcall
  if not ok then
    LuaDialog.Message ("MIDI CC Map Editor",
      "Error: " .. tostring (err),
      LuaDialog.MessageType.Error, LuaDialog.ButtonType.Close):run ()
  end
end end

