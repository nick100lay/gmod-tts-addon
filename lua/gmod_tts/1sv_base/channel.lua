

local channel_mt = {}
channel_mt.__index = channel_mt
gmod_tts.channel_mt = channel_mt

function gmod_tts.make_channel(name, api_client, sender, params)
    local chan = setmetatable({}, channel_mt)
    chan.name = name
    chan.api_client = api_client
    chan.sender = sender
    chan.queue = gmod_tts.make_queue()
    chan.params = params or {}
    chan.paused = false
    chan.muted = false
    return chan
end

function channel_mt:send(text, voice, language, options)
    local debounce_ms = self.params.debounce or 0
    if debounce_ms <= 0 then
        self:_send(text, voice, language, options)
        return
    end
    if self.debounce_timer then
        gmod_tts.debug(2, "channel(name=%s):send: restart current debounce.", self.name)
        timer.Stop(self.debounce_timer)
        timer.Start(self.debounce_timer)
        local args = self.debounce_args
        self.debounce_args = {
            text = args.text .. " " .. text,
            voice = voice,
            language = language,
            options = options
        }
    else
        gmod_tts.debug(2, "channel(name=%s):send: start debounce timer for %.0f ms.", self.name, debounce_ms)
        local debounce_timer_id = "gmod_tts_channel_debounce_timer;".. self.name .. ";" .. SysTime()
        timer.Create(debounce_timer_id, debounce_ms / 1000, 1, function()  
            local args = self.debounce_args
            self.debounce_timer = nil
            self.debounce_args = nil
            self:_send(args.text, args.voice, args.language, args.options) 
        end)
        self.debounce_args = { text = text, voice = voice, language = language, options = options }
        self.debounce_timer = debounce_timer_id
    end
end

function channel_mt:_send(text, voice, language, options)
    gmod_tts.debug(1, "channel(name=%s):_send(text=%s, voice=%s, language=%s, options={...})", gmod_tts.quote(self.name), gmod_tts.quote(text), gmod_tts.quote(voice), gmod_tts.quote(language))
    if self.muted then
        gmod_tts.debug(2, "channel(name=%s):_send: channel is muted, exit.", gmod_tts.quote(self.name))
        return false
    end
    local max_queue_size = self.params.max_queue_size or 0
    if max_queue_size >= 1 and self.queue.size >= max_queue_size then
        gmod_tts.debug(2, "channel(name=%s):_send: queue is full (max_queue_size=%d), exit.", gmod_tts.quote(self.name), max_queue_size)
        return false
    end
    local max_text_len = self.params.max_text_len or 0
    if max_text_len >= 1 then
        local action_on_text_len_exceed = string.Trim(string.lower(self.params.action_on_text_len_exceed or "truncate"))
        local text_len = utf8.len(text)
        if text_len >= max_text_len then
            if action_on_text_len_exceed == "skip" then
                gmod_tts.debug(2, "channel(name=%s):_send: the text_len=%d exceeds max_text_len=%d, skip from sending.", gmod_tts.quote(self.name), text_len, max_text_len)
                return false
            else
                gmod_tts.debug(2, "channel(name=%s):_send: the text_len=%d exceeds max_text_len=%d, truncate the text.", gmod_tts.quote(self.name), text_len, max_text_len)
            end
            text = string.sub(text, 1, utf8.offset(text, max_text_len))
        end
    end
    self.queue:enqueue(text, voice, language, options)
    self:handle_queue()
    return true
end

function channel_mt:handle_queue()
    if self.muted then
        gmod_tts.debug(2, "channel(name=%s):handle_queue: channel is muted, exit.", gmod_tts.quote(self.name))
        return
    end
    if self.paused then
        gmod_tts.debug(2, "channel(name=%s):handle_queue: channel is paused, exit.", gmod_tts.quote(self.name))
        return
    end
    if self.tts_request or self.speech_timer then
        gmod_tts.debug(2, "channel(name=%s):handle_queue: queue is already been handling, exit.", gmod_tts.quote(self.name))
        return
    end

    gmod_tts.debug(1, "channel(name=%s):handle_queue()", gmod_tts.quote(self.name))

    local text, voice, language, options
    while true do
        if self.queue.size <= 0 then
            gmod_tts.debug(2, "channel(name=%s):handle_queue(): queue is empty, exit.", gmod_tts.quote(self.name))
            return
        end
        text, voice, language, options = self.queue:dequeue()
        if self.sender.should_send and not self.sender.should_send(self, text, voice) then
            gmod_tts.debug(2, "channel(name=%s):handle_queue: sender refused to send text=%s with voice=%s, handle next.", gmod_tts.quote(text), gmod_tts.quote(voice))
        else
            break
        end
    end

    local function on_success(request_info, audio_info)
        self.tts_request = nil
        self.cur_audio_info = audio_info
        gmod_tts.debug(2, "channel(name=%s):handle_queue on_success: sending audio...", gmod_tts.quote(self.name))
        local ok, sender_status = pcall(self.sender.send, self, audio_info, self.paused)
        if not ok then
            gmod_tts.debug(2, "channel(name=%s):handle_queue on_success: sender throws error: %s, handle next.", gmod_tts.quote(self.name), sender_status)
            self:handle_queue()
            return
        end
        if sender_status == false then
            gmod_tts.debug(2, "channel(name=%s):handle_queue on_success: sender refused to send this audio, handle next.", gmod_tts.quote(self.name))
            self:handle_queue()
            return
        end

        local wait_dur = audio_info.duration + (self.params.sender_latency or 0) / 1000
        local timer_id = "gmod_tts_channel_speech_timer;" .. self.name .. ";" .. SysTime()
        gmod_tts.debug(2, "channel(name=%s):handle_queue on_success: waiting for %.3fs...", gmod_tts.quote(self.name), wait_dur)
        timer.Create(timer_id, wait_dur, 1, function()
            self.speech_timer = nil
            gmod_tts.debug(2, "channel(name=%s):handle_queue on_success: audio %s ended, handle next.", gmod_tts.quote(self.name), gmod_tts.quote(audio_info.play_url))
            self.cur_audio_info = nil
            self:handle_queue()
        end)
        self.speech_timer = timer_id
        if self.paused then
            timer.Pause(timer_id)
        end
    end

    local function on_failure(request_info, msg)
        self.tts_request = nil
        if request_info.cancelled then
            gmod_tts.debug(2, "channel(name=%s):handle_queue on_failure: request is cancelled.", gmod_tts.quote(self.name))
            return
        end
        gmod_tts.debug(2, "channel(name=%s):handle_queue on_failure: failed to handle queue: %s.", gmod_tts.quote(self.name), msg)
        if request_info.response and request_info.response.status_code == 401 then
            gmod_tts.debug(0, "channel(name=%s) has unauthorized api client", gmod_tts.quote(self.name))
        end
        if self.sender.send_error then
            local ok, msg = pcall(self.sender.send_error, self, request_info, msg)
            if not ok then
                gmod_tts.debug(2, "channel(name=%s):handle_queue on_success: sender throws error when send_error: %s.", gmod_tts.quote(self.name), sender_status)
            end
        end
        self:handle_queue()
    end

    local tts_request = self.api_client:text_to_speech(text, voice, language, options)
    self.tts_request = tts_request
    tts_request:after(on_success, on_failure)
end

function channel_mt:pause()
    if self.paused then
        gmod_tts.debug(2, "channel(name=%s):pause: channel is already paused, exit.", gmod_tts.quote(self.name))
        return
    end
    gmod_tts.debug(1, "channel(name=%s):pause()", gmod_tts.quote(self.name))
    self.paused = true

    if self.speech_timer then
        timer.Pause(self.speech_timer)
        gmod_tts.debug(2, "channel(name=%s):pause: pause the speech timer and sending pause...", gmod_tts.quote(self.name))
        self.sender.pause(self, self.cur_audio_info, true)
    end
end

function channel_mt:unpause()
    if not self.paused then
        gmod_tts.debug(2, "channel(name=%s):unpause: channel is not paused, exit.", gmod_tts.quote(self.name))
        return
    end
    gmod_tts.debug(1, "channel(name=%s):unpause()", gmod_tts.quote(self.name))
    self.paused = false

    if self.speech_timer then
        timer.UnPause(self.speech_timer)
        gmod_tts.debug(2, "channel(name=%s):pause: unpause the speech timer and sending unpause...", gmod_tts.quote(self.name))
        self.sender.pause(self, self.cur_audio_info, false)
    else
        self:handle_queue()
    end
end

function channel_mt:stop()
    gmod_tts.debug(1, "channel(name=%s):stop()", gmod_tts.quote(self.name))
    self.queue:clear()
    if self.tts_request then
        gmod_tts.debug(2, "channel(name=%s):stop: cancel the current request.", gmod_tts.quote(self.name))
        self.tts_request.cancel()
        self.tts_request = nil
    end
    local cur_audio_info = self.cur_audio_info
    self.cur_audio_info = nil
    if self.speech_timer then
        gmod_tts.debug(2, "channel(name=%s):stop: stop the current speech timer and sending stop.", gmod_tts.quote(self.name))
        timer.Remove(self.speech_timer)
        self.speech_timer = nil
        self.sender.stop(self, cur_audio_info)
    end
end

function channel_mt:mute()
    if self.muted then
        gmod_tts.debug(2, "channel(name=%s):pause: channel is already muted, exit.", gmod_tts.quote(self.name))
        return
    end
    self.muted = true
    gmod_tts.debug(1, "channel(name=%s):mute()", gmod_tts.quote(self.name))
    self:stop()
end

function channel_mt:unmute()
    if not self.muted then
        gmod_tts.debug(2, "channel(name=%s):pause: channel is not muted, exit.", gmod_tts.quote(self.name))
        return
    end
    gmod_tts.debug(1, "channel(name=%s):unmute()", gmod_tts.quote(self.name))
    self.muted = false
end