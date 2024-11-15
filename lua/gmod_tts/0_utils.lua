

local debug_level_cvar = CreateConVar("gmod_tts_debug", "0", FCVAR_ARCHIVE, "Shown debug information level of gmod-tts.", 0, 3)
gmod_tts.debug_level_cvar = debug_level_cvar


function gmod_tts.concat_url_components(url1, url2)
    url1 = string.Trim(url1)
    url2 = string.Trim(url2)
    url1 = string.TrimRight(url1, "/")
    url2 = string.TrimLeft(url2, "/")
    return url1 .. "/" .. url2
end


function gmod_tts.debug(level, format, ...)
    level = math.Clamp(level, debug_level_cvar:GetMin(), debug_level_cvar:GetMax())
    if debug_level_cvar:GetInt() < level then
        return
    end
    local level_str = "DEBUG " .. level
    if level == 0 then
        level_str = "INFO"
    end
    local message = string.format(format, ...)
    print(string.format("GMOD-TTS %s [%s]: %s", util.DateStamp(), level_str, message))
end


function gmod_tts.debug_level(level)
    level = math.Clamp(level, debug_level_cvar:GetMin(), debug_level_cvar:GetMax())
    return debug_level_cvar:GetInt() >= level
end


local escape_chars = {
    ["\\"] = "\\",
    ["\""] = "\"",
    ["\n"] = "n",
    ["\t"] = "t",
    ["\v"] = "v"
}

local function quote_string(str)
    result = ""
    pos = 1
    while true do
        new_pos = string.find(str, "[\"\\\n\t\v]", pos, false)
        if not new_pos then
            result = result .. string.sub(str, pos)
            break
        else
            result = result .. string.sub(str, pos, new_pos - 1) .. "\\" .. escape_chars[string.sub(str, new_pos, new_pos)]
        end
        pos = new_pos + 1
    end
    return "\"" .. result .. "\""
end

function gmod_tts.quote(val)
    if type(val) == "string" then
        return quote_string(val)
    end
    return tostring(val)
end