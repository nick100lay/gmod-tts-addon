

AddCSLuaFile()

gmod_tts = {}


local function get_module_realm(name)
    if string.find(name, "^%d*_?sv_") then
        return "sv"
    elseif string.find(name, "^%d*_?cl_") then
        return "cl"
    end
    return "sh"
end

local function get_order(name)
    local num = string.match(name, "^(%d+)")
    return num and tonumber(num) or 0
end


local function show_debug(level, format, ...)
    if gmod_tts.debug then
        gmod_tts.debug(level, format, ...)
    end
end

local function load_module_dir(dir_path, can_be_server, can_be_client)
    local files, dirs = file.Find(dir_path .. "/*", "LUA")
    local mods = {}
    for i, file_name in ipairs(files) do
        if string.GetExtensionFromFilename(file_name) != "lua" then
            continue
        end
        mods[#mods + 1] = { name = file_name, path = dir_path .. "/" .. file_name, is_dir = false }
    end
    for i, dir_name in ipairs(dirs) do
        mods[#mods + 1] = { name = dir_name, path = dir_path .. "/" .. dir_name, is_dir = true }
    end
    table.sort(mods, function(a, b) 
        return get_order(a.name) < get_order(b.name)
    end)

    for i, mod in ipairs(mods) do
        local realm = get_module_realm(mod.name)
        if realm == "sv" and not can_be_server then
            error(string.format("module %s can't be on serverside.", mod.path))
        elseif realm == "cl" and not can_be_client then
            error(string.format("module %s can't be on clientside.", mod.path))
        end
        if realm == "sh" then
            if can_be_server and not can_be_client then
                realm = "sv"
            elseif can_be_client and not can_be_server then
                realm = "cl"
            end
        end
        if not mod.is_dir then
            if SERVER and (realm == "cl" or realm == "sh") then
                show_debug(1, "adding client side lua file %s", mod.path)
                AddCSLuaFile(mod.path)
            end
            if realm == "sh" or realm == "sv" and SERVER or realm == "cl" and CLIENT then
                show_debug(1, "including lua file %s", mod.path)
                include(mod.path)
            end
        else
            show_debug(1, "loading directory of modules %s", mod.path)
            if realm == "sh" then
                load_module_dir(mod.path, true, true)
            elseif realm == "sv" then
                load_module_dir(mod.path, true, false)
            else
                load_module_dir(mod.path, false, true)
            end
        end
    end
end


load_module_dir("gmod_tts", true, true)

hook.Run("gmod_tts_init")