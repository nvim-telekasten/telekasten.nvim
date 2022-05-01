-- Utils for path checks and path maniupulation
local Path = require("plenary.path")
local misc = require("telekasten.utils.misc")

local M = {}

-- Cleans home path for Windows users
M.clean_path = function(path)
    -- File path delimeter for Windows machines
    local windows_delim = "\\"
    -- Returns the path delimeter for the machine
    -- '\\' for Windows, '/' for Unix
    local system_delim = package.config:sub(1, 1)
    local new_path_start

    -- Removes portion of path before '\\' for Windows machines
    -- since Telescope does not like that
    if system_delim == windows_delim then
        new_path_start = path:find(windows_delim) -- Find the first '\\'
        if new_path_start ~= nil then
            path = path:sub(new_path_start) -- Start path at the first '\\'
        end
    end

    -- Returns cleaned path
    return path
end

-- Check if file exists or not
M.file_exists = function(fname)
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

-- Check if dir exists and ask if it should be created
M.check_dir_and_ask = function(dir, purpose)
    local ret = false
    if dir ~= nil and Path:new(dir):exists() == false then
        vim.cmd("echohl ErrorMsg")
        local answer = vim.fn.input(
            "Telekasten.nvim: "
                .. purpose
                .. " folder "
                .. dir
                .. " does not exist!"
                .. " Shall I create it? [y/N] "
        )
        vim.cmd("echohl None")
        answer = vim.fn.trim(answer)
        if answer == "y" or answer == "Y" then
            if Path:new(dir):mkdir({ exists_ok = false }) then
                vim.cmd('echomsg " "')
                vim.cmd('echomsg "' .. dir .. ' created"')
                ret = true
            else
                -- unreachable: plenary.Path:mkdir() will error out
                misc.print_error("Could not create directory " .. dir)
                ret = false
            end
        end
    else
        ret = true
    end
    return ret
end

-- Make image path relative to the current buffer
M.make_relative_path = function(bufferpath, imagepath, sep)
    sep = sep or "/"

    -- Split the buffer and image path into their dirs/files
    local buffer_dirs = {}
    for w in string.gmatch(bufferpath, "([^" .. sep .. "]+)") do
        buffer_dirs[#buffer_dirs + 1] = w
    end
    local image_dirs = {}
    for w in string.gmatch(imagepath, "([^" .. sep .. "]+)") do
        image_dirs[#image_dirs + 1] = w
    end

    -- The parts of the dir list that match won't matter, so skip them
    local i = 1
    while i < #image_dirs and i < #buffer_dirs do
        if image_dirs[i] ~= buffer_dirs[i] then
            break
        else
            i = i + 1
        end
    end

    -- Append ../ to walk up from the buffer location and the path downward
    -- to the location of the image file in order to create a relative path
    local relative_path = ""
    while i <= #image_dirs or i <= #buffer_dirs do
        if i <= #image_dirs then
            if relative_path == "" then
                relative_path = image_dirs[i]
            else
                relative_path = relative_path .. sep .. image_dirs[i]
            end
        end
        if i <= #buffer_dirs - 1 then
            relative_path = ".." .. sep .. relative_path
        end
        i = i + 1
    end

    return relative_path
end

-- Return file extension
M.file_extension = function(fname)
    return fname:match("^.+(%..+)$")
end

return M
