# ardour_midi_utils
Various scripts to further assist with MIDI controllers in Ardour.

### MPK2 Auto Feedback Usage
Add both the mpk2_config.lua and mpk2_autofdbk.lua scripts to your session. 

Run the MPK2 Config action script to set your device and feedback track settings. 

The mpk2_autofdbk hook script will check for selected MIDI tracks tagged with a bank letter 
enclosed in square brackets (ex: [BANK A], [BANK_B] or [BankC]). This will switch the MPK2's bank, along 
with providing visual feedback to the pads. 

Multiple selections are allowed for tracks with the same bank. 

Feedback is set if main feedback track is tagged with [PLAY].

MPK2 SysEx information obtained from [Nick Smith](https://github.com/nsmith-/mpk2/)

### Send SysEx from Text Field
Utility script to send short SysEx messages up to 256 bytes from a text field. Device must be connected to one of Ardour's async MIDI ports (ex: MIDI Control Out).
