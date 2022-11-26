ardour {
	["type"]    = "EditorHook",
	name        = "MPK2 Auto Feedback",
	author      = "sollapse",
	license     = "MIT",
	description = "Automatically provide pad feedback and bank switching on MPK2 series controllers from tagged MIDI track selected. \n\nMPK2 series SysEx information provided by Nick Smith @ https://github.com/nsmith-/mpk2",
}

function signals ()
	s = LuaSignal.Set()
	s:add (
		{
			[LuaSignal.Change] = true,
		}
	)
	return s
end

function factory (params)
	--globals
	padfdbk = nil --Pad feedback MIDI track
	parser = nil --Raw MIDI parser for SysEx
	sel = nil --editor selection object
	padfdbk_name = "" --Pad feedback MIDI track name
	mpk2_out = "" --MPK2 hardware out port name
	mpk2_padchn = 0 --MPK2 pads channel
	mpk2_model = 0 --SysEx identifier for controller model (MPK225 = 0x23, MPK249 = 0x24, MPK261 = 0x25)
	noteoff_buf = "" --buffer for all note off messages 
	multi_sel = false
	configured = false
	debug = true --print debug messages
	
	function parseComments(str)
		--check for brackets
		b,e = string.find(str, "%b[]") 
			if b > 0 and e > 0 then
				   local s = string.sub(str,b+1,e-1)	
				return s:upper()
			else
				return ""
			end
	end

	--helper function to send MIDI
	function tx_midi (syx, len, safesend)
		for b = 1, len do
			-- parse message to C/C++ uint8_t* array (Validate message correctness. This
			-- also returns C/C++ uint8_t* array for direct use with write_immediate_event.)
			if parser:process_byte (syx:byte(b)) then
				padfdbk:write_immediate_event (Evoral.EventType.MIDI_EVENT, parser:buffer_size (), parser:midi_buffer ())
				if safesend then
					-- Slow things down a bit to ensure that no messages as lost.
					-- Physical MIDI is sent at 31.25kBaud.
					-- Every message is sent as 10bit message on the wire,
					-- so every MIDI byte needs 320usec.
					ARDOUR.LuaAPI.usleep (400 * parser:buffer_size ())
				end
			end
		end
	end

	return function (signal, ref, ...)
		--build config filename
		cfgname = ARDOUR.LuaAPI.build_filename(Session:path(), "mpk2.cfg")

		function chkConfig()
			--attempt to read config file and load variables
			if ARDOUR.LuaAPI.file_test(cfgname, ARDOUR.LuaAPI.FileTest.Exists) then
				cfgfile = io.open(cfgname, "r+")
				io.input(cfgfile)

				--load variables
				local r = io.read()
				
				local vars = {}
				for v in r:gmatch("([^,]+)") do
					table.insert(vars, v)
				end

				if #vars == 4 then 
					mpk2_out = vars[1]
					mpk2_model = tonumber(vars[2], 16)
					mpk2_padchn = tonumber(vars[3])
					padfdbk_name = vars[4]
						
					--get feedback track object
					local r = Session:route_by_name(padfdbk_name)

					if not r:to_track():to_midi_track():isnil() then
						padfdbk = r:to_track():to_midi_track()
						configured = true
						io.close(cfgfile)
					end 
				else
					io.close(cfgfile)
				end
	
				if configured then
					--Set raw midi parser
					parser = ARDOUR.RawMidiParser()

					--fill all notes off buffer
					for i = 0, 127 do
						noteoff_buf = noteoff_buf .. string.char((0x80 & 0xF0) + tonumber(string.format("%x", mpk2_padchn - 1), 16), tonumber(string.format("%x", i), 16), 0x00)
					end
				else
					if debug then print("MPK2 Auto Feedback not configured.") end
					return
				end
			end
		end
       
		function configFeedback()	
			if debug then print("Multiple selections: " .. tostring(multi_sel) .. " Size: " .. tostring(sel.tracks:routelist():size())) end
		   	--disconnect here for multiple MIDI selections
			if multi_sel then
				--disconnect old
				padfdbk:input():midi(0):disconnect_all()
			end

			if #padfdbk:comment() > 0 then
				playfdbk = parseComments(padfdbk:comment())
				if playfdbk == "PLAY" then 
					goto process 
				else
					goto skip
				end
			else
				playfdbk = ""
				goto skip
			end

			::process::
			--send all notes off
			tx_midi(noteoff_buf, #noteoff_buf, false)

			--check for valid MIDI track(s)
			for t in Session:get_tracks():iter() do 
				local miditrk = t:to_track():to_midi_track()

				if not miditrk:isnil() and not padfdbk:isnil() and miditrk:is_selected() and #miditrk:comment() > 0 then
						--don't make change on feedback track
						if not miditrk:name():find(padfdbk_name) then
							--parse comments for bank
							b = parseComments(miditrk:comment())
							--make bank change on tagged tracks
							if b:find("BANK") then 
								if debug then print("Selected MIDI Track: " .. miditrk:name() .. " Bank tag: " .. b) end
								--if debug then print("Selected MIDI Track output port: " .. miditrk:output():midi(0):name()) end

								--get SysEx code for bank change
								if b == "BANK_A" or b == "BANKA" or b == "BANK A" then
									mpk2_bank = 0x00
								elseif b == "BANK_B" or b == "BANKB" or b == "BANK B" then
									mpk2_bank = 0x01
								elseif b == "BANK_C" or b == "BANKC" or b == "BANK C" then
									mpk2_bank = 0x02
								elseif b == "BANK_D" or b == "BANKD" or b == "BANK D" then
									mpk2_bank = 0x03
								else  --default to Bank A
									mpk2_bank = 0x00
								end
									
								--create SysEx message for bank change
								local syx = string.char (0xf0, 0x47,0x00,      
														mpk2_model, 0x30,
														0x00, 0x04, 0x01, 
														0x00, 0x18, mpk2_bank, 0xf7)
								--transmit message
								tx_midi(syx, #syx, false)
								
								--disconnect here for single selection
								if not multi_sel then
									--disconnect old
									padfdbk:input():midi(0):disconnect_all()
								end
								--connect output port for feedback
								padfdbk:input():midi(0):connect(miditrk:output():midi(0):name())
							else
								padfdbk:input():midi(0):disconnect_all()
							end
						end
				end 
			end
			::skip::
		end

		function selectTrack()
			    --get current selection in editor
				 sel = Editor:get_selection()
			    
				--check for track(s) selected
				if sel.tracks:routelist():size() == 1 then
					multi_sel = false
					configFeedback()
				elseif sel.tracks:routelist():size() > 1 then
					--get selected tracks
					local t_tbl = {}

					for t in Session:get_tracks():iter() do
						local trk = t:to_track():to_midi_track()
						if not trk:isnil() and trk:is_selected() and not trk:name():find(padfdbk_name) then
							table.insert(t_tbl, trk)
						end
					end

					--parse comments to see if selections belong to the same bank
					local falsecnt = 0
					for i = 1, #t_tbl do
						if i > 1 then
							if #t_tbl[i - 1]:comment() > 0 and #t_tbl[i]:comment() > 0 then
								local s1 = parseComments(t_tbl[i - 1]:comment())
								local s2 = parseComments(t_tbl[i]:comment())
								if s2:find("BANK") and s1:find("BANK") then 
									local b = (s2 == s1)
									if not b then
										falsecnt = falsecnt + 1
									end
								end
							end
						end
					end

					--clear track table
					for i = 1, #t_tbl do
						t_tbl[i] = nil
					end
					t_tbl = nil
					
					--config for multi tracks of same bank
					if falsecnt == 0 then
						multi_sel = true
						configFeedback()
					else
						if debug then print("Multiple selections do not share the same bank. Last track selected in use.") end
						multi_sel = false
						configFeedback()
					end
				end
		end

		--wait for editor change signal (selections)
		if (signal == LuaSignal.Change) then
			if configured then
				selectTrack()
			else
				chkConfig()
			end
		end
	end
end