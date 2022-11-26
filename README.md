# ardour_midi_utils
Various scripts to further assist with MIDI controllers in Ardour.

# MPK2 Auto Feedback Usage
Add both the mpk2_config.lua and mpk2_autofdbk.lua scripts to your session. Run the MPK2 Config action script to set your device and feedback track settings. 
The mpk2_autofdbk hook script will check for selected MIDI tracks tagged with a bank letter (ie..[BANK A] or [BankB]) and switch the MPK2's bank, along with providing visual feedback to the pads. Multiple selections are allowed for tracks 
with the same bank. Feedback is set if main feedback track is tagged with [PLAY].
