

if not CLIENT then
    print("Run this script on the client side")
    return
end


local ACTION_PLAY = 1
local ACTION_LOAD = 2
local ACTION_PAUSE = 3
local ACTION_UNPAUSE = 4
local ACTION_STOP = 5


local audio_tab = {}


local function load_sound_url(url, paused, ply)
    sound.PlayURL(url, "3d mono noplay", function(audio_chan, error_id, error_msg)
        if not audio_chan then
            gmod_tts.debug(1, "error occured when loading sound URL %s (code=%s): %s.", url, error_id, error_msg)
            return
        end
        if not audio_chan:IsValid() then
            gmod_tts.debug(1, "sound of URL %s is invalid.", url)
            return
        end
        local time = SysTime()
        local duration = audio_chan:GetLength()
        local info = {}
        info.starts_at = time
        info.ends_at = time + duration
        info.duration = duration
        info.paused = paused
        info.ply = ply
        info.audio_chan = audio_chan
        audio_tab[url] = info
        gmod_tts.debug(1, "audio of URL %s is loaded (sample_rate=%s, bitrate=%d kbps, mono).", url, audio_chan:GetSamplingRate(), audio_chan:GetAverageBitRate())
        if not paused then
            audio_chan:Play()
        end
    end)

end


net.Receive("gmod_tts_test1", function()
    local action = net.ReadUInt(8)
    local play_url = net.ReadString()

    if action == ACTION_PLAY or action == ACTION_LOAD then
        local steam_id = net.ReadString()
        local ply = player.GetBySteamID(steam_id)
        load_sound_url(play_url, action == ACTION_LOAD, ply)
    elseif audio_tab[play_url] then
        local info = audio_tab[play_url]
        local audio_chan = info.audio_chan
        local time = SysTime()
        if action == ACTION_PAUSE then
            if not info.paused then
                info.duration = info.duration - (time - info.starts_at)
                info.paused = true
                audio_chan:Pause()
                gmod_tts.debug(1, "audio of url %s is paused.", play_url)
            end
        elseif action == ACTION_UNPAUSE then
            if info.paused then
                info.starts_at = time
                info.ends_at = time + info.duration
                info.paused = false
                audio_chan:Play()
                gmod_tts.debug(1, "audio of url %s is unpaused.", play_url)
            end
        elseif action == ACTION_STOP then
            audio_chan:Stop()
            audio_tab[play_url] = nil
            gmod_tts.debug(1, "audio of url %s is stopped.", play_url)
        end
    end
end)


hook.Add("Think", "gmod_tts_test1", function()
    local completed_audio = {}
    local time = SysTime()
    for url, info in pairs(audio_tab) do
        if not info.paused then
            if time < info.ends_at then
                local ply = info.ply
                info.audio_chan:SetPos(ply:GetShootPos() + ply:GetAimVector() * 5, ply:GetAimVector())
            else
                completed_audio[url] = true
            end
        end
    end
    for url, b in pairs(completed_audio) do
        if b then
            audio_tab[url] = nil
            gmod_tts.debug(1, "audio of url %s is ended.", url)
        end
    end
end)