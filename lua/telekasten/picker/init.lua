-- lua/telekasten/picker/init.lua
-- Abstraction layer for multiple picker backends (telescope, fzf-lua, snacks)

local M = {}

-- Current backend configuration
M.backend = nil
M.impl = nil

-- Available backends
local BACKENDS = {
    telescope = "telekasten.picker.telescope",
    fzf = "telekasten.picker.fzf",
    snacks = "telekasten.picker.snacks",
}

-- Setup the picker backend
-- @param backend string: "telescope", "fzf", or "snacks"
-- @param opts table: backend-specific configuration options
function M.setup(backend, opts)
    backend = backend or "telescope"
    opts = opts or {}

    if not BACKENDS[backend] then
        error(
            string.format(
                "Unknown picker backend: %s. Available: telescope, fzf, snacks",
                backend
            )
        )
    end

    local ok, impl = pcall(require, BACKENDS[backend])
    if not ok then
        error(
            string.format(
                "Failed to load picker backend '%s': %s",
                backend,
                impl
            )
        )
    end

    M.backend = backend
    M.impl = impl

    if M.impl.setup then
        M.impl.setup(opts)
    end

    return M
end

-- Get the current backend name
function M.get_backend()
    return M.backend
end

-- Ensure backend is initialized
local function ensure_backend()
    if not M.impl then
        M.setup("telescope") -- default fallback
    end
end

-- ============================================================================
-- Core Picker API - All backends must implement these
-- ============================================================================

-- Find files with sorting and filtering
-- @param opts table: picker options
--   - prompt_title: string
--   - cwd: string
--   - default_text: string
--   - search_pattern: string (regex pattern)
--   - search_depth: number
--   - filter_extensions: table of strings
--   - preview_type: "text" | "media"
--   - sort: "filename" | "modified"
--   - show_link_counts: boolean
--   - attach_mappings: function(actions, map)
function M.find_files(opts)
    ensure_backend()
    return M.impl.find_files(opts)
end

-- Live grep with custom patterns
-- @param opts table: picker options
--   - prompt_title: string
--   - cwd: string
--   - default_text: string
--   - search_dirs: table of strings
--   - attach_mappings: function(actions, map)
function M.live_grep(opts)
    ensure_backend()
    return M.impl.live_grep(opts)
end

-- Custom picker with arbitrary results
-- @param opts table: picker options
--   - prompt_title: string
--   - results: table (list of items)
--   - entry_maker: function(entry) -> { value, display, ordinal }
--   - attach_mappings: function(actions, map)
--   - theme: "dropdown" | "ivy" | "cursor" | nil
function M.custom_picker(opts)
    ensure_backend()
    return M.impl.custom_picker(opts)
end

-- ============================================================================
-- Action Abstraction - Common actions across all pickers
-- ============================================================================

M.actions = {}

-- Action builder functions that return backend-specific actions
-- These should be called within attach_mappings

function M.actions.select_default(callback)
    ensure_backend()
    return M.impl.actions.select_default(callback)
end

function M.actions.close(opts)
    ensure_backend()
    return M.impl.actions.close(opts)
end

function M.actions.yank_selection(get_text_fn)
    ensure_backend()
    return M.impl.actions.yank_selection(get_text_fn)
end

function M.actions.paste_selection(get_text_fn, insert_after)
    ensure_backend()
    return M.impl.actions.paste_selection(get_text_fn, insert_after)
end

-- Get the selected entry/line from picker state
function M.actions.get_selection()
    ensure_backend()
    return M.impl.actions.get_selection()
end

-- Get current line text from prompt
function M.actions.get_current_line()
    ensure_backend()
    return M.impl.actions.get_current_line()
end

-- ============================================================================
-- Theme/Layout Abstraction
-- ============================================================================

M.themes = {}

function M.themes.dropdown(opts)
    ensure_backend()
    if M.impl.themes and M.impl.themes.dropdown then
        return M.impl.themes.dropdown(opts)
    end
    return opts or {}
end

function M.themes.ivy(opts)
    ensure_backend()
    if M.impl.themes and M.impl.themes.ivy then
        return M.impl.themes.ivy(opts)
    end
    return opts or {}
end

function M.themes.cursor(opts)
    ensure_backend()
    if M.impl.themes and M.impl.themes.cursor then
        return M.impl.themes.cursor(opts)
    end
    return opts or {}
end

-- ============================================================================
-- Utility Functions
-- ============================================================================

-- Create entry display formatter (for link counts, icons, etc)
-- @param spec table: display specification
--   - separator: string
--   - items: table of { width = number, remaining = boolean }
-- @return function: displayer function
function M.create_entry_display(spec)
    ensure_backend()
    if M.impl.create_entry_display then
        return M.impl.create_entry_display(spec)
    end
    -- Fallback: simple formatter
    return function(entry)
        return entry.display or entry.value or tostring(entry)
    end
end

-- Check if backend supports feature
-- @param feature string: feature name
-- @return boolean
function M.supports(feature)
    ensure_backend()
    if M.impl.supports then
        return M.impl.supports(feature)
    end
    return false
end

-- ============================================================================
-- Backend-Agnostic Helper Functions
-- ============================================================================

-- Sort file list by filename or modification time
-- @param files table: list of file paths
-- @param sort_by string: "filename" | "modified"
-- @return table: sorted file list
function M.sort_files(files, sort_by)
    if sort_by == "modified" then
        table.sort(files, function(a, b)
            return vim.fn.getftime(a) > vim.fn.getftime(b)
        end)
    else
        table.sort(files, function(a, b)
            return a > b
        end)
    end
    return files
end

-- Filter files by extension
-- @param files table: list of file paths
-- @param extensions table: list of extensions (e.g., {".md", ".txt"})
-- @return table: filtered file list
function M.filter_by_extension(files, extensions)
    if not extensions or #extensions == 0 then
        return files
    end

    local ext_map = {}
    for _, ext in ipairs(extensions) do
        ext_map[ext] = true
    end

    local filtered = {}
    for _, file in ipairs(files) do
        local ext = file:match("^.+(%..+)$")
        if ext and ext_map[ext] then
            table.insert(filtered, file)
        end
    end

    return filtered
end

-- Create relative path from absolute paths
-- @param from string: source path
-- @param to string: target path
-- @return string: relative path
function M.make_relative_path(from, to)
    local sep = "/"

    local from_parts = {}
    for part in from:gmatch("([^" .. sep .. "]+)") do
        table.insert(from_parts, part)
    end

    local to_parts = {}
    for part in to:gmatch("([^" .. sep .. "]+)") do
        table.insert(to_parts, part)
    end

    local i = 1
    while i < #to_parts and i < #from_parts do
        if to_parts[i] ~= from_parts[i] then
            break
        end
        i = i + 1
    end

    local relative = ""
    while i <= #to_parts or i <= #from_parts do
        if i <= #to_parts then
            if relative == "" then
                relative = to_parts[i]
            else
                relative = relative .. sep .. to_parts[i]
            end
        end
        if i <= #from_parts - 1 then
            relative = ".." .. sep .. relative
        end
        i = i + 1
    end

    return relative
end

-- ============================================================================
-- Validation
-- ============================================================================

-- Validate that a backend implementation has required functions
function M.validate_backend(impl)
    local required = {
        "find_files",
        "live_grep",
        "custom_picker",
        "actions",
    }

    for _, fn_name in ipairs(required) do
        if not impl[fn_name] then
            return false,
                string.format("Backend missing required function: %s", fn_name)
        end
    end

    local required_actions = {
        "select_default",
        "close",
        "yank_selection",
        "paste_selection",
        "get_selection",
        "get_current_line",
    }

    for _, action_name in ipairs(required_actions) do
        if not impl.actions[action_name] then
            return false,
                string.format(
                    "Backend missing required action: actions.%s",
                    action_name
                )
        end
    end

    return true
end

return M
