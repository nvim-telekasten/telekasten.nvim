local M = {}

-- Checks if file exists
function M.file_exists(fname)
    if fname == nil then
        return false
    end

    local f = io.open(fname, "r")
    if f ~= nil then
        io.close(f)
        return true
    else
        return false
    end
end

-- Prompts the user for a note title
function M.prompt_title(ext, defaultFile, callback)
    local canceledStr = "__INPUT_CANCELLED__"

    vim.ui.input({
        prompt = "Title: ",
        cancelreturn = canceledStr,
        completion = "file",
        default = defaultFile,
    }, function(title)
        if not title then
            title = ""
        end
        if title == canceledStr then
            vim.cmd("echohl WarningMsg")
            vim.cmd("echomsg 'Note creation cancelled!'")
            vim.cmd("echohl None")
        else
            title = strip_extension(title, ext)
            callback(title)
        end
    end)
end

return M
