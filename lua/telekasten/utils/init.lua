local M = {}

--- Escapes Lua pattern characters for use in gsub
function M.escape(s)
    -- return s:gsub("[^%w]", "%%%1") -- Escape everything ?
    return s:gsub("[%%%]%^%-$().[*+?]", "%%%1")
end

--- Returns string with listed chars removed (= safer gsub)
function M.strip(s, chars_to_remove)
    return s:gsub("[" .. M.escape(chars_to_remove) .. "]", "")
end

-- strip an extension from a file name, escaping "." properly, eg:
-- strip_extension("path/Filename.md", ".md") -> "path/Filename"
local function strip_extension(str, ext)
    return str:gsub("(" .. ext:gsub("%.", "%%.") .. ")$", "")
end

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
