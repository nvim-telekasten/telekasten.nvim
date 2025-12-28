local M = {}
package.loaded[...] = M

local debug_utils = require("plenary.debug_utils")
local Path = require("plenary.path")
local scan = require("plenary.scandir")
local actions = require("telescope.actions")
local conf = require("telescope.config").values
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local entry_display = require("telescope.pickers.entry_display")
local previewers = require("telescope.previewers")
local utils = require("telescope.utils")
local config = require("telekasten.config")
local periodic = require("telekasten.periodic")
local tkpickers = require("telekasten.pickers")
local templates = require("telekasten.templates")
local tkutils = require("telekasten.utils")
local dateutils = require("telekasten.utils.dates")
local linkutils = require("telekasten.utils.links")

local vim = vim

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

--- assemble_roots_specs(opts)
--- Collect all important root directories:
---   - home
---   - periodic root
---   - each enabled periodic kind's root
---   - (optionally) templates and image_subdir
--- Returns an array of { dir = <abs path>, label = <string> }.
--- @param opts { include_aux?: boolean }|nil
local function assemble_roots_specs(opts)
    opts = opts or {}
    local include_aux = opts.include_aux ~= false --default: include templates & images

    local dirs = {}
    local seen = {}

    local function add(dir, label)
        if dir ~= nil and dir ~= "" and not seen[dir] then
            seen[dir] = true
            table.insert(dirs, { dir = dir, label = label })
        end
    end

    add(config.options.home, "home")

    local pcfg = config.options.periodic
    if pcfg then
        add(pcfg.root, "proot")

        if pcfg.kinds then
            for kind, kcfg in pairs(pcfg.kinds) do
                if kcfg.enabled then
                    local root = periodic.search_root(pcfg, kind)
                    add(root, kind)
                end
            end
        end
    end

    if include_aux then
        add(config.options.templates, "templates")
        add(config.options.image_subdir, "images")
    end

    return dirs
end

--- assemble_roots(opts)
--- Convenience wrapper that returns just a list of directory paths,
--- in the same order as assemble_root_specs.
--- @param opts { include_aux?: boolean }|nil
--- @return string[]
function M.assemble_roots(opts)
    local specs = assemble_roots_specs(opts)
    local roots = {}
    for _, spec in ipairs(specs) do
        table.insert(roots, spec.dir)
    end
    return roots
end

-- Prompts the user for a note title
function M.prompt_title(ext, defaultFile, callback, cwd)
    local canceledStr = "__INPUT_CANCELLED__"
    local current_dir = ""
    -- change the cwd to the configured home directory, so tab completion
    -- works for the folders in that directory
    if not cwd then
        cwd = ""
    end
    if cwd ~= "" then
        current_dir = vim.fn.getcwd()
        vim.fn.chdir(cwd)
    end
    vim.ui.input({
        prompt = "Title: ",
        cancelreturn = canceledStr,
        completion = "file",
        default = defaultFile,
    }, function(title)
        -- change back to the original directory
        if current_dir ~= "" then
            vim.fn.chdir(current_dir)
        end
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

local function apply_match(kind, fields, caps, cal_monday)
    local dinfo = {}

    for i, field in ipairs(fields) do
        local v = caps[i]

        if periodic.periodic_kinds[field] then
            v = tonumber(v)
        end

        dinfo[field] = v
    end

    -- SPECIAL CASE: weekly notes
    -- If we have a year + week, then convert that ISO week to a proper date
    -- (this gives us year/month/day anchored to the *start* of that week)
    if dinfo.week ~= nil and dinfo.year ~= nil then
        dinfo = dateutils.isoweek_to_date(dinfo.year, dinfo.week)
        dinfo.calculate_dates(dinfo, cal_monday)
        return kind, dinfo
    end

    -- SPECIAL CASE: quarterly notes
    -- quarter -> anchor on the first month of that quarter
    if dinfo.quarter ~= nil and dinfo.year ~= nil then
        local qi = dinfo.quarter
        if qi >= 1 and qi <= 4 then
            local first_month = (qi - 1) * 3 + 1
            dinfo.month = first_month
            dinfo.day = 1
        end
    end

    -- enforce sane defaults for monthlies and yearlies as well
    if kind == "monthly" then
        dinfo.day = dinfo.day or 1
    elseif kind == "yearly" then
        dinfo.month = dinfo.month or 1
        dinfo.day = dinfo.day or 1
    end

    dinfo = dateutils.calculate_dates(dinfo, cal_monday)

    return kind, dinfo
end

--- check_if_periodic(title)
-- Returns info on if the title given is for a periodic note and the date(s)
-- @param title string Title of the note to be checked
-- @return boolean True if daily note
-- @return boolean True if weekly note
-- @return boolean True if monthly note
-- @return boolean True if quarterly note
-- @return boolean True if yearly note
-- @return table Date info
local function check_if_periodic(title)
    local cal_monday = config.options.calendar_opts.calendar_monday
    local dateinfo = dateutils.calculate_dates(nil, cal_monday) -- sane default

    local is_daily = false
    local is_weekly = false
    local is_monthly = false
    local is_quarterly = false
    local is_yearly = false

    for _, entry in ipairs(periodic.detection_patterns) do
        local pattern = entry.pattern
        local kind = entry.kind
        local fields = entry.fields or {}
        local caps = { title:match(pattern) }

        if #caps > 0 then
            local k, dinfo = apply_match(kind, fields, caps, cal_monday)

            if k == "daily" then
                is_daily = true
            elseif k == "weekly" then
                is_weekly = true
            elseif k == "monthly" then
                is_monthly = true
            elseif k == "quarterly" then
                is_quarterly = true
            elseif k == "yearly" then
                is_yearly = true
            end

            dateinfo = dinfo
            break
        end
    end

    return is_daily, is_weekly, is_monthly, is_quarterly, is_yearly, dateinfo
end

--- filter_filetypes(flist, ftypes)
-- Returns all entries in flist with filetypes in ftypes
-- @param flist table List of files
-- @param ftypes table List of file types
-- @return table List of flist entries with filetype in ftypes
local function filter_filetypes(flist, ftypes)
    local new_fl = {}
    ftypes = ftypes or { config.options.extension }

    local ftypeok = {}
    for _, ft in pairs(ftypes) do
        ftypeok[ft] = true
    end

    for _, fn in pairs(flist) do
        if ftypeok[M.get_extension(fn)] then
            table.insert(new_fl, fn)
        end
    end
    return new_fl
end

-- Defines how to  provide a media preview when trying to find files
-- TODO: This is all setup for defining media_preview just for use in find_files_sorted, feels like it could be cleaner
local sourced_file = debug_utils.sourced_filepath()
M.base_directory = vim.fn.fnamemodify(sourced_file, ":h:h:h")
local media_files_base_directory = M.base_directory
    .. "/telescope-media-files.nvim"
local defaulter = utils.make_default_callable
local media_preview = defaulter(function(opts)
    local preview_cmd = ""
    if config.options.media_previewer == "telescope-media-files" then
        preview_cmd = media_files_base_directory .. "/scripts/vimg"
    end

    if config.options.media_previewer == "catimg-previewer" then
        preview_cmd = M.base_directory
            .. "/telekasten.nvim/scripts/catimg-previewer"
    end

    if vim.startswith(config.options.media_previewer, "viu-previewer") then
        preview_cmd = M.base_directory
            .. "/telekasten.nvim/scripts/"
            .. config.options.media_previewer
    end

    if vim.fn.executable(preview_cmd) == 0 then
        print("Previewer not found: " .. preview_cmd)
        return conf.file_previewer(opts)
    end
    return previewers.new_termopen_previewer({
        get_command = opts.get_command
            or function(entry)
                local tmp_table = vim.split(entry.value, "\t")
                local preview = opts.get_preview_window()
                opts.cwd = opts.cwd and vim.fn.expand(opts.cwd)
                    or vim.loop.cwd()
                if vim.tbl_isempty(tmp_table) then
                    return { "echo", "" }
                end
                print(tmp_table[1])
                return {
                    preview_cmd,
                    tmp_table[1],
                    preview.col,
                    preview.line + 1,
                    preview.width,
                    preview.height,
                }
            end,
    })
end, {})

--- new_uuid(uuid_style)
-- Returns a new UUID in the specified style. If
-- @param uuid_style string|function If "rand", use random_variable(6),
-- else if function, use to make UUID, else use as date format
-- @return string UUID
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

--- check_dir_and_ask(dir, purpose, callback)
-- Checks for the existence of directory/folder dir and if not, creates it if possible.
-- Runs callback(true) if dir exists or callback(false) if dir doesn't exist and can't be created.
-- @param dir string A file system directory/folder
-- @param purpose string Purpose of the directory being checked
-- @param callback function
-- @return boolean True if dir exists or didn't but is successfully created, false if nonexistent and creation fails
-- TODO: Why doesn't callback get called if the directory exists? Figure out and explain here.
function M.check_dir_and_ask(dir, purpose, callback)
    local ret = false
    if dir ~= nil and Path:new(dir):exists() == false then
        vim.ui.select({ "No (default)", "Yes" }, {
            prompt = "Telekasten.nvim: "
                .. purpose
                .. " folder "
                .. dir
                .. " does not exist!"
                .. " Shall I create it? ",
        }, function(answer)
            if answer == "Yes" then
                if
                    Path:new(dir):mkdir({ parents = true, exists_ok = false })
                then
                    vim.cmd('echomsg " "')
                    vim.cmd('echomsg "' .. dir .. ' created"')
                    ret = true
                else
                    -- unreachable: plenary.Path:mkdir() will error out
                    tkutils.print_error("Could not create directory " .. dir)
                    ret = false
                    callback(ret)
                end
            end
        end)
    else
        ret = true
        if callback ~= nil then
            callback(ret)
        end
    end
    return ret
end

function M.global_dir_check(callback)
    local ret
    if config.options.home == nil then
        tkutils.print_error("Telekasten.nvim: home is not configured!")
        ret = false
        callback(ret)
    end
    local check = M.check_dir_and_ask

    local dirs = assemble_roots_specs({ include_aux = true })

    local i = 1
    local function step()
        local entry = dirs[i]
        if not entry then
            callback(true)
            return
        end

        i = i + 1
        check(entry.dir, entry.label, function(ok)
            if ok == false then
                callback(false)
                return
            end
            step()
        end)
    end

    step()
end

--- generate_note_filename(uuid, title)
-- Returns the new note's file name, accounting for UUID usage and any desired space substition
-- @param uuid string New UUID for file name if needed
-- @param title string Title of the new note
-- @return string Complete file name with appropriate UUID if needed
function M.generate_note_filename(uuid, title)
    if config.options.filename_space_subst ~= nil then
        title = title:gsub(" ", config.options.filename_space_subst)
    end

    local pp = Path:new(title)
    local p_splits = pp:_split()
    local filename = p_splits[#p_splits]
    local subdir = title:gsub(tkutils.escape(filename), "")

    local sep = config.options.uuid_sep or "-"
    if config.options.new_note_filename ~= "uuid" and #title > 0 then
        if config.options.new_note_filename == "uuid-title" then
            return subdir .. uuid .. sep .. filename
        elseif config.options.new_note_filename == "title-uuid" then
            return title .. sep .. uuid
        else
            return title
        end
    else
        return uuid
    end
end

--- make_config_path_absolute(path)
-- Returns the absolute path to a local file
-- @param path string Path to be made absolute
-- @return string Absolute version of the given path
function M.make_config_path_absolute(path)
    local ret = path
    if not (Path:new(path):is_absolute()) and path ~= nil then
        ret = config.options.home .. "/" .. path
    end

    if ret ~= nil then
        ret = ret:gsub("/$", "")
    end

    return ret
end

--- Pinfo
--- Table of data related to a file's location and purpose
---    - fexists : true if file exists
---    - title : the title (filename including subdirs without extension)
---      - if opts.subdirs_in_links is false, no subdirs will be included
---    - filename : filename component only
---    - filepath : full path, identical to p
---    - root_dir : the root dir (home, dailies, ...)
---    - sub_dir : subdir if present, relative to root_dir
---    - is_periodic : bool
---    - is_daily : bool
---    - is_weekly : bool
---    - is_monthly : bool
---    - is_quarterly : bool
---    - is_yearly : bool
---    - template : suggested template based on opts
M.Pinfo = {
    fexists = false,
    title = "",
    filename = "",
    filepath = "",
    root_dir = "",
    sub_dir = "",
    is_periodic = false,
    is_daily = false,
    is_weekly = false,
    is_monthly = false,
    is_quarterly = false,
    is_yearly = false,
    template = "",
    calendar_info = nil,
}

--- Pinfo:new(opts)
-- Returns a Pinfo table tailored to the file path or title specified in opts
-- @param opts table Options, ideally including filepath and title
-- @return table Pinfo table of file info
-- TODO: Unsure of potential relation to new file paths and/or titles, check later
function M.Pinfo:new(opts)
    opts = opts or {}

    local object = {}
    setmetatable(object, self)
    self.__index = self
    if opts.filepath then
        return object:resolve_path(opts.filepath, opts)
    end
    if opts.title ~= nil then
        return object:resolve_link(opts.title, opts)
    end
    return object
end

--- resolve_path(p, opts)
-- Inspects the path p and returns a Pinfo table
-- @param p string Path to directory
-- @param opts table Options, ideally including subdirs_in_links
-- @return table Pinfo
function M.Pinfo:resolve_path(p, opts)
    opts = opts or {}
    opts.subdirs_in_links = opts.subdirs_in_links
        or config.options.subdirs_in_links

    self.fexists = M.file_exists(p)
    self.filepath = p
    self.root_dir = config.options.home
    self.is_periodic = false
    self.is_daily = false
    self.is_weekly = false
    self.is_monthly = false
    self.is_quarterly = false
    self.is_yearly = false

    -- strip all dirs to get filename
    local pp = Path:new(p)
    local p_splits = pp:_split()
    self.filename = p_splits[#p_splits]
    self.title = self.filename:gsub(config.options.extension, "")

    if vim.startswith(p, config.options.home) then
        self.root_dir = config.options.home
    end

    local is_daily, is_weekly, is_monthly, is_quarterly, is_yearly, dinfo =
        check_if_periodic(self.title)

    self.is_daily = is_daily
    self.is_weekly = is_weekly
    self.is_monthly = is_monthly
    self.is_quarterly = is_quarterly
    self.is_yearly = is_yearly
    self.is_periodic = is_daily
        or is_weekly
        or is_monthly
        or is_quarterly
        or is_yearly

    if self.is_periodic then
        local kind
        if is_daily then
            kind = "daily"
        elseif is_weekly then
            kind = "weekly"
        elseif is_monthly then
            kind = "monthly"
        elseif is_quarterly then
            kind = "quarterly"
        elseif is_yearly then
            kind = "yearly"
        end

        local pcfg = config.options.periodic
        local _, _, root_dir =
            periodic.build_path(pcfg, kind, dinfo, config.options.extension)

        if root_dir and root_dir ~= "" then
            self.root_dir = root_dir
        end
    end

    -- now work out subdir relative to root
    self.sub_dir = p:gsub(tkutils.escape(self.root_dir .. "/"), "")
        :gsub(tkutils.escape(self.filename), "")
        :gsub("/$", "")
        :gsub("^/", "")

    if opts.subdirs_in_links and #self.sub_dir > 0 then
        self.title = self.sub_dir .. "/" .. self.title
    end

    return self
end

-- string, table -> table
--- resolve_link(title, opts)
-- Returns a Pinfo table for the given title and options
-- @param title string Title to be resolved to file path
-- @param opts table Options, ideally including periodics, home, extension, template_handling,
-- new_note_location, and note_type_templates
-- @return table Pinfo for note corresponding to title if found or detailing the failure
function M.Pinfo:resolve_link(title, opts)
    -- Set options, preferring passed opts over user config
    opts = opts or {}
    opts.periodic = opts.periodic or config.options.periodic
    opts.home = opts.home or config.options.home
    opts.extension = opts.extension or config.options.extension
    opts.template_handling = opts.template_handling
        or config.options.template_handling
    opts.new_note_location = opts.new_note_location
        or config.options.new_note_location
    opts.template_new_note = opts.template_new_note
        or config.options.template_new_note
    opts.note_type_templates = opts.note_type_templates
        or {
            normal = config.options.template_new_note,
        }

    -- Set basic Pinfo values
    self.fexists = false
    self.title = title
    self.filename = title .. opts.extension
    self.filename = self.filename:gsub("^%./", "") -- strip potential leading ./
    self.root_dir = opts.home
    self.template = nil
    self.calendar_info = nil

    local is_daily, is_weekly, is_monthly, is_quarterly, is_yearly, dinfo =
        check_if_periodic(self.title)

    self.calendar_info = dinfo
    self.is_daily = is_daily
    self.is_weekly = is_weekly
    self.is_monthly = is_monthly
    self.is_yearly = is_yearly
    self.is_periodic = is_daily
        or is_weekly
        or is_monthly
        or is_quarterly
        or is_yearly

    local kind
    if is_daily then
        kind = "daily"
    elseif is_weekly then
        kind = "weekly"
    elseif is_monthly then
        kind = "monthly"
    elseif is_yearly then
        kind = "yearly"
    end

    if kind ~= nil then
        local path, _, root_dir, _ =
            periodic.build_path(opts.periodic, kind, dinfo, opts.extension)

        if path and M.file_exists(path) then
            self.filepath = path
            self.fexists = true
            self.root_dir = root_dir or opts.home
        end
    end

    if M.file_exists(opts.home .. "/" .. self.filename) then
        self.filepath = opts.home .. "/" .. self.filename
        self.fexists = true
    end

    -- If still nothing found, check subdirectories
    if self.fexists == false then
        -- now search for it in all subdirs
        local subdirs = scan.scan_dir(opts.home, { only_dirs = true })
        local tempfn
        for _, folder in pairs(subdirs) do
            tempfn = folder .. "/" .. self.filename
            -- [[testnote]]
            if M.file_exists(tempfn) then
                self.filepath = tempfn
                self.fexists = true
                -- print("Found: " ..self.filename)
                break
            end
        end
    end

    -- if we just cannot find the note, check if it's a periodic one
    -- Note that fexists is not changed; This is prep in case a new note is made
    if self.fexists == false then
        -- TODO: if we're not smart, we also shouldn't need to try to set the calendar info..?
        --       I bet someone will want the info in there, so let's put it in if possible
        _, _, _, _, _, self.calendar_info = check_if_periodic(self.title) -- will set today as default, so leave in!

        if opts.new_note_location == "smart" then
            if kind ~= nil and self.calendar_info ~= nil then
                local path, _, root_dir, _ = periodic.build_path(
                    opts.periodic,
                    kind,
                    self.calendar_info,
                    opts.extension
                )

                if path then
                    self.filepath = path
                    self.root_dir = root_dir or opts.home
                    self.is_periodic = true
                else
                    self.filepath = opts.home .. "/" .. self.filename
                end
            else
                self.filepath = opts.home .. "/" .. self.filename
            end
        elseif opts.new_note_location == "same_as_current" then
            local cwd = vim.fn.expand("%:p")
            if #cwd > 0 then
                self.root_dir = Path:new(cwd):parent():absolute()
                if Path:new(self.root_dir):exists() then
                    -- check if potential subfolders in filename would end up in a non-existing directory
                    self.filepath = self.root_dir .. "/" .. self.filename
                    if not Path:new(self.filepath):parent():exists() then
                        print("Path " .. self.filepath .. " is invalid!")
                        -- self.filepath = opts.home .. "/" .. self.filename
                    end
                else
                    print("Path " .. self.root_dir .. " is invalid!")
                    -- self.filepath = opts.home .. "/" .. self.filename
                end
            else
                self.filepath = opts.home .. "/" .. self.filename
            end
        else
            -- default fn for creation
            self.filepath = opts.home .. "/" .. self.filename
        end

        -- final round, there still can be a subdir mess-up
        if not Path:new(self.filepath):parent():exists() then
            print("Path " .. self.filepath .. " is invalid!")
        end
    end

    -- now work out subdir relative to root
    self.sub_dir = self.filepath
        :gsub(tkutils.escape(self.root_dir .. "/"), "")
        :gsub(tkutils.escape(self.filename), "")
        :gsub("/$", "")
        :gsub("^/", "")

    -- now suggest a template based on opts
    self.template = opts.template_new_note
    if opts.template_handling == "prefer_new_note" then
        self.template = opts.note_type_templates.normal
    elseif opts.template_handling == "always_ask" then
        self.template = nil
    elseif opts.template_handling == "smart" then
        local pcfg = config.options.periodic
        if self.is_daily then
            self.template = pcfg.kinds.daily.template_file
        elseif self.is_weekly then
            self.template = pcfg.kinds.weekly.template_file
        elseif self.is_monthly then
            self.template = pcfg.kinds.monthly.template_file
        elseif self.is_quarterly then
            self.template = pcfg.kinds.quarterly.template_file
        elseif self.is_yearly then
            self.template = pcfg.kinds.yearly.template_file
        else
            self.template = opts.template_new_note
        end
    end

    return self
end

-- find_files_sorted(opts)
-- like builtin.find_files, but:
--     - uses plenary.scan_dir synchronously instead of external jobs
--     - pre-sorts the file list in descending order (nice for dates, most recent first)
--     - filters for allowed file types by extension
--     - (also supports devicons)
--     - displays subdirs if necessary
--         - e.g. when searching for daily notes, no subdirs are displayed
--         - but when entering a date in find_notes, the daily/ and weekly/ subdirs are displayed
--     - optionally previews media (pdf, images, mp4, webm)
--         - this requires the telescope-media-files.nvim extension
-- @param opts table Options, ideally including search_pattern, search_depth, filter_extensions, sort,
--                   show_link_counts, and preview_type
function M.find_files_sorted(opts)
    opts = opts or {}
    local search_pattern = opts.search_pattern or nil
    local search_depth = opts.search_depth or nil
    local scan_opts = { search_pattern = search_pattern, depth = search_depth }

    local file_list = scan.scan_dir(opts.cwd, scan_opts)
    local filter_extensions = opts.filter_extensions
        or config.options.filter_extensions
    file_list = filter_filetypes(file_list, filter_extensions)
    local sort_option = opts.sort or "filename"
    if sort_option == "modified" then
        table.sort(file_list, function(a, b)
            return vim.fn.getftime(a) > vim.fn.getftime(b)
        end)
    else
        table.sort(file_list, function(a, b)
            return a > b
        end)
    end

    local counts = nil
    if opts.show_link_counts then
        counts = linkutils.generate_backlink_map(config.options)
    end

    -- display with devicons
    local function iconic_display(display_entry)
        local display_opts = {
            path_display = function(_, e)
                return e:gsub(tkutils.escape(opts.cwd .. "/"), "")
            end,
        }

        local hl_group
        local display = utils.transform_path(display_opts, display_entry.value)

        display, hl_group =
            utils.transform_devicons(display_entry.value, display, false)

        if hl_group then
            return display, { { { 1, 3 }, hl_group } }
        else
            return display
        end
    end

    -- for media_files
    local popup_opts = {}
    opts.get_preview_window = function()
        return popup_opts.preview
    end

    -- local width = config.width
    --     or config.layout_config.width
    --     or config.layout_config[config.layout_strategy].width
    --     or vim.o.columns
    -- local telescope_win_width
    -- if width > 1 then
    --     telescope_win_width = width
    -- else
    --     telescope_win_width = math.floor(vim.o.columns * width)
    -- end
    local displayer = entry_display.create({
        separator = "",
        items = {
            { width = 4 },
            { width = 4 },
            { remaining = true },
        },
    })

    local function make_display(entry)
        local fn = entry.value
        local nlinks = counts.link_counts[fn] or 0
        local nbacks = counts.backlink_counts[fn] or 0

        if opts.show_link_counts then
            local display, hl = iconic_display(entry)

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
                    display,
                    function()
                        return hl
                    end,
                },
            })
        else
            return iconic_display(entry)
        end
    end

    local function entry_maker(entry)
        local iconic_entry = {}
        iconic_entry.value = entry
        iconic_entry.path = entry
        iconic_entry.ordinal = entry
        if opts.show_link_counts then
            iconic_entry.display = make_display
        else
            iconic_entry.display = iconic_display
        end
        return iconic_entry
    end

    local previewer = conf.file_previewer(opts)
    if opts.preview_type == "media" then
        previewer = media_preview.new(opts)
    end

    opts.attach_mappings = opts.attach_mappings
        or function(_, _)
            actions.select_default:replace(
                tkpickers.picker_actions.select_default
            )
        end

    local picker = pickers.new(opts, {
        finder = finders.new_table({
            results = file_list,
            entry_maker = entry_maker,
        }),
        sorter = conf.generic_sorter(opts),
        previewer = previewer,
    })

    -- local oc = picker.finder.close
    --
    -- picker.finder.close = function()
    --     print('on close')
    --     print(vim.inspect(picker:get_selection()))
    --     -- unfortunately, no way to tell if the selection was confirmed or
    --     -- canceled out
    --     oc()
    --     -- alternative: attach default mappings for <ESC> and <C-c>
    --     --       if anyone quits with q!, it's their fault
    -- end

    -- for media_files:
    local line_count = vim.o.lines - vim.o.cmdheight
    if vim.o.laststatus ~= 0 then
        line_count = line_count - 1
    end

    popup_opts = picker:get_window_options(vim.o.columns, line_count)

    picker:find()
end

local function resolve_template_file(templatefn)
    if not templatefn or templatefn == "" then
        return nil
    end

    local expanded = vim.fn.expand(templatefn)

    local cfg = config.options
    local candidates = {}

    table.insert(candidates, expanded)

    local p = Path:new(expanded)

    if not p:is_absolute() then
        if cfg.templates and cfg.templates ~= "" then
            table.insert(
                candidates,
                Path:new({ cfg.templates, templatefn}):absolute()
            )
        end
        if cfg.home and cfg.home ~= "" then
            table.insert(
                candidates,
                Path:new({cfg.home, templatefn}):absolute()
            )
        end
    end

    for _, cand in ipairs(candidates) do
        if M.file_exists(cand) then
            return cand
        end
    end

    return nil
end

-- string, string, string, string, table, function -> N/A
--- create_note_from_template(title, uuid, filepath, templatefn, calendar_info, callback)
-- @param title string Title for the new note
-- @param uuid string UUID to include in title
-- @param filepath string
-- No return, only creates a new note file from a given template file
-- utils/templates.lua? utils/files.lua? utils/init.lua?
function M.create_note_from_template(
    title,
    uuid,
    filepath,
    templatefn,
    calendar_info,
    callback
)

    templatefn = resolve_template_file(templatefn)

    -- first, read the template file
    local lines = {}
    if M.file_exists(templatefn) then
        for line in io.lines(templatefn) do
            lines[#lines + 1] = line
        end
    end

    -- now write the output file, substituting vars line by line
    local file_dir = filepath:match("(.*/)") or ""
    M.check_dir_and_ask(file_dir, "Create weekly dir", function(dir_succeed)
        if dir_succeed == false then
            return
        end

        local ofile = io.open(filepath, "a")

        for _, line in pairs(lines) do
            ofile:write(
                templates.subst_templated_values(
                    line,
                    title,
                    calendar_info,
                    uuid,
                    config.options.calendar_opts.calendar_monday
                ) .. "\n"
            )
        end

        ofile:flush()
        ofile:close()
        callback()
    end)
end

return M
