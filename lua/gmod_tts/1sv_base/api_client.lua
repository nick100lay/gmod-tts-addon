

local function put_secret_key(headers, secret_key)
    headers.Authorization = "Bearer " .. secret_key
    return headers
end


local api_client_mt = {}
api_client_mt.__index = api_client_mt
gmod_tts.api_client_mt = api_client_mt

function gmod_tts.make_api_client(base_url, secret_key)
    local api_client = setmetatable({}, api_client_mt)
    api_client.base_url = base_url
    api_client.secret_key = secret_key
    return api_client
end

function api_client_mt:text_to_speech(text, voice, language, options)
    local base_url = string.Trim(self.base_url or "")
    local secret_key = string.Trim(self.secret_key or "")
    local headers = {}
    if base_url == "" then
        gmod_tts.debug(2, "api_client:text_to_speech: base_url is empty, exit.")
        return gmod_tts.http_post()
    end
    gmod_tts.debug(1, "api_client(base_url=%s):text_to_speech(text=%s, voice=%s, options={...})", gmod_tts.quote(base_url), gmod_tts.quote(text), gmod_tts.quote(voice))
    if secret_key ~= "" then
        gmod_tts.debug(2, "api_client:text_to_speech: put secret key.")
        put_secret_key(headers, secret_key)
    end
    if options and table.Count(options) == 0 then
        options = nil
    end
    local json = {
        text = text,
        voice = voice,
        language = language,
        options = options
    } 

    local function on_success(request_info, status_code, body)
        if status_code < 200 or status_code >= 300 then
            gmod_tts.debug(2, "api_client:text_to_speech on_success: status code %s, throw error.", status_code)
            return gmod_tts.chain_error(string.format("status code %s", status_code))
        end
        data = util.JSONToTable(body)
        if not data then
            gmod_tts.debug(2, "api_client:text_to_speech on_success: bad response structure, throw error.")
            return gmod_tts.chain_error(string.format("bad response", status_code))
        end
        gmod_tts.debug(2, "api_client:text_to_speech on_success: got response play_url=%s duration=%.3f play_url_expires_at=%s.", 
            gmod_tts.quote(data.play_url), data.duration, gmod_tts.quote(data.play_url_expires_at)
        )
        return data
    end

    return gmod_tts.http_post(gmod_tts.concat_url_components(base_url, "tts"), json, headers):after(on_success)
end

function api_client_mt:fetch_info()
    local base_url = string.Trim(self.base_url or "")
    local secret_key = string.Trim(self.secret_key or "")
    local headers = {}
    if base_url == "" then
        gmod_tts.debug(2, "api_client:fetch_info: base_url is empty, exit.")
        return gmod_tts.http_get()
    end
    gmod_tts.debug(1, "api_client(base_url=%s):fetch_info()", gmod_tts.quote(base_url))
    if secret_key ~= "" then
        gmod_tts.debug(2, "api_client:fetch_info: put secret key.")
        put_secret_key(headers, secret_key)
    end

    local function on_success(request_info, status_code, body)
        if status_code < 200 or status_code >= 300 then
            gmod_tts.debug(2, "api_client:fetch_info on_success: status code %s, throw error.", status_code)
            return gmod_tts.chain_error(string.format("status code %s", status_code))
        end
        data = util.JSONToTable(body)
        if not data then
            gmod_tts.debug(2, "api_client:fetch_info on_success: bad response structure, throw error.")
            return gmod_tts.chain_error(string.format("bad response", status_code))
        end
        gmod_tts.debug(2, "api_client:fetch_info on_success: got gmod tts server information")
        return data
    end

    return gmod_tts.http_get(gmod_tts.concat_url_components(base_url, "info"), headers):after(on_success)
end

