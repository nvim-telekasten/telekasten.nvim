-- Misc utils

local M = {}

-- Print standard error message
M.print_error = function(s)
    vim.cmd("echohl ErrorMsg")
    vim.cmd("echomsg " .. '"' .. s .. '"')
    vim.cmd("echohl None")
end

return M
