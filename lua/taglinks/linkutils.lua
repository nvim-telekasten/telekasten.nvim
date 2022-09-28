-- local async = require("plenary.async")
local scan = require("plenary.scandir")

local M = {}

local function file_exists(fn, file_list)
    return file_list[fn] ~= nil
end

local function resolve_link(title, file_list, subdir_list, opts)
    local fexists = false
    local filename = title .. opts.extension
    filename = filename:gsub("^%./", "") -- strip potential leading ./

    if
        opts.weeklies
        and file_exists(opts.weeklies .. "/" .. filename, file_list)
    then
        filename = opts.weeklies .. "/" .. filename
        fexists = true
    end
    if
        opts.dailies and file_exists(opts.dailies .. "/" .. filename, file_list)
    then
        filename = opts.dailies .. "/" .. filename
        fexists = true
    end
    if file_exists(opts.home .. "/" .. filename, file_list) then
        filename = opts.home .. "/" .. filename
        fexists = true
    end

    if fexists == false then
        -- now search for it in all subdirs
        local tempfn
        for _, folder in pairs(subdir_list) do
            tempfn = folder .. "/" .. filename
            -- [[testnote]]
            if file_exists(tempfn, file_list) then
                filename = tempfn
                fexists = true
                -- print("Found: " .. filename)
                break
            end
        end
    end

    if fexists == false then
        -- default fn for creation
        filename = opts.home .. "/" .. filename
    end
    return fexists, filename
end

-- TODO: cache mtimes and only update if changed

-- The reason we go over all notes in one go, is: backlinks
-- We generate 2 maps: one containing the number of links within a note
--    and a second one containing the number of backlinks to a note
-- Since we're parsing all notes anyway, we can mark linked notes as backlinked from the currently parsed note
M.generate_backlink_map = function(opts)
    assert(opts ~= nil, "opts must not be nil")
    -- TODO: check for code blocks
    -- local in_fenced_code_block = false
    -- also watch out for \t tabbed code blocks or ones with leading spaces that don't end up in a - or * list

    -- first, find all notes
    assert(opts.extension ~= nil, "Error: need extension in opts!")
    assert(opts.home ~= nil, "Error: need home dir in opts!")

    -- async seems to have lost await and we don't want to enter callback hell, hence we go sync here
    local subdir_list = scan.scan_dir(opts.home, { only_dirs = true })
    local file_list = {}
    -- transform the file list
    local _x = scan.scan_dir(opts.home, {
        search_pattern = function(entry)
            return entry:sub(-#opts.extension) == opts.extension
        end,
    })
    for _, v in pairs(_x) do
        file_list[v] = true
    end

    -- now process all the notes
    local link_counts = {}
    local backlink_counts = {}
    for note_fn, _ in pairs(file_list) do
        -- print("processing " .. note_fn .. "...")
        -- go over file line by line
        for line in io.lines(note_fn) do
            for linktitle in line:gmatch("%[%[(.-)%]%]") do
                -- strip # from title
                linktitle = linktitle:gsub("#.*$", "")

                -- now: inc our link count
                link_counts[note_fn] = link_counts[note_fn] or 0
                link_counts[note_fn] = link_counts[note_fn] + 1

                -- and: inc the backlinks of the linked note
                local fexists, backlinked_file =
                    resolve_link(linktitle, file_list, subdir_list, opts)
                -- print(
                --     "note for link `"
                --         .. linktitle
                --         .. "` = "
                --         .. backlinked_file
                --         .. " (exists: "
                --         .. tostring(fexists)
                --         .. ')'
                -- )
                if fexists and (note_fn ~= backlinked_file) then
                    backlink_counts[backlinked_file] = backlink_counts[backlinked_file]
                        or 0
                    backlink_counts[backlinked_file] = backlink_counts[backlinked_file]
                        + 1
                end
            end
        end

        -- check if in comments block
        -- find all links in the note and count them
        -- add 1 (this note) as back-link to linked note
    end
    local ret = {
        link_counts = link_counts,
        backlink_counts = backlink_counts,
    }
    return ret
end

return M
