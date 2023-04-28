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

-- Returns the file extension
function M.get_extension(fname)
    return fname:match("^.+(%..+)$")
end

-- Strips an extension from a file name, escaping "." properly, eg:
-- strip_extension("path/Filename.md", ".md") -> "path/Filename"
local function strip_extension(str, ext)
    return str:gsub("(" .. ext:gsub("%.", "%%.") .. ")$", "")
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

local function random_variable(length)
    math.randomseed(os.clock() ^ 5)
    local res = ""
    for _ = 1, length do
        res = res .. string.char(math.random(97, 122))
    end
    return res
end

function M.new_uuid(uuid_style)
    local uuid
    if uuid_style == "rand" then
        uuid = random_variable(6)
    elseif type(uuid_style) == "function" then
        uuid = uuid_style()
    else
        uuid = os.date(uuid_style)
    end
    return uuid
end

return M
