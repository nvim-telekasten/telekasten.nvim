local templates = require("telekasten.templates")

local M = {}

local vim = vim

---@class PeriodicKindSpec
---@field name string
---@field enabled boolean
---@field root string
---@field folder_path string
---@field filename string
---@field template_file string
---@field create_if_missing boolean

---@class PeriodicSpec
---@field root string
---@field extension string
---@field kinds table<string, PeriodicKindSpec>

M.periodic_kinds = { "yearly", "quarterly", "monthly", "weekly", "daily" }

--- detection_patterns
-- A dynamically filled table containing detection patterns which determine
-- if a given pattern is a periodic note or not.
-- Each entry consists of three fields:
-- pattern (string): The full string regex pattern for the filename
-- kind (string): Which kind of periodic note it classifies as
-- fields (table): Which values to update in the file's date info table,
-- based on detected pattern order
M.detection_patterns = {}

-- A Table for specific token detection
-- NOTE: Different from detection_patterns! Only for specific template tokens.
local token_meta = {
    year = {
        pattern = "%d%d%d%d",
        fields = { "year" }
    },
    month = {
        pattern = "%d%d",
        fields = { "month" },
    },
    day = {
        pattern = "%d%d",
        fields = { "day" },
    },
    week = {
        pattern = "%d%d",
        fields = { "week" },
    },
    quarter = {
        pattern = "[1-4]",
        fields = { "quarter" },
    },
    quarter_yq = {
        pattern = "%d%d%d%d%-Q[1-4]",
        fields = { "year", "quarter"},
    },
    month_ym = {
        pattern = "%d%d%d%d%-%d%d",
        fields = { "year", "day" },
    },
    isoweek = {
        pattern = "%d%d%d%d%-W%d%d",
        fields = { "year", "week" },
    },
    date = {
        pattern = "%d%d%d%d%-%d%d%-%d%d",
        fields = { "year", "month", "day" },
    },
}

local function escape_lua(text)
    return (text:gsub("([%%%^%$%(%)%.%[%]%+%-%?])", "%%%1"))
end

---@param periodic PeriodicConfig
---@return table[] detection_patterns
local function build_detection_patterns(periodic)
    local patterns = {}

    if not periodic or not periodic.kinds then
        return patterns
    end

    for kind, kcfg in pairs(periodic.kinds) do
        if kcfg ~= false then
            local tmpl = kcfg.filename or ""
            if tmpl ~= "" then
                local pat = "^"
                local fields = {}

                local i = 1
                while i <= #tmpl do
                    local s, e, token = tmpl:find("{([%w_]+)}", i)
                    if s then
                        if s > i then
                            local literal = tmpl:sub(i, s-1)
                            pat = pat .. escape_lua(literal)
                        end

                        local meta = token_meta[token]
                        if meta and meta.pattern then
                            pat = pat .. meta.pattern
                            for _, f in ipairs(meta.fields) do
                                table.insert(fields, f)
                            end
                        else
                            pat = pat .. ".*"
                        end

                        i = e + 1
                    else
                        local literal = tmpl:sub(i)
                        pat = pat .. escape_lua(literal)
                        break
                    end
                end

                pat = pat .. "$"

                table.insert(patterns, {
                    pattern = pat,
                    kind = kind,
                    fields = fields,
                })
            end
        end
    end

    return patterns
end

---@param periodic PeriodicConfig|nil
---@return PeriodicConfig
function M.normalize_periodic(periodic)
    periodic = periodic or {}
    periodic.root = periodic.root or ""
    periodic.kinds = periodic.kinds or {}

    for _, kind in ipairs(M.periodic_kinds) do
        local kcfg = periodic.kinds[kind] or {}

        if kcfg.enabled == nil then
            kcfg.enabled = true
        end
        if kcfg.root == nil then
            kcfg.root = ""
        end
        kcfg.folder_path = kcfg.folder_path or ""
        kcfg.filename = kcfg.filename or ""
        kcfg.template_file = kcfg.template_file or ""
        if kcfg.create_if_missing == nil then
            kcfg.create_if_missing = true
        end

        periodic.kinds[kind] = kcfg
    end

    M.detection_patterns = build_detection_patterns(periodic)

    return periodic
end

local function root_for_kind(periodic, kind)
    local kcfg = periodic.kinds[kind]
    if not kcfg or kcfg.enabled == false then
        return nil
    end

    if kcfg.root ~= "" then
        return kcfg.root
    end
    return periodic.root
end

--- Build full path for a periodic note.
---@param periodic PeriodicConfig
---@param kind PeriodicKind
---@param dinfo table  -- dateutils.calculate_dates result
---@param extension string
---@return string|nil filepath
---@return string|nil title
---@return string|nil root_dir
---@return string|nil sub_dir
function M.build_path(periodic, kind, dinfo, extension)
    local kcfg = periodic.kinds[kind]
    if not kcfg or kcfg.enabled == false then
        return nil, nil, nil, nil
    end

    local ctx = dinfo or {}
    local root_dir = root_for_kind(periodic, kind)
    if not root_dir or root_dir == "" then
        return nil, nil, nil, nil
    end

    local rel_folder = templates.expand_template(kcfg.folder_path, ctx)
    local title = templates.expand_template(kcfg.filename, ctx)

    local sub_dir = rel_folder ~= "" and rel_folder or ""
    local folder = root_dir
    if rel_folder ~= "" then
        folder = root_dir .. "/" .. rel_folder
    end

    local path = folder .. "/" .. title .. (extension or "")
    return path, title, root_dir, sub_dir
end

--- Top-level search root for a kind (no date folders).
---@param periodic PeriodicConfig
---@param kind PeriodicKind
---@return string|nil
function M.search_root(periodic, kind)
    return root_for_kind(periodic, kind)
end

--- Build a Lua pattern that matches the filename (without folders).
---@param periodic PeriodicConfig
---@param kind PeriodicKind
---@param extension string
---@return string|nil
function M.filename_pattern(periodic, kind, extension)
    local kcfg = periodic.kinds[kind]
    if not kcfg or kcfg.enabled == false then
        return nil
    end

    local pattern = kcfg.filename
    if pattern == "" then
        return nil
    end

    -- escape lua pattern magic
    pattern = pattern:gsub("[^{]+", function(lit)
        return escape_lua(lit)
    end)

    pattern = pattern:gsub("{([%w_]+)}", function(key)
        return token_meta[key] or ".*"
    end)

    extension = extension or ""
    if extension ~= "" then
        pattern = pattern .. vim.pesc(extension) .. "$"
    end

    return pattern
end

return M
