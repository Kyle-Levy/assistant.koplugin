-- filepath: /Users/Q620675/Code/assistant.koplugin/api_handlers/azure_openai.lua
local BaseHandler = require("api_handlers.base")
local https = require("ssl.https")
local ltn12 = require("ltn12")
local json = require("json")
local logger = require("logger")
local Device = require("device")

local AzureOpenAIHandler = BaseHandler:new()

function AzureOpenAIHandler:makeRequest(url, headers, body)
    logger.dbg("Attempting Azure OpenAI API request:", {
        url = url,
        headers = headers and "present" or "missing",
        body_length = #body
    })
    
    -- Try using curl first (more reliable on Kindle)
    if Device:isKindle() then
        local tmp_request = "/tmp/azure_openai_request.json"
        local tmp_response = "/tmp/azure_openai_response.json"
        
        -- Write request body
        local f = io.open(tmp_request, "w")
        if f then
            f:write(body)
            f:close()
        end
        
        -- Construct curl command with proper headers
        local header_args = ""
        for k, v in pairs(headers) do
            header_args = header_args .. string.format(' -H "%s: %s"', k, v)
        end
        
        local curl_cmd = string.format(
            'curl -k -s -X POST%s --connect-timeout 30 --retry 2 --retry-delay 3 '..
            '--data-binary @%s "%s" -o %s',
            header_args, tmp_request, url, tmp_response
        )
        
        logger.dbg("Executing curl command:", curl_cmd:gsub(headers["api-key"], "api-key ***")) -- Hide API key in logs
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
            return true, 200, response
        end
    end
    
    -- Fallback to standard HTTPS if curl fails or not on Kindle
    logger.dbg("Attempting HTTPS fallback request")
    local response = {}
    local status, code, responseHeaders = https.request{
        url = url,
        method = "POST",
        headers = headers,
        source = ltn12.source.string(body),
        sink = ltn12.sink.table(response),
        protocol = "tlsv1_2",
        verify = "none", -- Disable SSL verification for Kindle
        timeout = 30
    }
    
    return status, code, table.concat(response)
end

function AzureOpenAIHandler:query(message_history, config)
    local azure_settings = config.provider_settings and config.provider_settings.azure_openai
    
    -- Check required settings
    for _, setting in ipairs({"api_key", "endpoint", "deployment_name", "api_version"}) do
        if not azure_settings or not azure_settings[setting] then
            return nil, "Error: Missing " .. setting .. " in configuration"
        end
    end
    
    -- Construct the Azure OpenAI API URL
    local api_url = string.format(
        "%s/openai/deployments/%s/chat/completions?api-version=%s",
        azure_settings.endpoint:gsub("/$", ""),  -- Remove trailing slash if present
        azure_settings.deployment_name,
        azure_settings.api_version
    )
    
    -- Prepare request body
    local requestBodyTable = {
        messages = message_history,
        max_tokens = azure_settings.max_tokens,
        temperature = azure_settings.temperature or 0.7
    }
    
    local requestBody = json.encode(requestBodyTable)
    local headers = {
        ["Content-Type"] = "application/json",
        ["api-key"] = azure_settings.api_key,
        ["HTTP-Referer"] = "https://github.com/omer-faruq/assistant.koplugin",
        ["X-Title"] = "assistant.koplugin"
    }
    
    local status, code, response = self:makeRequest(api_url, headers, requestBody)
    
    if status and code == 200 then
        local success, responseData = pcall(json.decode, response)
        if success and responseData and responseData.choices and responseData.choices[1] then
            return responseData.choices[1].message.content
        end
    end
    
    return nil, "Error: " .. (code or "unknown") .. " - " .. response
end

return AzureOpenAIHandler