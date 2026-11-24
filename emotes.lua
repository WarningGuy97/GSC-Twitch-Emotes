-- GSCTwitchEmotes emote definitions.
--
-- Texture tag format: |Tpath:height:width|t
-- So "file.tga:28:28" is normal, "file.tga:28:56" is wide.
-- Names must be unique vs Giga and the base pack.

local base = "Interface\\AddOns\\GSCTwitchEmotes\\emotes\\"

GSCTwitchEmotes_emotes = {
    -- Static:
    -- ["gscHello"] = base .. "gscHello.tga:28:28",
    -- ["gscWide"]  = base .. "gscWide.tga:28:56",

    -- Animated: add a matching entry in animation.lua too.
    -- ["gscDance"] = base .. "gscDance.tga:28:28",
}

-- 150 temporary test emotes so /gsc can be checked before real emotes
-- are added. Remove this loop when replacing them with your own list.
for i = 1, 150 do
    local name = string.format("gscSample%03d", i)
    GSCTwitchEmotes_emotes[name] = base .. string.format("sample%03d.tga", i) .. ":28:28"
end
