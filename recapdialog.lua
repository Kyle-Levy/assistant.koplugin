local InputDialog = require("ui/widget/inputdialog")
local ChatGPTViewer = require("chatgptviewer")
local UIManager = require("ui/uimanager")
local TextBoxWidget = require("ui/widget/textboxwidget")
local _ = require("gettext")
local Event = require("ui/event")
local queryChatGPT = require("gpt_query")
local configuration = require("configuration")

local function showRecapDialog(ui, title, author, progress_percent, message_history)
	local formatted_progress_percent = string.format("%.2f", progress_percent * 100)
    local message_history = message_history or {
        {
            role = "system",
            content = "You are a book recap giver with entertaining tone and high quality detail with a focus on summarization. You also match the tone of the book provided.",
        },
    }
    
    local context_message = {
        role = "user",
		content = title .. " by " .. author .. " that has been " .. formatted_progress_percent .. "% read.\n" ..
            "Given the above title and author of a book and the positional parameter, very briefly summarize the contents of the book prior with rich text formatting.\n" ..
            "Above all else do not give any spoilers to the book, only consider prior content. Focus on the more recent content rather than a general summary to help the user pick up where they left off. \n" ..
			"Match the tone and energy of the book, for example if the book is funny match that style of humor and tone, if it's an exciting fantasy novel show it, if it's a historical or sad book reflect that.\n" ..
			"Use text bolding to emphasize names and locations. Use italics to emphasize major plot points. No emojis or symbols.\n" ..
            "Answer this whole response in ".. configuration.features.dictionary_translate_to .." language.\n" ..
            "only show the replies, do not give a description."
    }
    table.insert(message_history, context_message)

    local answer = queryChatGPT(message_history)
    local function createResultText(answer)
        local result_text = 
            TextBoxWidget.PTF_HEADER .. 
            TextBoxWidget.PTF_BOLD_START .. title .. TextBoxWidget.PTF_BOLD_END .. " by " .. author .. " is " .. formatted_progress_percent .. "% complete.\n\n" ..
            answer 
        return result_text
    end

    local result_text = createResultText(answer)
    local chatgpt_viewer = nil

    chatgpt_viewer = ChatGPTViewer:new {
        ui = ui,
        title = _("Recap"),
        text = result_text,
        showAskQuestion = false
    }

    UIManager:show(chatgpt_viewer)
    if configuration and configuration.features and configuration.features.refresh_screen_after_displaying_results then
        UIManager:setDirty(nil, "full")
    end
end

return showRecapDialog