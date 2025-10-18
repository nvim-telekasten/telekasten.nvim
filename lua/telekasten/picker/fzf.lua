-- lua/telekasten/picker/fzf.lua
-- FZF-Lua backend implementation for telekasten picker abstraction

local M = {}

-- Lazy-loaded fzf-lua module
local fzf_loaded = false
local fzf_lua

-- Load fzf-lua
local function ensure_fzf()
    if fzf_loaded then
        return true
    end

    local ok, fzf = pcall(require, "fzf-lua")
    if not ok then
        error(
            "fzf-lua is not installed. Please install fzf-lua or use a different picker backend."
        )
    end

    fzf_lua = fzf
    fzf_loaded = true
    return true
end

-- Backend configuration
M.config = {
    winopts = {
        height = 0.85,
        width = 0.80,
        row = 0.35,
        col = 0.50,
        border = "rounded",
    },
    previewers = {
        builtin = {
            extensions = {
                ["png"] = { "chafa" },
                ["jpg"] = { "chafa" },
                ["jpeg"] = { "chafa" },
                ["gif"] = { "chafa" },
                ["webp"] = { "chafa" },
            },
        },
    },
}

function M.setup(opts)
    ensure_fzf()
    M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

-- ============================================================================
-- Helper Functions
-- ============================================================================

-- Convert attach_mappings to fzf-lua actions
local function convert_mappings(attach_mappings)
    if not attach_mappings then
        return nil
    end

    local actions_obj = {}
    local map_fn = function(mode, key, action_fn)
        -- Store action for this key
        actions_obj[key] = action_fn
    end

    -- Call the attach_mappings with our mock actions and map
    attach_mappings(actions_obj, map_fn)

    -- Convert to fzf-lua format
    local fzf_actions = {}
    for key, action_fn in pairs(actions_obj) do
        fzf_actions[key] = function(selected, opts_inner)
            -- Create a mock prompt_bufnr for compatibility
            local mock_bufnr = vim.api.nvim_get_current_buf()

            -- Store selected for get_selection
            M._current_selection = selected and selected[1]

            -- Call the action
            action_fn(mock_bufnr)
        end
    end

    return fzf_actions
end

-- Format entry for display
local function format_entry(entry, opts)
    if type(entry) == "string" then
        return entry
    end

    if entry.display then
        if type(entry.display) == "function" then
            return entry.display(entry)
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
    ensure_fzf()
    opts = opts or {}

    -- For simple cases, use fzf-lua's built-in files
    if not opts.show_link_counts and not opts.search_pattern then
        local fzf_opts = {
            prompt = (opts.prompt_title or "Find Files") .. "> ",
            cwd = opts.cwd,
            query = opts.default_text,
            winopts = M.config.winopts,
            actions = convert_mappings(opts.attach_mappings),
        }

        return fzf_lua.files(fzf_opts)
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

        table.insert(formatted_entries, display)
    end

    local fzf_opts = {
        prompt = (opts.prompt_title or "Find Files") .. "> ",
        fzf_opts = {
            ["--no-sort"] = "",
        },
        winopts = M.config.winopts,
        actions = convert_mappings(opts.attach_mappings),
    }

    -- Handle preview
    if opts.preview_type == "media" then
        fzf_opts.previewer = "builtin"
    end

    return fzf_lua.fzf_exec(formatted_entries, fzf_opts)
end

function M.live_grep(opts)
    ensure_fzf()
    opts = opts or {}

    local fzf_opts = {
        prompt = (opts.prompt_title or "Live Grep") .. "> ",
        cwd = opts.cwd,
        search = opts.default_text or "",
        winopts = M.config.winopts,
        actions = convert_mappings(opts.attach_mappings),
    }

    -- Handle search_dirs
    if opts.search_dirs and #opts.search_dirs > 0 then
        fzf_opts.cwd = opts.search_dirs[1]
    end

    return fzf_lua.live_grep(fzf_opts)
end

function M.custom_picker(opts)
    ensure_fzf()
    opts = opts or {}

    local results = opts.results or {}

    -- Format entries using entry_maker if provided
    local formatted_entries = {}
    if opts.entry_maker then
        for _, item in ipairs(results) do
            local entry = opts.entry_maker(item)
            table.insert(formatted_entries, format_entry(entry, opts))
        end
    else
        for _, item in ipairs(results) do
            table.insert(formatted_entries, tostring(item))
        end
    end

    local fzf_opts = {
        prompt = (opts.prompt_title or "Select") .. "> ",
        winopts = vim.tbl_deep_extend("force", M.config.winopts, {}),
        actions = convert_mappings(opts.attach_mappings),
        fzf_opts = {
            ["--no-sort"] = "",
        },
    }

    -- Apply theme
    if opts.theme == "dropdown" then
        fzf_opts.winopts.height = 0.4
        fzf_opts.winopts.width = 0.6
        fzf_opts.winopts.row = 0.4
    elseif opts.theme == "ivy" then
        fzf_opts.winopts.height = 0.4
        fzf_opts.winopts.row = 1.0
        fzf_opts.winopts.border = "none"
    elseif opts.theme == "cursor" then
        fzf_opts.winopts.height = 0.3
        fzf_opts.winopts.width = 0.3
        fzf_opts.winopts.row = 0.5
        fzf_opts.winopts.col = 0.5
    end

    return fzf_lua.fzf_exec(formatted_entries, fzf_opts)
end

-- ============================================================================
-- Actions
-- ============================================================================

M.actions = {}

-- Store current selection for get_selection
M._current_selection = nil
M._current_line = nil

function M.actions.select_default(callback)
    return function(selected, fzf_opts)
        if callback then
            -- Store selection
            M._current_selection = selected and selected[1]

            -- Create mock prompt_bufnr
            local mock_bufnr = vim.api.nvim_get_current_buf()
            callback(mock_bufnr)
        else
            -- Default behavior: open file
            if selected and selected[1] then
                vim.cmd("edit " .. selected[1])
            end
        end
    end
end

function M.actions.close(opts)
    opts = opts or {}
    return function(selected, fzf_opts)
        -- fzf-lua handles closing automatically

        -- Erase file if specified
        if opts.erase and opts.erase_file then
            if vim.fn.filereadable(opts.erase_file) == 1 then
                vim.fn.delete(opts.erase_file)
            end
        end
    end
end

function M.actions.yank_selection(get_text_fn)
    return function(selected, fzf_opts)
        if not selected or not selected[1] then
            return
        end

        M._current_selection = selected[1]

        -- Create a mock entry
        local mock_entry = {
            value = selected[1],
            filename = selected[1],
        }

        local text = get_text_fn(mock_entry)
        vim.fn.setreg('"', text)
        print("yanked " .. text)
    end
end

function M.actions.paste_selection(get_text_fn, insert_after)
    return function(selected, fzf_opts)
        if not selected or not selected[1] then
            return
        end

        M._current_selection = selected[1]

        -- Create a mock entry
        local mock_entry = {
            value = selected[1],
            filename = selected[1],
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
            value = M._current_selection,
            filename = M._current_selection,
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
        winopts = {
            height = 0.4,
            width = 0.6,
            row = 0.4,
            col = 0.5,
        },
    }, opts)
end

function M.themes.ivy(opts)
    opts = opts or {}
    return vim.tbl_deep_extend("force", {
        winopts = {
            height = 0.4,
            row = 1.0,
            border = "none",
        },
    }, opts)
end

function M.themes.cursor(opts)
    opts = opts or {}
    return vim.tbl_deep_extend("force", {
        winopts = {
            height = 0.3,
            width = 0.3,
            row = 0.5,
            col = 0.5,
        },
    }, opts)
end

-- ============================================================================
-- Utilities
-- ============================================================================

function M.create_entry_display(spec)
    -- FZF-lua doesn't have telescope's entry_display
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

    -- Partial support
    if feature == "media_preview" then
        return vim.fn.executable("chafa") == 1
    end

    return false
end

return M
