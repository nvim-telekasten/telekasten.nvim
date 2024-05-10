local config = require("telekasten.config")
local fileutils = require("telekasten.utils.files")

local vim = vim

local M = {}

-- Prints a basic error message
function M.print_error(s)
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

-- Escapes for regex functions like grep or rg
function M.grep_escape(s)
    return s:gsub("[%(|%)|\\|%[|%]|%-|%{%}|%?|%+|%*|%^|%$|%/]", {
        ["\\"] = "\\\\",
        ["-"] = "\\-",
        ["("] = "\\(",
        [")"] = "\\)",
        ["["] = "\\[",
        ["]"] = "\\]",
        ["{"] = "\\{",
        ["}"] = "\\}",
        ["?"] = "\\?",
        ["+"] = "\\+",
        ["*"] = "\\*",
        ["^"] = "\\^",
        ["$"] = "\\$",
    })
end

-- N/A -> N/A
-- No return
-- Saves all modified buffers if auto_set_filetype and buffer's filetype is telekasten or if not auto_set_filetype
-- Move to utils/files.lua? Arguably file related, but maybe better utils/init.lua
function M.save_all_mod_buffers()
    for i = 1, vim.fn.bufnr("$") do
        if
            vim.fn.getbufvar(i, "&mod") == 1
            and (
                (
                    config.options.auto_set_filetype == true
                    and vim.fn.getbufvar(i, "&filetype") == "telekasten"
                )
                or config.options.auto_set_filetype == false
            )
        then
            vim.cmd(i .. "bufdo w")
        end
    end
end

-- string, string, string -> N/A
-- No return, runs ripgrep and sed if and only if the global dir check passes
-- ripgrep finds all files with instances of 'old' in 'dir'
-- sed takes file list from rg and replaces all instances of 'old' with 'new'
-- Move to utils/files.lua? Arguably file related
function M.recursive_substitution(dir, old, new)
    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        if vim.fn.executable("sed") == 0 then
            vim.api.nvim_err_write("Sed not installed!\n")
            return
        end

        old = M.grep_escape(old)
        new = M.grep_escape(new)

        local sedcommand = "sed -i"
        if vim.fn.has("mac") == 1 then
            sedcommand = "sed -i ''"
        end

        -- 's|\(\[\[foo\)\([]#|\]\)|\[\[MYTEST\2|g'
        local replace_cmd = "rg -0 -l -t markdown '"
            .. old
            .. "' "
            .. dir
            .. " | xargs -0 "
            .. sedcommand
            .. " 's|\\("
            .. old
            .. "\\)\\([]#|]\\)|"
            .. new
            .. "\\2|g' >/dev/null 2>&1"
        os.execute(replace_cmd)
    end)
end

return M
