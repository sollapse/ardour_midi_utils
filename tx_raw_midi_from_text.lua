ardour {
	["type"]    = "EditorAction",
	name        = "Send Raw MIDI from Text Field",
	license     = "MIT",
	author      = "Ardour Team",
	description = [[Read raw SysEx MIDI message from a text field and send it to a MIDI port]]
}

function factory () return function ()

	function portlist ()
		local rv = {}
		local a = Session:engine()
		local _, t = a:get_ports (ARDOUR.DataType("midi"), ARDOUR.PortList())
		for p in t[2]:iter() do
			local amp = p:to_asyncmidiport ()
			if amp:isnil() or not amp:sends_output() then goto continue end
			rv[amp:name()] = amp
			print (amp:name(), amp:sends_output())
			::continue::
		end
		return rv
	end

	local dialog_options = {
		{ type = "checkbox", key = "autoinc", default = false, title = "Add F0 and F7 bytes?" },
		{ type = "entry", key = "syxstring", title = "Enter SysEx bytes" },
		{ type = "dropdown", key = "port", title = "Target Port", values = portlist () }
	}

	local rv = LuaDialog.Dialog ("Select Target", dialog_options):run ()
	dialog_options = nil -- drop references (ports, shared ptr)
	collectgarbage () -- and release the references immediately

	if not rv then return end -- user cancelled

    --convert string to byte array	
	pbuf = "" 
	i = 0
	for s in string.gmatch(rv["syxstring"],"%S+") do
    	pbuf = pbuf .. string.char(tonumber(s, 16))
	end
    
	if rv["autoinc"] then
		--test first and last bytes for 0xF0 and 0xF7	
        if ((string.byte(pbuf,1)) ~= 0xF0) and (string.byte(pbuf, #pbuf) ~= 0xF7) then
			pbuf =  string.char(0xf0) .. pbuf .. string.char(0xf7)
		end
	
	end

	
	do -- scope for 'local'
		local async_midi_port = rv["port"] -- reference to port
		local parser = ARDOUR.RawMidiParser () -- construct a MIDI parser
			
		-- parse MIDI data byte-by-byte
		for i = 1, #pbuf do
				if parser:process_byte (string.byte(pbuf,i)) then
					
					-- parsed complete normalized MIDI message, send it
					async_midi_port:write (parser:midi_buffer (), parser:buffer_size (), 0)

					-- Physical MIDI is sent at 31.25kBaud.
					-- Every message is sent as 10bit message on the wire,
					-- so every MIDI byte needs 320usec.
					ARDOUR.LuaAPI.usleep (400 * parser:buffer_size ())
	
				end
	    end

	end
	::out::
end end

function icon (params) return function (ctx, width, height, fg)
	ctx:set_source_rgba (ARDOUR.LuaAPI.color_to_rgba (fg))
	local txt = Cairo.PangoLayout (ctx, "ArdourMono ".. math.ceil(math.min (width, height) * .45) .. "px")
	txt:set_text ("S")
	ctx:move_to (1, 1)
	txt:show_in_cairo_context (ctx)

	txt:set_text ("Y")
	local tw, th = txt:get_pixel_size ()
	ctx:move_to (.5 * (width - tw), .5 * (height - th))
	txt:show_in_cairo_context (ctx)

	txt:set_text ("X")
	tw, th = txt:get_pixel_size ()
	ctx:move_to ((width - tw - 1), (height - th -1))
	txt:show_in_cairo_context (ctx)
end end
