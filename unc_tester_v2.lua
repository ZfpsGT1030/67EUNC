local RAW_SCRIPT_URL = "https://raw.githubusercontent.com/ZfpsGT1030/67EUNC/main/unc_tester.lua"
local OLD_API_URL = "https://67unc.vercel.app/api/results"
local NEW_API_URL = "https://67unc.vercel.app/api/upload"
local CHUNK_SIZE = 700

local function _getReqFn()
    if type(request) == "function" then return request, "request" end
    if type(http_request) == "function" then return http_request, "http_request" end
    if type(http) == "table" and type(http.request) == "function" then return http.request, "http.request" end
    return nil, nil
end

local function _cloneHeaders(src)
    local out = {}
    if type(src) == "table" then
        for k, v in pairs(src) do
            out[k] = v
        end
    end
    return out
end

local function _makeQueryUrl(httpSvc, baseUrl, params)
    local parts = {}
    for k, v in pairs(params or {}) do
        parts[#parts + 1] = tostring(k) .. "=" .. httpSvc:UrlEncode(tostring(v))
    end
    table.sort(parts)
    return baseUrl .. "?" .. table.concat(parts, "&")
end

local function _statusOf(res)
    if type(res) ~= "table" then return nil end
    return tonumber(res.StatusCode or res.Status or res.status)
end

local function _bodyOf(res)
    if type(res) ~= "table" then return "" end
    return tostring(res.Body or res.body or "")
end

local function _uploadViaGetFallback(origReq, httpSvc, rawJson)
    local okInit, initRes = pcall(origReq, {
        Url = _makeQueryUrl(httpSvc, NEW_API_URL, { action = "init" }),
        Method = "GET"
    })
    if not okInit or type(initRes) ~= "table" then
        return false, initRes
    end

    local initStatus = _statusOf(initRes)
    local initBody = _bodyOf(initRes)
    if not initStatus or initStatus < 200 or initStatus >= 300 then
        return false, initRes
    end

    local okDecode, initData = pcall(function()
        return httpSvc:JSONDecode(initBody ~= "" and initBody or "{}")
    end)
    if not okDecode or type(initData) ~= "table" or type(initData.id) ~= "string" then
        return false, { StatusCode = 417, Body = initBody ~= "" and initBody or "Fallback init failed" }
    end

    local uploadId = initData.id
    local i = 1
    while i <= #rawJson do
        local chunk = string.sub(rawJson, i, i + CHUNK_SIZE - 1)
        local okChunk, chunkRes = pcall(origReq, {
            Url = _makeQueryUrl(httpSvc, NEW_API_URL, {
                action = "chunk",
                id = uploadId,
                data = chunk,
            }),
            Method = "GET"
        })
        if not okChunk or type(chunkRes) ~= "table" then
            return false, chunkRes
        end
        local chunkStatus = _statusOf(chunkRes)
        if not chunkStatus or chunkStatus < 200 or chunkStatus >= 300 then
            return false, chunkRes
        end
        i = i + CHUNK_SIZE
    end

    local okFinal, finalRes = pcall(origReq, {
        Url = _makeQueryUrl(httpSvc, NEW_API_URL, {
            action = "finalize",
            id = uploadId,
        }),
        Method = "GET"
    })
    if not okFinal or type(finalRes) ~= "table" then
        return false, finalRes
    end

    local finalStatus = _statusOf(finalRes)
    if finalStatus and finalStatus >= 200 and finalStatus < 300 then
        print("[UNC] Upload mode : GET chunk fallback")
        return true, finalRes
    end

    return false, finalRes
end

local function _installWrapper()
    local origReq, slot = _getReqFn()
    if type(origReq) ~= "function" then
        warn("[UNC] No HTTP request function found for upload wrapper")
        return
    end

    local httpSvc = game:GetService("HttpService")

    local function wrappedReq(opts)
        if type(opts) ~= "table" then
            return origReq(opts)
        end

        local url = tostring(opts.Url or opts.url or "")
        local method = string.upper(tostring(opts.Method or opts.method or "GET"))

        if method == "POST" and (url == OLD_API_URL or url == NEW_API_URL) then
            local body = tostring(opts.Body or opts.body or "")
            local headers = _cloneHeaders(opts.Headers or opts.headers)
            headers["Content-Type"] = headers["Content-Type"] or "application/json"
            headers["Expect"] = ""

            local postOpts = {}
            for k, v in pairs(opts) do postOpts[k] = v end
            postOpts.Url = NEW_API_URL
            postOpts.Method = "POST"
            postOpts.Headers = headers
            postOpts.Body = body

            local okPost, postRes = pcall(origReq, postOpts)
            local postStatus = okPost and _statusOf(postRes) or nil

            if okPost and type(postRes) == "table" and postStatus and postStatus ~= 417 then
                return postRes
            end

            local okFallback, fallbackRes = _uploadViaGetFallback(origReq, httpSvc, body)
            if okFallback and type(fallbackRes) == "table" then
                return fallbackRes
            end

            if type(fallbackRes) == "table" then
                return fallbackRes
            end
            if type(postRes) == "table" then
                return postRes
            end

            return {
                StatusCode = 417,
                Body = tostring(fallbackRes or postRes or "Upload fallback failed")
            }
        end

        if url == OLD_API_URL then
            local pass = {}
            for k, v in pairs(opts) do pass[k] = v end
            pass.Url = NEW_API_URL
            return origReq(pass)
        end

        return origReq(opts)
    end

    if slot == "request" then
        request = wrappedReq
    elseif slot == "http_request" then
        http_request = wrappedReq
    elseif slot == "http.request" then
        http.request = wrappedReq
    end

    if type(request) == "function" then request = wrappedReq end
    if type(http_request) == "function" then http_request = wrappedReq end
    if type(http) == "table" and type(http.request) == "function" then http.request = wrappedReq end
end

_installWrapper()

local okSrc, src = pcall(function()
    return game:HttpGet(RAW_SCRIPT_URL)
end)

if not okSrc or type(src) ~= "string" or src == "" then
    error("Failed to fetch upstream unc_tester.lua")
end

local chunk = src:gsub(OLD_API_URL, OLD_API_URL)
local fn, loadErr = loadstring(chunk)
if not fn then
    error(loadErr or "Failed to load upstream unc_tester.lua")
end

return fn()
