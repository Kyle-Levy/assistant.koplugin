local Device = require("device")
local InputContainer = require("ui/widget/container/inputcontainer")
local NetworkMgr = require("ui/network/manager")
local _ = require("gettext")

local showChatGPTDialog = require("dialogs")
local UpdateChecker = require("update_checker")

local Assistant = InputContainer:new {
  name = "Assistant",
  is_doc_only = true,
}

-- Load Configuration
local CONFIGURATION = nil
local success, result = pcall(function() return require("configuration") end)
if success then
  CONFIGURATION = result
else
  print("configuration.lua not found, skipping...")
end

-- Flag to ensure the update message is shown only once per session
local updateMessageShown = false

function Assistant:init()
  -- Assistant button
  self.ui.highlight:addToHighlightDialog("assistant", function(_reader_highlight_instance)
    return {
      text = _("Assistant"),
      enabled = Device:hasClipboard(),
      callback = function()
        if not CONFIGURATION then
          local UIManager = require("ui/uimanager")
          local InfoMessage = require("ui/widget/infomessage")
          UIManager:show(InfoMessage:new{
            text = _("Configuration not found. Please set up configuration.lua first.")
          })
          return
        end
        NetworkMgr:runWhenOnline(function()
          if not updateMessageShown then
            UpdateChecker.checkForUpdates()
            updateMessageShown = true
          end
          showChatGPTDialog(self.ui, _reader_highlight_instance.selected_text.text)
        end)
      end,
    }
  end)
  -- Dictionary button
  if CONFIGURATION and CONFIGURATION.features and CONFIGURATION.features.dictionary_translate_to and CONFIGURATION.features.show_dictionary_button_in_main_popup then
    self.ui.highlight:addToHighlightDialog("dictionary", function(_reader_highlight_instance)
      return {
          text = _("Dictionary").." (AI)",
          enabled = Device:hasClipboard(),
          callback = function()
              NetworkMgr:runWhenOnline(function()
                  local showDictionaryDialog = require("dictdialog")
                  showDictionaryDialog(self.ui, _reader_highlight_instance.selected_text.text)
              end)
          end,
      }
    end)
  end

  -- Add Custom buttons (ones with show_on_main_popup = true)
  if CONFIGURATION and CONFIGURATION.features and CONFIGURATION.features.prompts then
    local _ = require("gettext")  -- Ensure gettext is available in this scope
    -- Create a sorted list of prompts
    local sorted_prompts = {}
    for prompt_type, prompt in pairs(CONFIGURATION.features.prompts) do
      if prompt.show_on_main_popup then
        table.insert(sorted_prompts, {type = prompt_type, config = prompt})
      end
    end
    
    -- Sort by order value, default to 1000 if not specified
    table.sort(sorted_prompts, function(a, b)
      local order_a = a.config.order or 1000
      local order_b = b.config.order or 1000
      return order_a < order_b
    end)
    
    -- Add buttons in sorted order
    for _, prompt_data in ipairs(sorted_prompts) do
      local prompt_type = prompt_data.type
      local prompt = prompt_data.config
      -- Use order in the index for proper sorting (pad with zeros for consistent sorting)
      local order_str = string.format("%02d", prompt.order or 1000)
      self.ui.highlight:addToHighlightDialog("assistant_" .. order_str .. "_" .. prompt_type, function(_reader_highlight_instance)
        return {
          text = prompt.text.." (AI)", 
          enabled = Device:hasClipboard(),
          callback = function()
            NetworkMgr:runWhenOnline(function()
              showChatGPTDialog(self.ui, _reader_highlight_instance.selected_text.text, prompt_type)
            end)
          end,
        }
      end)
    end
  end
end

function Assistant:onDictButtonsReady(dict_popup, buttons)
  -- Add the "Dictionary (AI)" button if enabled in the configuration
  if CONFIGURATION and CONFIGURATION.features and CONFIGURATION.features.show_dictionary_button_in_dictionary_popup then
    table.insert(buttons, 1, {{
        id = "assistant_dictionary",
        text = _("Dictionary").." (AI)",
        font_bold = false,
        callback = function()
            NetworkMgr:runWhenOnline(function()
                local showDictionaryDialog = require("dictdialog")
                -- Pass the word from the dict_popup instead of the highlight instance:
                showDictionaryDialog(self.ui, dict_popup.lookupword)
            end)
        end,
    }})
  end

  -- Add the "Pronunciation" button if the prompt is defined in the configuration
  if CONFIGURATION and CONFIGURATION.features and CONFIGURATION.features.prompts and CONFIGURATION.features.prompts.pronunciation then
    local pronunciation_prompt = CONFIGURATION.features.prompts.pronunciation
    table.insert(buttons, 2, {{
        id = "assistant_pronunciation",
        text = (pronunciation_prompt.text or _("Pronunciation")) .. " (AI)",
        font_bold = false,
        callback = function()
            NetworkMgr:runWhenOnline(function()
                showChatGPTDialog(self.ui, dict_popup.lookupword, "pronunciation")
            end)
        end,
    }})
  end
end

return Assistant
