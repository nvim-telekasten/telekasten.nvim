-- lua/telekasten/picker/telescope.lua
-- Telescope backend implementation for telekasten picker abstraction

local M = {}

-- Lazy-loaded telescope modules
local telescope_loaded = false
local builtin, actions, action_state, action_set, pickers, finders, conf
local previewers, make_entry, entry_display, sorters, themes, utils

-- Load telescope modules
local function ensure_telescope()
    if telescope_loaded then
        return true
    end

    local ok, _ = pcall(require, "telescope")
    if not ok then
        error(
            "Telescope is not installed. Please install telescope.nvim or use a different picker backend."
        )
    end

    builtin = require("telescope.builtin")
    actions = require("telescope.actions")
    action_state = require("telescope.actions.state")
    action_set = require("telescope.actions.set")
    pickers = require("telescope.pickers")
    finders = require("telescope.finders")
    conf = require("telescope.config").values
    previewers = require("telescope.previewers")
    make_entry = require("telescope.make_entry")
    entry_display = require("telescope.pickers.entry_display")
    sorters = require("telescope.sorters")
    themes = require("telescope.themes")
    utils = require("telescope.utils")

    telescope_loaded = true
    return true
end

-- Backend configuration
M.config = {}

function M.setup(opts)
    ensure_telescope()
    M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

-- ============================================================================
-- Core Picker Implementations
-- ============================================================================

function M.find_files(opts)
    ensure_telescope()
    opts = opts or {}

    -- Use builtin find_files for simple cases
    if not opts.show_link_counts and not opts.preview_type then
        local telescope_opts = {
            prompt_title = opts.prompt_title or "Find Files",
            cwd = opts.cwd,
            default_text = opts.default_text,
            attach_mappings = opts.attach_mappings,
            find_command = opts.find_command,
        }

        return builtin.find_files(telescope_opts)
    end

    -- For complex cases, use custom picker with plenary scan
    local scan = require("plenary.scandir")
    local Path = require("plenary.path")

    local scan_opts = {
        search_pattern = opts.search_pattern,
        depth = opts.search_depth,
    }

    local file_list = scan.scan_dir(opts.cwd, scan_opts)

    -- Filter by extension if needed
    if opts.filter_extensions then
        local filtered = {}
        for _, file in ipairs(file_list) do
            local ext = file:match("^.+(%..+)$")
            for _, allowed_ext in ipairs(opts.filter_extensions) do
                if ext == allowed_ext then
                    table.insert(filtered, file)
                    break
                end
            end
        end
        file_list = filtered
    end

    -- Sort files
    if opts.sort == "modified" then
        table.sort(file_list, function(a, b)
            return vim.fn.getftime(a) > vim.fn.getftime(b)
        end)
    else
        table.sort(file_list, function(a, b)
            return a > b
        end)
    end

    -- Create entry maker
    local function make_file_entry(entry)
        local display_fn

        if opts.show_link_counts then
            -- Custom display with link counts
            local displayer = entry_display.create({
                separator = "",
                items = {
                    { width = 4 },
                    { width = 4 },
                    { remaining = true },
                },
            })

            display_fn = function(e)
                local display = e.value:gsub(opts.cwd .. "/", "")
                local display_with_icon, hl_group =
                    utils.transform_devicons(e.value, display, false)

                -- Get link counts (passed via opts.link_counts)
                local nlinks = opts.link_counts
                        and opts.link_counts.link_counts[e.value]
                    or 0
                local nbacks = opts.link_counts
                        and opts.link_counts.backlink_counts[e.value]
                    or 0

                return displayer({
                    {
                        "L" .. tostring(nlinks),
                        function()
                            return {
                                { { 0, 1 }, "tkTagSep" },
                                { { 1, 3 }, "tkTag" },
                            }
                        end,
                    },
                    {
                        "B" .. tostring(nbacks),
                        function()
                            return {
                                { { 0, 1 }, "tkTagSep" },
                                { { 1, 3 }, "DevIconMd" },
                            }
                        end,
                    },
                    {
                        display_with_icon,
                        function()
                            return hl_group and { { { 1, 3 }, hl_group } } or {}
                        end,
                    },
                })
            end
        else
            -- Simple display with devicons
            display_fn = function(e)
                local display = e.value:gsub(opts.cwd .. "/", "")
                local display_with_icon, hl_group =
                    utils.transform_devicons(e.value, display, false)

                if hl_group then
                    return display_with_icon, { { { 1, 3 }, hl_group } }
                else
                    return display_with_icon
                end
            end
        end

        return {
            value = entry,
            path = entry,
            ordinal = entry,
            display = display_fn,
        }
    end

    -- Select previewer
    local previewer_fn = conf.file_previewer(opts)
    if opts.preview_type == "media" then
        -- Use media previewer if configured
        previewer_fn = M.get_media_previewer(opts)
    end

    local picker = pickers.new(opts, {
        prompt_title = opts.prompt_title or "Find Files",
        finder = finders.new_table({
            results = file_list,
            entry_maker = make_file_entry,
        }),
        sorter = conf.generic_sorter(opts),
        previewer = previewer_fn,
        attach_mappings = opts.attach_mappings,
    })

    return picker:find()
end

function M.live_grep(opts)
    ensure_telescope()
    opts = opts or {}

    local telescope_opts = {
        prompt_title = opts.prompt_title or "Live Grep",
        cwd = opts.cwd,
        search_dirs = opts.search_dirs,
        default_text = opts.default_text,
        attach_mappings = opts.attach_mappings,
        find_command = opts.find_command,
    }

    return builtin.live_grep(telescope_opts)
end

function M.custom_picker(opts)
    ensure_telescope()
    opts = opts or {}

    -- Apply theme if specified
    if opts.theme then
        if opts.theme == "dropdown" then
            opts = vim.tbl_deep_extend(
                "force",
                themes.get_dropdown(opts.theme_opts or {}),
                opts
            )
        elseif opts.theme == "ivy" then
            opts = vim.tbl_deep_extend(
                "force",
                themes.get_ivy(opts.theme_opts or {}),
                opts
            )
        elseif opts.theme == "cursor" then
            opts = vim.tbl_deep_extend(
                "force",
                themes.get_cursor(opts.theme_opts or {}),
                opts
            )
        end
    end

    local picker = pickers.new(opts, {
        prompt_title = opts.prompt_title or "Select",
        finder = finders.new_table({
            results = opts.results or {},
            entry_maker = opts.entry_maker or function(entry)
                return {
                    value = entry,
                    display = tostring(entry),
                    ordinal = tostring(entry),
                }
            end,
        }),
        sorter = conf.generic_sorter(opts),
        previewer = opts.previewer,
        attach_mappings = opts.attach_mappings,
    })

    return picker:find()
end

-- ============================================================================
-- Media Previewer
-- ============================================================================

function M.get_media_previewer(opts)
    ensure_telescope()

    -- Determine preview command based on configuration
    local preview_cmd = ""
    local media_previewer = opts.media_previewer or "telescope-media-files"

    if media_previewer == "telescope-media-files" then
        local base_dir = debug.getinfo(1, "S").source:match("@?(.*/)")
        preview_cmd = base_dir
            .. "../../../telescope-media-files.nvim/scripts/vimg"
    elseif media_previewer == "catimg-previewer" then
        preview_cmd = "catimg-previewer"
    elseif media_previewer:match("^viu%-previewer") then
        preview_cmd = media_previewer
    end

    if vim.fn.executable(preview_cmd) == 0 then
        return conf.file_previewer(opts)
    end

    return previewers.new_termopen_previewer({
        get_command = function(entry)
            local preview = opts.get_preview_window()
            return {
                preview_cmd,
                entry.value,
                preview.col,
                preview.line + 1,
                preview.width,
                preview.height,
            }
        end,
    })
end

-- ============================================================================
-- Actions
-- ============================================================================

M.actions = {}

function M.actions.select_default(callback)
    return function(prompt_bufnr)
        if callback then
            callback(prompt_bufnr)
        else
            return action_set.select(prompt_bufnr, "default")
        end
    end
end

function M.actions.close(opts)
    opts = opts or {}
    return function(prompt_bufnr)
        actions.close(prompt_bufnr)

        -- Erase file if specified
        if opts.erase and opts.erase_file then
            if vim.fn.filereadable(opts.erase_file) == 1 then
                vim.fn.delete(opts.erase_file)
            end
        end
    end
end

function M.actions.yank_selection(get_text_fn)
    return function(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        local text = get_text_fn(selection)
        vim.fn.setreg('"', text)
        print("yanked " .. text)
    end
end

function M.actions.paste_selection(get_text_fn, insert_after)
    return function(prompt_bufnr)
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        local text = get_text_fn(selection)
        vim.api.nvim_put({ text }, "", true, true)

        if insert_after then
            vim.api.nvim_feedkeys("A", "m", false)
        end
    end
end

function M.actions.get_selection()
    return action_state.get_selected_entry()
end

function M.actions.get_current_line()
    return action_state.get_current_line()
end

-- ============================================================================
-- Themes
-- ============================================================================

M.themes = {}

function M.themes.dropdown(opts)
    ensure_telescope()
    return themes.get_dropdown(opts or {})
end

function M.themes.ivy(opts)
    ensure_telescope()
    return themes.get_ivy(opts or {})
end

function M.themes.cursor(opts)
    ensure_telescope()
    return themes.get_cursor(opts or {})
end

-- ============================================================================
-- Utilities
-- ============================================================================

function M.create_entry_display(spec)
    ensure_telescope()
    return entry_display.create(spec)
end

function M.supports(feature)
    local supported = {
        "media_preview",
        "custom_entry_display",
        "themes",
        "live_grep",
        "devicons",
    }

    for _, f in ipairs(supported) do
        if f == feature then
            return true
        end
    end

    return false
end

return M
