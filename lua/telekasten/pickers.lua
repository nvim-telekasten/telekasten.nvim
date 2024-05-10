local actions = require("telescope.actions")
local action_set = require("telescope.actions.set")
local action_state = require("telescope.actions.state")
local conf = require("telescope.config").values
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local config = require("telekasten.config")
local fileutils = require("telekasten.utils.files")

local vim = vim

local M = {}

-- Pick between the various configured vaults
function M.vaults(telekasten, opts)
    opts = opts or {}
    local vaults = telekasten.vaults
    local _vaults = {}
    for k, v in pairs(vaults) do
        table.insert(_vaults, { k, v })
    end
    pickers
        .new(opts, {
            prompt_title = "Vaults",
            finder = finders.new_table({
                results = _vaults,
                entry_maker = function(entry)
                    return {
                        value = entry,
                        display = entry[1],
                        ordinal = entry[1],
                    }
                end,
            }),
            sorter = conf.generic_sorter(opts),
            attach_mappings = function(prompt_bufnr, map)
                actions.select_default:replace(function()
                    actions.close(prompt_bufnr)
                    local selection = action_state.get_selected_entry()
                    -- print(vim.inspect(selection))
                    telekasten.chdir(selection.value[2])
                end)
                return true
            end,
        })
        :find()
end

-- note picker actions
-- Move to utils/pickers.lua? Make sure to bring table entry definitions from below
M.picker_actions = {}

-- N/A -> N/A
-- No return. If user config auto sets filetype or syntax, actually set them
-- Keep with picker_actions definition
M.picker_actions.post_open = function()
    if config.options.auto_set_filetype then
        vim.cmd("set ft=telekasten")
    end
    if config.options.auto_set_syntax then
        vim.cmd("set syntax=telekasten")
    end
end

-- int -> nil? action_set.select returns result of action_set.edit, but edit doesn't return a value
-- Keep with picker_actions definition
M.picker_actions.select_default = function(prompt_bufnr)
    local ret = action_set.select(prompt_bufnr, "default")
    M.picker_actions.post_open()
    return ret
end

-- table -> function
-- Returns a configured function mapped to a key while using the picker
-- Keep with picker_actions definition
function M.picker_actions.close(opts)
    opts = opts or {}
    return function(prompt_bufnr)
        actions.close(prompt_bufnr)
        if opts.erase then
            if fileutils.file_exists(opts.erase_file) then
                vim.fn.delete(opts.erase_file)
            end
        end
    end
end

-- table -> function
-- Returns a configured function that gets mapped to a key while using the picker in FindAllTags
function M.picker_actions.paste_tag(opts)
    return function(prompt_bufnr)
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        vim.api.nvim_put({ selection.value.tag }, "", true, true)
        if opts.insert_after_inserting or opts.i then
            vim.api.nvim_feedkeys("A", "m", false)
        end
    end
end

-- table -> function
-- Returns a configured function that gets mapped to a key while using the picker in FindAllTags
function M.picker_actions.yank_tag(opts)
    return function(prompt_bufnr)
        opts = opts or {}
        if opts.close_after_yanking then
            actions.close(prompt_bufnr)
        end
        local selection = action_state.get_selected_entry()
        vim.fn.setreg('"', selection.value.tag)
        print("yanked " .. selection.value.tag)
    end
end

-- table -> function
-- Returns a configured function that gets mapped to a key while using the picker
function M.picker_actions.paste_link(opts)
    opts = opts or {}
    opts.subdirs_in_links = opts.subdirs_in_links
        or config.options.subdirs_in_links
    return function(prompt_bufnr)
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        local pinfo = fileutils.Pinfo:new({
            filepath = selection.filename or selection.value,
            opts,
        })
        local title = "[[" .. pinfo.title .. "]]"
        vim.api.nvim_put({ title }, "", true, true)
        if opts.insert_after_inserting or opts.i then
            vim.api.nvim_feedkeys("A", "m", false)
        end
    end
end

-- table -> function
-- Returns a configured function that gets mapped to a key while using the picker
function M.picker_actions.yank_link(opts)
    return function(prompt_bufnr)
        opts = opts or {}
        opts.subdirs_in_links = opts.subdirs_in_links
            or config.options.subdirs_in_links
        if opts.close_after_yanking then
            actions.close(prompt_bufnr)
        end
        local selection = action_state.get_selected_entry()
        local pinfo = fileutils.Pinfo:new({
            filepath = selection.filename or selection.value,
            opts,
        })
        local title = "[[" .. pinfo.title .. "]]"
        vim.fn.setreg('"', title)
        print("yanked " .. title)
    end
end

-- table -> function
-- Returns a configured function that gets mapped to a key while using the picker for images
function M.picker_actions.paste_img_link(opts)
    return function(prompt_bufnr)
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        local fn = selection.value
        fn = make_relative_path(vim.fn.expand("%:p"), fn, "/")
        local imglink = "![](" .. fn .. ")"
        vim.api.nvim_put({ imglink }, "", true, true)
        if opts.insert_after_inserting or opts.i then
            vim.api.nvim_feedkeys("A", "m", false)
        end
    end
end

-- table -> function
-- Returns a configured function that gets mapped to a key while using the picker for images
function M.picker_actions.yank_img_link(opts)
    return function(prompt_bufnr)
        opts = opts or {}
        if opts.close_after_yanking then
            actions.close(prompt_bufnr)
        end
        local selection = action_state.get_selected_entry()
        local fn = selection.value
        fn = make_relative_path(vim.fn.expand("%:p"), fn, "/")
        local imglink = "![](" .. fn .. ")"
        vim.fn.setreg('"', imglink)
        print("yanked " .. imglink)
    end
end

-- table -> function
-- Keep with other picker_actions
function M.picker_actions.create_new(opts)
    opts = opts or {}
    opts.subdirs_in_links = opts.subdirs_in_links
        or config.options.subdirs_in_links
    return function(prompt_bufnr)
        local prompt =
            action_state.get_current_picker(prompt_bufnr).sorter._discard_state.prompt
        actions.close(prompt_bufnr)
        on_create(opts, prompt)
        -- local selection = action_state.get_selected_entry()
    end
end

return M
