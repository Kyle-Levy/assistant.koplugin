local api_key = nil
local CONFIGURATION = nil

-- Attempt to load the configuration module first
local success, result = pcall(function() return require("configuration") end)
if success then
    CONFIGURATION = result
else
    print("No configuration found. Please set up configuration.lua")
end

-- Define handlers table with proper error handling
local handlers = {}
local function loadHandler(name)
    local success, handler = pcall(function()
        return require("api_handlers." .. name)
    end)
    if success then
        handlers[name] = handler
    else
        print("Failed to load " .. name .. " handler: " .. tostring(handler))
    end
end

local provider_handlers = {
    anthropic = function() loadHandler("anthropic") end,
    openai = function() loadHandler("openai") end,
    deepseek = function() loadHandler("deepseek") end,
    gemini = function() loadHandler("gemini") end,
    openrouter = function() loadHandler("openrouter") end,
    ollama = function() loadHandler("ollama") end,
    mistral = function() loadHandler("mistral") end,
    groq = function() loadHandler("groq") end,
    azure_openai = function() loadHandler("azure_openai") end
}

if CONFIGURATION and CONFIGURATION.provider and provider_handlers[CONFIGURATION.provider] then
    provider_handlers[CONFIGURATION.provider]()
end

local function getApiKey(provider)
    if CONFIGURATION and CONFIGURATION.provider_settings and
       CONFIGURATION.provider_settings[provider] and
       CONFIGURATION.provider_settings[provider].api_key then
        return CONFIGURATION.provider_settings[provider].api_key
    end
    return nil
end

local function queryChatGPT(message_history)
    if not CONFIGURATION then
        return "Error: No configuration found. Please set up configuration.lua"
    end

    local provider = CONFIGURATION.provider 
    
    if not provider then
        return "Error: No provider specified in configuration"
    end

    local handler = handlers[provider]

    if not handler then
        return "Error: Unsupported provider " .. provider .. ". Please check configuration.lua"
    end

    -- Get API key for the selected provider
    CONFIGURATION.api_key = getApiKey(provider)
    if not CONFIGURATION.api_key then
        return "Error: No API key found for provider " .. provider .. ". Please check configuration.lua"
    end

    local success, result = pcall(function()
        return handler:query(message_history, CONFIGURATION)
    end)

    if not success then
        return "Error: " .. tostring(result)
    end

    return result
end

return queryChatGPT
