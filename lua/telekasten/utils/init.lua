local M = {}

-- Prints a basic error message
local function print_error(s)
    vim.cmd("echohl ErrorMsg")
    vim.cmd("echomsg " .. '"' .. s .. '"')
    vim.cmd("echohl None")
end

-- Escapes Lua pattern characters for use in gsub
function M.escape(s)
    -- return s:gsub("[^%w]", "%%%1") -- Escape everything ?
    return s:gsub("[%%%]%^%-$().[*+?]", "%%%1")
end

-- Returns string with listed chars removed (= safer gsub)
function M.strip(s, chars_to_remove)
    return s:gsub("[" .. M.escape(chars_to_remove) .. "]", "")
end

-- strip an extension from a file name, escaping "." properly, eg:
-- strip_extension("path/Filename.md", ".md") -> "path/Filename"
local function strip_extension(str, ext)
    return str:gsub("(" .. ext:gsub("%.", "%%.") .. ")$", "")
end

return M
