ardour {
    ["type"] = "EditorAction",
    name = "MPK2 Auto Feedback Config",
    license = "MIT",
    author = "sollapse",
    description = "Configure MPK2 Auto Feedback. \n\nMPK2 series SysEx information provided by Nick Smith @ https://github.com/nsmith-/mpk2"
}

function factory()
    padfdbk_name = ""
    mpk2_out = ""
    mpk2_model = ""
    mpk2_padchn = ""

    return function()

        -- find all MIDI hardware that accepts input	
        function deviceList()
            _, v = Session:engine():get_backend_ports("", ARDOUR.DataType("midi"),
                ARDOUR.PortFlags.IsInput | ARDOUR.PortFlags.IsPhysical, C.StringVector())
            p = {}
            d = "MIDI Hardware Devices For Output"
            print(d)
            print(string.rep("-", #d + 16))
            for n in v[4]:iter() do
                p[Session:engine():get_pretty_name_by_name(n)] = n
                print(n)
            end
            return p
        end

        function getModel()
            if mpk2_out:find("225") then
                mpk2_model = "23"
            elseif mpk2_out:find("249") then
                mpk2_model = "24"
            elseif mpk2_out:find("261") then
                mpk2_model = "25"
            end
        end

        -- open or create config file in session directory
        -- CSV format
        -- line 1: "MPK2 device port","MPK2 device code","pad channel","feedback track name" 
        cfgname = ARDOUR.LuaAPI.build_filename(Session:path(), "mpk2.cfg")

        if ARDOUR.LuaAPI.file_test(cfgname, ARDOUR.LuaAPI.FileTest.Exists) then
            cfgfile = io.open(cfgname, "r+")
            io.input(cfgfile)

            -- load variables
            local r = io.read()

            local vars = {}
            for v in r:gmatch("([^,]+)") do
                table.insert(vars, v)
                print(v)
            end

            if #vars == 4 then
                mpk2_out = vars[1]
                mpk2_model = vars[2]
                mpk2_padchn = vars[3]
                padfdbk_name = vars[4]
                allvars = true
            else
                allvars = false
            end

        else
            -- create file
            cfgfile = io.open(cfgname, "w+")
            allvars = false
        end

        -- create correct dialog
        if allvars then
            dialog_options = {{
                type = "entry",
                key = "fdbktrack",
                default = padfdbk_name,
                title = "Pad Feedback Track Name"
            }, {
                type = "checkbox",
                key = "hidetrack",
                default = false,
                title = "Hide Feedback Track?"
            }, {
                type = "dropdown",
                key = "port",
                default = Session:engine():get_pretty_name_by_name(mpk2_out),
                title = "Select MPK2 Device",
                values = deviceList()
            }, {
                type = "entry",
                key = "padchn",
                default = mpk2_padchn,
                title = "Pad Channel"
            }}
        else
            -- use default values
            dialog_options = {{
                type = "entry",
                key = "fdbktrack",
                default = "MPK2 Pad Fdbk",
                title = "Pad Feedback Track Name"
            }, {
                type = "checkbox",
                key = "hidetrack",
                default = false,
                title = "Hide Feedback Track?"
            }, {
                type = "dropdown",
                key = "port",
                title = "Select MPK2 Device",
                values = deviceList()
            }, {
                type = "entry",
                key = "padchn",
                default = "10",
                title = "Pad Channel"
            }}
        end

        -- run main dialog
        local rv = LuaDialog.Dialog("MPK2 Auto Feedback Config", dialog_options):run()
        dialog_options = nil -- drop references 
        collectgarbage() -- release the references immediately

        -- dialog cancelled
        if not rv then
            io.close(cfgfile)
            return
        end

        -- populate vars
        mpk2_out = rv["port"]
        mpk2_padchn = rv["padchn"]
        padfdbk_name = rv["fdbktrack"]

        -- find MPK2 model code from device name
        getModel()

        -- write values to cfg file
        io.output(cfgfile)
        cfgvars = mpk2_out .. "," .. mpk2_model .. "," .. mpk2_padchn .. "," .. padfdbk_name
        cfgfile:seek("set", 0)
        io.write(cfgvars .. "\n")
        io.close(cfgfile)

        -- test for feedback track
        t = Session:route_by_name(padfdbk_name)
        if t:isnil() then
            -- create new feedback track
            mt = Session:new_midi_track(ARDOUR.ChanCount(ARDOUR.DataType("midi"), 1),
                ARDOUR.ChanCount(ARDOUR.DataType("midi"), 1), true, ARDOUR.PluginInfo(), nil, nil, 1, padfdbk_name,
                ARDOUR.PresentationInfo.max_order, ARDOUR.TrackMode.Normal, false)
			padfdbk = mt:front()
		else 
			padfdbk = t:to_track():to_midi_track()
        end

        -- configure feedback track
        if not padfdbk:isnil() then
            padfdbk:set_comment("[PLAY]", nil)
            padfdbk:set_capture_channel_mode(ARDOUR.ChannelMode.ForceChannel,
                1 << tonumber(string.format("%x", tonumber(mpk2_padchn) - 1), 16))
            padfdbk:output():midi(0):connect(mpk2_out)
        end
        
        --set feedback track visibility
        tv = Editor:rtav_from_route(Session:route_by_name(padfdbk_name)):to_timeaxisview()
        if rv["hidetrack"] then
            Editor:hide_track_in_display(tv, true)
        else
            Editor:show_track_in_display(tv, true)
        end
    end
end

function icon(params)
    return function(ctx, width, height, fg)
        local txt = Cairo.PangoLayout(ctx, "ArdourMono " .. math.ceil(height / 3) .. "px")
        ctx:set_source_rgba(1, 1, 1, 1)
        txt:set_text("MPK")
        local tw, th = txt:get_pixel_size()
        ctx:move_to(.3 * (width - tw), .5 * (height - th))
        txt:show_in_cairo_context(ctx)
        ctx:set_source_rgba(1, 0, 0, 1)
        txt:set_text("2")
        local tw, th = txt:get_pixel_size()
        ctx:move_to(.9 * (width - tw), .5 * (height - th))
        txt:show_in_cairo_context(ctx)
    end
end
