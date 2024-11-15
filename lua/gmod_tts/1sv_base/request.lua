

local chain_error_tab = {}

function gmod_tts.chain_error(msg)
    return {
        [chain_error_tab] = true,
        message = msg
    }
end


local request_mt = {}
request_mt.__index = request_mt
gmod_tts.request_mt = request_mt

local function make_root_request(url, method, json)
    local request = setmetatable({}, gmod_tts.request_mt)
    local request_info = {}
    request_info.url = url
    request_info.method = method
    request_info.cancelled = false
    request_info.issued_at = util.DateStamp()
    request_info.root = request
    request_info.json = json
    request.info = request_info
    request.next = {}
    return request
end

local function debug_response_body(body)
    if not gmod_tts.debug_level(3) then
        return
    end
    local json_body = util.JSONToTable(body)
    if not json_body then
        gmod_tts.debug(3, "response body as text:\n" .. body)
    else
        gmod_tts.debug(3, "response body as json:\n" .. util.TableToJSON(json_body, true))
    end
end

local function make_http_callbacks(request)
    local function on_success(status_code, body, response_headers)
        if request.info.cancelled then
            gmod_tts.debug(3, "got http response with status code %s, but the %s request issued at %s has been cancelled.", status_code, request.info.method, request.info.issued_at)
            return
        end
        gmod_tts.debug(3, "got http response on the %s request issued at %s with status code %s.", request.info.method, request.info.issued_at, status_code)
        debug_response_body(body)
        request.info.root = nil
        request.info.response = { 
            status_code = status_code,
            body = body,
            headers = response_headers
        }
        request:resolve(status_code, body, response_headers)
    end

    local function on_failure(msg)
        if request.cancelled then
            gmod_tts.debug(3, "got http error with message %s, but the %s request issued at %s has been cancelled.", gmod_tts.quote(msg), request.info.method, request.info.issued_at)
            return
        end
        gmod_tts.debug(3, "got http error on the %s request issued at %s with message %s.", request.info.method, request.info.issued_at, gmod_tts.quote(msg))
        request.info.root = nil
        request:throw(msg)
    end

    return on_success, on_failure
end

function gmod_tts.http_get(url, headers)
    url = string.Trim(url or "")
    local request = make_root_request(url, "GET")
    if url == "" then
        gmod_tts.debug(2, "http_get: empty url, throw error")
        request:throw("no url")
        return request
    end
    gmod_tts.debug(1, "HTTP GET %s", url)
    local on_success, on_failure = make_http_callbacks(request)
    local ok = HTTP({
        method = "GET",
        url = url, 
        success = on_success, 
        failed = on_failure,
        headers = headers or {}
    })
    if not ok then
        gmod_tts.debug(2, "http_get: failed to do http request")
        request:throw("coudn't do http request")
    end
    return request
end

function gmod_tts.http_post(url, json_tab, headers)
    url = string.Trim(url or "")
    local request = make_root_request(url, "POST", json_tab)
    if url == "" then
        gmod_tts.debug(2, "http_post: empty url, throw error")
        request:throw("no url")
        return request
    end
    gmod_tts.debug(1, "HTTP POST %s", url)
    if gmod_tts.debug_level(3) then 
        gmod_tts.debug(3, "HTTP POST json:\n%s", util.TableToJSON(json_tab, true))
    end
    local on_success, on_failure = make_http_callbacks(request)
    local ok = HTTP({
        method = "POST",
        url = url, 
        success = on_success, 
        failed = on_failure,
        headers = headers or {},
        body = util.TableToJSON(json_tab),
        type = "application/json; charset=utf-8"
    })
    if not ok then
        gmod_tts.debug(2, "http_get: failed to do http request")
        request:throw("coudn't do http request")
    end
    return request
end

function request_mt:after(on_success, on_failure)
    local chain_request = setmetatable({}, gmod_tts.request_mt)
    if on_success then
        self.on_success_func = on_success
    end
    if on_failure then
        self.on_failure_func = on_failure
    end
    chain_request.info = self.info
    chain_request.next = {}
    self.next[#self.next + 1] = chain_request
    if self.result then    
        self:resolve(unpack(self.result))
    end
    return chain_request
end

function request_mt:cancel()
    if self.info.cancelled or not self.info.root then
        return
    end
    gmod_tts.debug(3, "%s request issued at %s is cancelled.", self.info.method, self.info.issued_at)
    self.info.cancelled = true
    self.info.root = nil
    request:throw("request is cancelled")
end

function request_mt:resolve(...)
    local first_arg = select(1, ...)
    local result = {}
    if type(first_arg) == "table" and first_arg[chain_error_tab] then
        if self.on_failure_func then
            local next_msg = self.on_failure_func(self.info, first_arg.message)
            if next_msg then
                result = {gmod_tts.chain_error(next_msg)}
            end
        else
            result = {first_arg}
        end
    else
        if self.on_success_func then
            result = {self.on_success_func(self.info, ...)}
        else
            result = {...}
        end
    end

    self.result = result
    local next_requests = self.next 
    self.next = {}
    for i, n in ipairs(next_requests) do
        n:resolve(unpack(result))
    end
end

function request_mt:throw(message)
    self:resolve(gmod_tts.chain_error(message))
end