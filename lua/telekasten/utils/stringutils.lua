-- Utils for string manipulation

local M = {}

-- Sanitize strings
M.escape_chars = function(string)
    return string.gsub(string, "[%(|%)|\\|%[|%]|%-|%{%}|%?|%+|%*|%^|%$|%/]", {
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

--- escapes a string for use as exact pattern within gsub
M.escape = function(s)
    return string.gsub(s, "[%%%]%^%-$().[*+?]", "%%%1")
end

return M
