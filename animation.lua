-- Animated emote metadata for GSCTwitchEmotes.
--
-- Animated emotes are vertical sprite sheets. Each frame is stacked top to bottom.
-- imageHeight should be frameHeight * nFrames.
-- Keep imageHeight <= 8192.
--
-- Add one AddAnimated(...) line per animated .tga, then add the emote to emotes.lua.

local base = "Interface\\AddOns\\GSCTwitchEmotes\\emotes\\"

GSCTwitchEmotes_animation_metadata = GSCTwitchEmotes_animation_metadata or {}

local function AddAnimated(fileName, nFrames, frameWidth, frameHeight, framerate)
    local path = base .. fileName
    local meta = {
        nFrames = nFrames,
        frameWidth = frameWidth,
        frameHeight = frameHeight,
        imageWidth = frameWidth,
        imageHeight = frameHeight * nFrames,
        framerate = framerate or 18,
    }

    GSCTwitchEmotes_animation_metadata[path] = meta

    -- Also publish into the base addon's shared metadata table.
    if type(TwitchEmotes_animation_metadata) == "table" then
        TwitchEmotes_animation_metadata[path] = meta
    end
end

-- Examples:
-- AddAnimated("gscDance.tga", 8, 32, 32, 18)
-- AddAnimated("gscWideDance.tga", 10, 64, 32, 18)
