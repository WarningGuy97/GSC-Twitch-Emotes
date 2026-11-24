GSC Twitch Emotes

Runs alongside Giga Twitch Emotes. Uses the base addon TwitchEmotes.

FILES
- emotes.lua      : emote name -> texture path
- animation.lua   : animated sprite-sheet metadata
- main.lua        : registration, autocomplete, animation wrapper, /gsc command
- emotes\         : put .tga files here

ADD STATIC EMOTE
1. Put Name.tga in the emotes folder.
2. In emotes.lua, add inside GSCTwitchEmotes_emotes:
   ["Name"] = base .. "Name.tga:28:28",
   Wide example: "Name.tga:28:56".

ADD ANIMATED EMOTE
1. Put Name.tga in emotes folder. Must be a vertical sprite sheet.
2. In emotes.lua, add:
   ["Name"] = base .. "Name.tga:28:28",
3. In animation.lua, add:
   AddAnimated("Name.tga", nFrames, frameWidth, frameHeight, framerate)
   imageHeight is calculated as frameHeight * nFrames. Keep <= 8192.

MINIMAP BUTTON
- Registered as LibDBIcon "GSCTwitchEmotes".
- SexyMap picks it up automatically: shape conformity, dragging, and its
  Always / Never / On Hover button visibility all work.
- Left-click button: open the emote browser.
- Right-click button: open GSC Twitch Emotes in the AddOns settings panel.
- Shift+Right-click button: hide the minimap button.
- Mode is mirrored into SexyMap's per-button setting when SexyMap is enabled.
- If the button does not update immediately, /reload once; saved mode persists.

COMMANDS
- /gsc                   : open the emote browser
                           Mouse wheel over browser also changes pages.

SETTINGS PANEL
- Options > AddOns > GSC Twitch Emotes.
- Radio buttons: Always show / Show only on hover / Hide button.
- Also has an "Open Emote Browser" button.

AUTOCOMPLETE
- Uses Twitch Emotes v2 autocomplete.
- Type ":" to open the emote list, keep typing to filter.
- TAB cycles suggestions, ENTER selects and sends.
- Requires "Enable Autocomplete" in Twitch Emotes v2 settings.
- GSC Twitch Emotes names are merged into the list even when Giga is enabled.

TEST EMOTES
- emotes.lua currently generates 150 sample emotes: gscSample001..gscSample150.
- Matching placeholder .tga files are in emotes\.
- Remove the generation loop when adding your real emotes.

NOTES
- Use emote names not already used by Giga or the base pack. Duplicate names: last addon loaded wins.
- Keep folder name GSCTwitchEmotes. Texture paths are hard-coded to it.
- /reload after editing Lua files.
