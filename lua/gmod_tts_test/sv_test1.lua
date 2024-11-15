

if not SERVER then
    print("Run this script on the server side")
    return
end


local test_base_url_cvar = CreateConVar("gmod_tts_test_base_url", "", FCVAR_PROTECTED, "base url of api client for test")
local test_secret_key_cvar = CreateConVar("gmod_tts_test_secret_key", "", FCVAR_PROTECTED, "secret key of api client for test")


util.AddNetworkString("gmod_tts_test1")

local ACTION_PLAY = 1
local ACTION_LOAD = 2
local ACTION_PAUSE = 3
local ACTION_UNPAUSE = 4
local ACTION_STOP = 5


local function send_to_clients(action, url, ply)
    net.Start("gmod_tts_test1")
        net.WriteUInt(action, 8)
        net.WriteString(url)
        if ply then
            net.WriteString(ply:SteamID())
        end
    net.Broadcast()
end


local test_sender = {}

function test_sender.send(chan, audio, paused)
    gmod_tts.debug(1, "sending url %s (paused: %s)", audio.play_url, paused)
    if not paused then
        send_to_clients(ACTION_PLAY, audio.play_url, chan.ply)
    else
        send_to_clients(ACTION_LOAD, audio.play_url, chan.ply)
    end
end

function test_sender.pause(chan, audio, paused)
    print(string.format("pausing url %s (paused: %s)", audio.play_url, paused))
    if paused then
        send_to_clients(ACTION_PAUSE, audio.play_url)
    else
        send_to_clients(ACTION_UNPAUSE, audio.play_url)
    end
end

function test_sender.stop(chan, audio)
    print(string.format("stop url %s", audio.play_url, paused))
    send_to_clients(ACTION_STOP, audio.play_url)
end


local test_api_client = nil

local function change_api_client()
    local base_url = test_base_url_cvar:GetString()
    local secret_key = test_secret_key_cvar:GetString()
    gmod_tts.debug(2, "make api client (base_url=%s, secret_key=\"****\")", gmod_tts.quote(base_url))
    test_api_client = gmod_tts.make_api_client(base_url, secret_key)
end

change_api_client()

local test_chan_params = {
    sender_latency = 125,
    debounce = 350
}

for i, ply in ipairs(player.GetAll()) do
    gmod_tts.debug(2, "create gmod-tts channel for player %s.", gmod_tts.quote(ply:Name()))
    ply.gmod_tts_test_chan = gmod_tts.make_channel("Test channel of " .. ply:SteamID(), test_api_client, test_sender, test_chan_params)
    ply.gmod_tts_test_chan.ply = ply
end


local tts_commands = {
    pause = function(ply)
        gmod_tts.debug(1, "%s pauses the speech.", gmod_tts.quote(ply:Name()))
        ply.gmod_tts_test_chan:pause()
    end,

    unpause = function(ply)
        gmod_tts.debug(1, "%s unpauses the speech.", gmod_tts.quote(ply:Name()))
        ply.gmod_tts_test_chan:unpause()
    end,

    stop = function(ply)
        gmod_tts.debug(1, "%s stops the speech.", gmod_tts.quote(ply:Name()))
        ply.gmod_tts_test_chan:stop()
    end,

    mute = function(ply)
        gmod_tts.debug(1, "%s mutes the channel.", gmod_tts.quote(ply:Name()))
        ply.gmod_tts_test_chan:mute()
    end,

    unmute = function(ply)
        gmod_tts.debug(1, "%s mutes the channel.", gmod_tts.quote(ply:Name()))
        ply.gmod_tts_test_chan:unmute()
    end,

    voice = function(ply, arg)
        gmod_tts.debug(1, "%s changes the voice on %s.", gmod_tts.quote(ply:Name()), gmod_tts.quote(arg))
        ply.gmod_tts_test_voice = arg
    end,

    lang = function(ply, arg)
        gmod_tts.debug(1, "%s changes the language on %s.", gmod_tts.quote(ply:Name()), gmod_tts.quote(arg))
        ply.gmod_tts_test_language = arg
    end,
}


hook.Add("PlayerSay", "gmod_tts_test1_player_say", function(ply, text)
    if not ply.gmod_tts_test_chan then
        gmod_tts.debug(2, "player %s doesn't have gmod-tts channel, create it.", gmod_tts.quote(ply:Name()))
        ply.gmod_tts_test_chan = gmod_tts.make_channel("Test channel of " .. ply:SteamID(), test_api_client, test_sender, test_chan_params)
        ply.gmod_tts_test_chan.ply = ply
    end
    local cmd, cmd_arg = string.match(text, "!(%w+)%s*(.*)")
    if cmd then
        cmd = string.lower(cmd)
        cmd_arg = string.Trim(cmd_arg)
        if tts_commands[cmd] then
            tts_commands[cmd](ply, cmd_arg)
            return
        end
    else
        ply.gmod_tts_test_chan:send(text, ply.gmod_tts_test_voice or "dmitry", ply.gmod_tts_test_language or "ru")
    end
end)