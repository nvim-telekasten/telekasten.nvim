
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

local kinds_order = { "yearly", "quarterly", "monthly", "weekly", "daily" }

--- detection_patterns
-- A Table containing detection patterns which determine
-- if a given pattern is a periodic note or not.
-- Each entry consists of three fields:
    -- pattern (string): The full string regex pattern for the filename
    -- kind (string): Which kind of periodic note it classifies as
    -- value_table (table): Which values to update in the file's date info table,
        -- based on detected pattern order
-- For anything regarding weeklies or quarterlies, be sure to include 
-- "week" or "quarter", respectively.
M.detection_patterns = {
    -- DAILY PATTERNS
    -- Pattern: YYYY-MM-DD
    {"^(%d%d%d%d)-(%d%d)-(%d%d)$", "daily", {"year", "month", "day"}},
    -- Pattern: YYYY.MM.DD
    {"^(%d%d%d%d).(%d%d).(%d%d)$", "daily", {"year", "month", "day"}},
    -- Pattern : YYYY MM DD
    {"^(%d%d%d%d)%s+(%d%d)%s+(%d%d)$", "daily", {"year", "month", "day"}},
    -- Pattern: DD-MM-YYYY
    {"^(%d%d)-(%d%d)-(%d%d%d%d)$", "daily", {"day", "month", "year"}}, -- IMPORTANT: Ask people to NOT use this kind of format for month/day/year
    -- Pattern: DD.MM.YYYY
    {"^(%d%d).(%d%d).(%d%d%d%d)$", "daily", {"day", "month", "year"}}, -- IMPORTANT: Ask people to NOT use this kind of format for month/day/year
    -- Pattern: DD MM YYYY
    {"^(%d%d)%s+(%d%d)%s+(%d%d%d%d)$", "daily", {"day", "month", "year"}}, -- IMPORTANT: Ask people to NOT use this kind of format for month/day/year

    -- WEEKLY PATTERNS
    -- Pattern: YYYY-[W]W
    {"^(%d%d%d%d)-W(%d%d)$", "weekly", {"year", "week"}},
    -- Pattern: YYYY.[W]W
    {"^(%d%d%d%d).W(%d%d)$", "weekly", {"year", "week"}},
    -- Pattern: YYYY [W]W
    {"^(%d%d%d%d)%s+W(%d%d)$", "weekly", {"year", "week"}},
    -- Pattern: [W]W-YYYY
    {"^W(%d%d)-(%d%d%d%d)$", "weekly", {"week", "year"}},
    -- Pattern: [W]W.YYYY
    {"^W(%d%d).(%d%d%d%d)$", "weekly", {"week", "year"}},
    -- Pattern: [W]W YYYY
    {"^W(%d%d)%s+(%d%d%d%d)$", "weekly", {"week", "year"}},

    -- MONTHLY PATTERNS
    -- Pattern: YYYY-MM
    {"^(%d%d%d%d)-(%d%d)$", "monthly", {"year", "month"}},
    -- Pattern: YYYY.MM
    {"^(%d%d%d%d).(%d%d)$", "monthly", {"year", "month"}},
    -- Pattern: YYYY MM
    {"^(%d%d%d%d)%s+(%d%d)$", "monthly", {"year", "month"}},
    -- Pattern: YYYY-M  -- (month name)
    {"^(%d%d%d%d)-(%a+)$", "monthly", {"year", "month_name"}},
    -- Pattern: YYYY.M
    {"^(%d%d%d%d).(%a+)$", "monthly", {"year", "month_name"}},
    -- Pattern: YYYY M
    {"^(%d%d%d%d)%s+(%a+)$", "monthly", {"year", "month_name"}},
    -- Pattern: MM-YYYY
    {"^(%d%d)-(%d%d%d%d)$", "monthly", {"month", "year"}},
    -- Pattern: MM.YYYY
    {"^(%d%d).(%d%d%d%d)$", "monthly", {"month", "year"}},
    -- Pattern: MM YYYY
    {"^(%d%d)%s+(%d%d%d%d)$", "monthly", {"month", "year"}},
    -- Pattern: M-YYYY
    {"^(%a+)-(%d%d%d%d)$", "monthly", {"month_name", "year"}},
    -- Pattern: M.YYYY
    {"^(%a+).(%d%d%d%d)$", "monthly", {"month_name", "year"}},
    -- Pattern: M YYYY
    {"^(%a+)%s+(%d%d%d%d)$", "monthly", {"month_name", "year"}},

    -- QUARTERLY PATTERNS
    -- Pattern: YYYY-[Q]Q
    {"^(%d%d%d%d)-Q([1-4])$", "quarterly", {"year", "quarter"}},
    -- Pattern: YYYY.[Q]Q
    {"^(%d%d%d%d).Q([1-4])$", "quarterly", {"year", "quarter"}},
    -- Pattern: YYYY [Q]Q
    {"^(%d%d%d%d)%s+Q([1-4])$", "quarterly", {"year", "quarter"}},
    -- Pattern: [Q]Q-YYYY
    {"^Q([1-4])-(%d%d%d%d)$", "quarterly", {"quarter", "year"}},
    -- Pattern: [Q]Q.YYYY
    {"^Q([1-4]).(%d%d%d%d)$", "quarterly", {"quarter", "year"}},
    -- Pattern: [Q]Q YYYY
    {"^Q([1-4])%s+(%d%d%d%d)$", "quarterly", {"quarter", "year"}},

    -- YEARLY PATTERNS
    -- Pattern: YYYY
    {"^(%d%d%d%d)$", "yearly", {"year"}},
}

-- A Table for specific token detection
-- NOTE: Different from detection_patterns! Only for specific template tokens.
local token_patterns = {
	year       = "%d%d%d%d",
    month      = "%d%d",
    day        = "%d%d",
    week       = "%d%d",
    quarter    = "[1-4]",
	quarter_yq = "%d%d%d%d%-Q[1-4]",
	month_ym   = "%d%d%d%d%-%d%d",
	isoweek    = "%d%d%d%d%-W%d%d",
	date       = "%d%d%d%d%-%d%d%-%d%d",
}

---@param periodic PeriodicConfig|nil
---@return PeriodicConfig
function M.normalize_periodic(periodic)
	periodic = periodic or {}
	periodic.root = periodic.root or ""
	periodic.kinds = periodic.kinds or {}

	for _, kind in ipairs(kinds_order) do
		local kcfg = periodic.kinds[kind] or {}

		if kcfg.enabled == nil then kcfg.enabled = true end
		if kcfg.root == nil then kcfg.root = "" end
		kcfg.folder_path = kcfg.folder_path or ""
		kcfg.filename = kcfg.filename or ""
		kcfg.template_file = kcfg.template_file or ""
		if kcfg.create_if_missing == nil then
		    kcfg.create_if_missing = true
		end

		periodic.kinds[kind] = kcfg
	end

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
	pattern = pattern:gsub("([%%%^%$%(%)%.%[%]%+%-%?])", "%%%1")

	pattern = pattern:gsub("{([%w_]+)}", function(key)
	    return token_patterns[key] or ".*"
	end)

	extension = extension or ""
	if extension ~= "" then
	    pattern = pattern .. vim.pesc(extension) .. "$"
	end

	return pattern
end

return M
