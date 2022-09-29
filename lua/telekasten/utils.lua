local M = {}

function M.prompt_title(callback)
    local canceledStr = "__INPUT_CANCELLED__"

    vim.ui.input({
        prompt = "Title: ",
        default = "",
        cancelreturn = canceledStr,
    }, function(title)
        if title == canceledStr then
            vim.cmd("echohl WarningMsg")
            vim.cmd("echomsg 'Note creation cancelled!'")
            vim.cmd("echohl None")
        else
            callback(title)
        end
    end)
end

return M
