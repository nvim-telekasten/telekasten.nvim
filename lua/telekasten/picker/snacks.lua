-- lua/telekasten/picker/snacks.lua
-- Snacks.nvim backend implementation for telekasten picker abstraction

local M = {}

-- Lazy-loaded snacks module
local snacks_loaded = false
local snacks

-- Load snacks
local function ensure_snacks()
    if snacks_loaded then
        return true
    end

    local ok, s = pcall(require, "snacks")
    if not ok then
        error(
            "snacks.nvim is not installed. Please install snacks.nvim or use a different picker backend."
        )
    end

    snacks = s
    snacks_loaded = true
    return true
end

-- Backend configuration
M.config = {}

function M.setup(opts)
    ensure_snacks()
    M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

-- ============================================================================
-- Helper Functions
-- ============================================================================

-- Store current selection for compatibility
M._current_selection = nil
M._current_line = nil

-- Convert telekasten attach_mappings to snacks format
local function convert_mappings(attach_mappings)
    if not attach_mappings then
        return nil
    end

    local actions_obj = {}
    local map_fn = function(mode, key, action_fn)
        actions_obj[key] = action_fn
    end

    -- Call attach_mappings with mock
    attach_mappings(actions_obj, map_fn)

    -- Convert to snacks actions format
    local snacks_actions = {}
    for key, action_fn in pairs(actions_obj) do
        snacks_actions[key] = function(picker_obj)
            -- Store selection
            M._current_selection = picker_obj:current()
            M._current_line = picker_obj:current()

            -- Create mock prompt_bufnr
            local mock_bufnr = vim.api.nvim_get_current_buf()

            -- Call the action
            action_fn(mock_bufnr)
        end
    end

    return snacks_actions
end

-- Format entry for display
local function format_entry(entry, opts)
    if type(entry) == "string" then
        return entry
    end

    if entry.display then
        if type(entry.display) == "function" then
            local display_result = entry.display(entry)
            if type(display_result) == "string" then
                return display_result
            elseif type(display_result) == "table" then
                return display_result[1] or tostring(entry)
            end
        else
            return entry.display
        end
    end

    return entry.value or tostring(entry)
end

-- ============================================================================
-- Core Picker Implementations
-- ============================================================================

function M.find_files(opts)
    ensure_snacks()
    opts = opts or {}

    -- For simple cases, use snacks' built-in files
    if not opts.show_link_counts and not opts.search_pattern then
        local snacks_opts = {
            prompt = opts.prompt_title or "Find Files",
            cwd = opts.cwd,
            input = opts.default_text,
        }

        -- Convert actions
        if opts.attach_mappings then
            snacks_opts.actions = convert_mappings(opts.attach_mappings)
        end

        return snacks.picker.pick("files", snacks_opts)
    end

    -- For complex cases, scan and format manually
    local scan = require("plenary.scandir")

    local scan_opts = {
        search_pattern = opts.search_pattern,
        depth = opts.search_depth,
    }

    local file_list = scan.scan_dir(opts.cwd, scan_opts)

    -- Filter by extension
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

    -- Format entries with link counts if needed
    local formatted_entries = {}
    for _, file in ipairs(file_list) do
        local display = file:gsub(opts.cwd .. "/", "")

        if opts.show_link_counts and opts.link_counts then
            local nlinks = opts.link_counts.link_counts[file] or 0
            local nbacks = opts.link_counts.backlink_counts[file] or 0
            display = string.format("L%-3d B%-3d %s", nlinks, nbacks, display)
        end

        table.insert(formatted_entries, {
            text = display,
            file = file,
        })
    end

    local snacks_opts = {
        prompt = opts.prompt_title or "Find Files",
        format = "file",
    }

    -- Convert actions
    if opts.attach_mappings then
        snacks_opts.actions = convert_mappings(opts.attach_mappings)
    end

    return snacks.picker.pick(formatted_entries, snacks_opts)
end

function M.live_grep(opts)
    ensure_snacks()
    opts = opts or {}

    local snacks_opts = {
        prompt = opts.prompt_title or "Live Grep",
        cwd = opts.cwd,
        input = opts.default_text or "",
    }

    -- Convert actions
    if opts.attach_mappings then
        snacks_opts.actions = convert_mappings(opts.attach_mappings)
    end

    return snacks.picker.pick("grep", snacks_opts)
end

function M.custom_picker(opts)
    ensure_snacks()
    opts = opts or {}

    local results = opts.results or {}

    -- Format entries using entry_maker if provided
    local formatted_entries = {}
    if opts.entry_maker then
        for _, item in ipairs(results) do
            local entry = opts.entry_maker(item)
            local display = format_entry(entry, opts)
            table.insert(formatted_entries, {
                text = display,
                value = entry.value,
                ordinal = entry.ordinal or display,
            })
        end
    else
        for _, item in ipairs(results) do
            table.insert(formatted_entries, {
                text = tostring(item),
                value = item,
            })
        end
    end

    local snacks_opts = {
        prompt = opts.prompt_title or "Select",
    }

    -- Apply theme-like layout
    if opts.theme == "dropdown" then
        snacks_opts.layout = {
            height = 0.4,
            width = 0.6,
        }
    elseif opts.theme == "ivy" then
        snacks_opts.layout = {
            height = 0.4,
            position = "bottom",
        }
    elseif opts.theme == "cursor" then
        snacks_opts.layout = {
            height = 0.3,
            width = 0.3,
            position = "center",
        }
    end

    -- Convert actions
    if opts.attach_mappings then
        snacks_opts.actions = convert_mappings(opts.attach_mappings)
    end

    return snacks.picker.pick(formatted_entries, snacks_opts)
end

-- ============================================================================
-- Actions
-- ============================================================================

M.actions = {}

function M.actions.select_default(callback)
    return function(picker_obj)
        if callback then
            -- Store selection
            M._current_selection = picker_obj:current()

            -- Create mock prompt_bufnr
            local mock_bufnr = vim.api.nvim_get_current_buf()
            callback(mock_bufnr)
        else
            -- Default behavior
            local item = picker_obj:current()
            if item and item.file then
                vim.cmd("edit " .. item.file)
            elseif item and item.text then
                vim.cmd("edit " .. item.text)
            end
        end
    end
end

function M.actions.close(opts)
    opts = opts or {}
    return function(picker_obj)
        picker_obj:close()

        -- Erase file if specified
        if opts.erase and opts.erase_file then
            if vim.fn.filereadable(opts.erase_file) == 1 then
                vim.fn.delete(opts.erase_file)
            end
        end
    end
end

function M.actions.yank_selection(get_text_fn)
    return function(picker_obj)
        local item = picker_obj:current()
        if not item then
            return
        end

        M._current_selection = item

        -- Create mock entry
        local mock_entry = {
            value = item.file or item.text or item.value,
            filename = item.file or item.text,
        }

        local text = get_text_fn(mock_entry)
        vim.fn.setreg('"', text)
        print("yanked " .. text)
    end
end

function M.actions.paste_selection(get_text_fn, insert_after)
    return function(picker_obj)
        local item = picker_obj:current()
        if not item then
            return
        end

        picker_obj:close()

        M._current_selection = item

        -- Create mock entry
        local mock_entry = {
            value = item.file or item.text or item.value,
            filename = item.file or item.text,
        }

        local text = get_text_fn(mock_entry)
        vim.api.nvim_put({ text }, "", true, true)

        if insert_after then
            vim.api.nvim_feedkeys("A", "m", false)
        end
    end
end

function M.actions.get_selection()
    -- Return mock entry with stored selection
    if M._current_selection then
        return {
            value = M._current_selection.file
                or M._current_selection.text
                or M._current_selection.value,
            filename = M._current_selection.file or M._current_selection.text,
        }
    end
    return nil
end

function M.actions.get_current_line()
    return M._current_line or ""
end

-- ============================================================================
-- Themes
-- ============================================================================

M.themes = {}

function M.themes.dropdown(opts)
    opts = opts or {}
    return vim.tbl_deep_extend("force", {
        layout = {
            height = 0.4,
            width = 0.6,
            position = "center",
        },
    }, opts)
end

function M.themes.ivy(opts)
    opts = opts or {}
    return vim.tbl_deep_extend("force", {
        layout = {
            height = 0.4,
            position = "bottom",
        },
    }, opts)
end

function M.themes.cursor(opts)
    opts = opts or {}
    return vim.tbl_deep_extend("force", {
        layout = {
            height = 0.3,
            width = 0.3,
            position = "center",
        },
    }, opts)
end

-- ============================================================================
-- Utilities
-- ============================================================================

function M.create_entry_display(spec)
    -- Snacks doesn't have telescope's entry_display
    -- Return a simple formatter function
    return function(entry)
        if type(entry) == "table" and entry.display then
            if type(entry.display) == "function" then
                return entry.display(entry)
            else
                return entry.display
            end
        end
        return tostring(entry.value or entry)
    end
end

function M.supports(feature)
    local supported = {
        "live_grep",
        "themes",
    }

    for _, f in ipairs(supported) do
        if f == feature then
            return true
        end
    end

    return false
end

return M
