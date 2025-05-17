local BaseHandler = require("api_handlers.base")
local https = require("ssl.https")
local ltn12 = require("ltn12")
local json = require("json")
local socket = require("socket")
local logger = require("logger")
local Device = require("device")

local GeminiHandler = BaseHandler:new()

-- Add fallback HTTP request function
function GeminiHandler:makeRequest(url, headers, body)
    logger.dbg("Attempting Gemini API request:", {
        url = url,
        headers = headers,
        body_length = #body
    })
    
    -- Try using curl first (more reliable on Kindle)
    if Device:isKindle() then
        local tmp_request = "/tmp/gemini_request.json"
        local tmp_response = "/tmp/gemini_response.json"
        
        -- Write request body
        local f = io.open(tmp_request, "w")
        if f then
            f:write(body)
            f:close()
        end
        
        -- Construct curl command with proper options for Kindle
        local curl_cmd = string.format(
            'curl -k -s -X POST -H "Content-Type: application/json" '..
            '--connect-timeout 30 --retry 2 --retry-delay 3 '..
            '--data-binary @%s "%s" -o %s',
            tmp_request, url, tmp_response
        )
        
        logger.dbg("Executing curl command:", curl_cmd)
        local curl_result = os.execute(curl_cmd)
        logger.dbg("Curl execution result:", curl_result)
        
        -- Read response
        local response = nil
        f = io.open(tmp_response, "r")
        if f then
            response = f:read("*all")
            f:close()
            logger.dbg("Curl response length:", #response)
        else
            logger.warn("Failed to read curl response file")
        end
        
        -- Cleanup
        os.remove(tmp_request)
        os.remove(tmp_response)
        
        if response then
            return true, response
        end
    end
    
    -- Fallback to standard HTTPS if curl fails
    logger.dbg("Attempting HTTPS fallback request")
    local responseBody = {}
    local success, code, headers_response = https.request({
        url = url,
        method = "POST",
        headers = headers,
        source = ltn12.source.string(body),
        sink = ltn12.sink.table(responseBody),
        timeout = 30,
        verify = "none", -- Disable SSL verification for Kindle
    })
    
    logger.dbg("HTTPS request details:", {
        success = success,
        code = code,
        response_headers = headers_response,
        response_length = responseBody and #table.concat(responseBody) or 0,
        error_type = type(code),
        error_message = tostring(code)
    })
    
    if success then
        return true, table.concat(responseBody)
    end
    
    -- Log detailed error information
    local error_info = {
        error_type = type(code),
        error_message = tostring(code),
        ssl_loaded = package.loaded["ssl"] ~= nil,
        https_loaded = package.loaded["ssl.https"] ~= nil,
        socket_loaded = package.loaded["socket"] ~= nil,
        device_info = {
            is_kindle = Device:isKindle(),
            model = Device:getModel(),
            firmware = Device:getFirmware(),
        }
    }
    
    logger.warn("Gemini API request failed with details:", error_info)
    return false, code
end

function GeminiHandler:query(message_history, config)
    if not config or not config.api_key then
        return "Error: Missing API key in configuration"
    end

    -- Gemini API requires messages with explicit roles
    local contents = {}
    local systemMessage = nil

    for i, msg in ipairs(message_history) do
        -- First message is treated as system message
        if i == 1 and msg.role ~= "user" then
            systemMessage = {
                role = "user",
                parts = {{ text = msg.content }}
            }
        else
            table.insert(contents, {
                role = "user",
                parts = {{ text = msg.content }}
            })
        end
    end

    -- If a system message exists, insert it at the beginning
    if systemMessage then
        table.insert(contents, 1, systemMessage)
    end

    local requestBodyTable = {
        contents = contents,
        safety_settings = {
            { category = "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold = "BLOCK_NONE" },
            { category = "HARM_CATEGORY_HATE_SPEECH", threshold = "BLOCK_NONE" },
            { category = "HARM_CATEGORY_HARASSMENT", threshold = "BLOCK_NONE" },
            { category = "HARM_CATEGORY_DANGEROUS_CONTENT", threshold = "BLOCK_NONE" }
        }
    }

    local requestBody = json.encode(requestBodyTable)
    
    local headers = {
        ["Content-Type"] = "application/json"
    }

    local gemini_settings = config.provider_settings and config.provider_settings.gemini or {}
    local model = gemini_settings.model or "gemini-1.5-pro-latest"
    local base_url = gemini_settings.base_url or "https://generativelanguage.googleapis.com/v1beta/models/"
    
    local url = string.format("%s%s:generateContent?key=%s", base_url, model, config.api_key)
    logger.dbg("Making Gemini API request to model:", model)
    
    local success, response = self:makeRequest(url, headers, requestBody)

    if not success then
        logger.warn("Gemini API request failed:", {
            error = response,
            model = model,
            base_url = base_url:gsub(config.api_key, "***"), -- Hide API key in logs
            request_size = #requestBody,
            message_count = #message_history
        })
        return "Error: Failed to connect to Gemini API - " .. tostring(response)
    end

    local success, parsed = pcall(json.decode, response)
    
    if not success then
        logger.warn("JSON Decode Error:", parsed)
        return "Error: Failed to parse Gemini API response"
    end
    
    if parsed and parsed.candidates and parsed.candidates[1] and 
       parsed.candidates[1].content and parsed.candidates[1].content.parts and
       parsed.candidates[1].content.parts[1] then
        return parsed.candidates[1].content.parts[1].text
    else
        return "Error: Unexpected response format from Gemini API"
    end
end

return GeminiHandler