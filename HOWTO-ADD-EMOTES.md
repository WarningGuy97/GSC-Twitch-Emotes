# Adding Emotes to GSC Twitch Emotes

## 1. Add the image

Put your `.tga` file here:

```text
GSCTwitchEmotes\emotes\
```

Example: `myEmote.tga`

Keep filenames simple. Match capitalization exactly in the code.

## 2. Remove the test emotes

Open `emotes.lua`. Delete this loop when ready:

```lua
for i = 1, 150 do
    local name = string.format("gscSample%03d", i)
    GSCTwitchEmotes_emotes[name] = base .. string.format("sample%03d.tga", i) .. ":28:28"
end
```

You may also delete the `sample001.tga`–`sample150.tga` files.

## 3. Add a static emote

In `emotes.lua`, add inside the table:

```lua
["myEmote"] = base .. "myEmote.tga:28:28",
```

Format is `filename.tga:height:width`.

Wide example:

```lua
["myWideEmote"] = base .. "myWideEmote.tga:28:56",
```

## 4. Add an animated emote

Animated emotes use a vertical sprite sheet. Frames stack top to bottom.

In `emotes.lua`:

```lua
["myDance"] = base .. "myDance.tga:28:28",
```

In `animation.lua`:

```lua
AddAnimated("myDance.tga", 8, 32, 32, 18)
```

That means:

- 8 frames
- each frame 32x32
- 18 frames per second
- image height becomes `32 * 8 = 256`

Keep image height at 8192 or below.

## 5. Reload and test

In game:

```text
/reload
/gsc
```

Check the browser shows your emote.

Autocomplete should also work:

```text
:myEmote
```

TAB cycles suggestions. ENTER selects and sends.

## Rules

- Use unique emote names. Do not reuse Giga or base-pack names.
- `.tga` is recommended.
- Names must match exactly between table key, filename, and metadata.
- After editing Lua files, use `/reload`.
