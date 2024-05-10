local debug_utils = require("plenary.debug_utils")
local Path = require("plenary.path")
local scan = require("plenary.scandir")
local conf = require("telescope.config").values
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local entry_display = require("telescope.pickers.entry_display")
local previewers = require("telescope.prevewers")
local utils = require("telescope.utils")
local config = require("telekasten.config")
local tkutils = require("telekasten.utils")
local dateutils = require("telekasten.utils.dates")
local linkutils = require("telekasten.utils.links")

local M = {}

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

-- Prompts the user for a note title
function M.prompt_title(ext, defaultFile, callback)
    local canceledStr = "__INPUT_CANCELLED__"

    vim.ui.input({
        prompt = "Title: ",
        cancelreturn = canceledStr,
        completion = "file",
        default = defaultFile,
    }, function(title)
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

-- string -> bool, bool, table
-- Returns info on if the title given is for a daily or weekly and the date(s)
-- Maybe move to utils/dates.lua?
local function check_if_daily_or_weekly(title)
    local daily_match = "^(%d%d%d%d)-(%d%d)-(%d%d)$"
    local weekly_match = "^(%d%d%d%d)-W(%d%d)$"

    local is_daily = false
    local is_weekly = false
    local dateinfo = dateutils.calculate_dates(
        nil,
        config.options.calendar_opts.calendar_monday
    ) -- sane default

    -- Set return values for a daily note
    local start, _, year, month, day = title:find(daily_match)
    if start ~= nil then
        if tonumber(month) < 13 then
            if tonumber(day) < 32 then -- TODO: This should probably be refined for accuracy in 28-30 day months
                is_daily = true
                dateinfo.year = tonumber(year)
                dateinfo.month = tonumber(month)
                dateinfo.day = tonumber(day)
                dateinfo = dateutils.calculate_dates(
                    dateinfo,
                    config.options.calendar_opts.calendar_monday
                )
            end
        end
    end

    -- Set return values for a weekly note
    -- Seems pointless to check both this and daily. Maybe try an else?
    local week
    start, _, year, week = title:find(weekly_match)
    if start ~= nil then
        if tonumber(week) < 53 then
            is_weekly = true
            -- ISO8601 week -> date calculation
            dateinfo = dateutils.isoweek_to_date(tonumber(year), tonumber(week))
            dateinfo = dateutils.calculate_dates(
                dateinfo,
                config.options.calendar_opts.calendar_monday
            )
        end
    end

    return is_daily, is_weekly, dateinfo
end

-- table, table -> table
-- Returns all entries in flist with filetypes in ftypes
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
    -- nested callbacks to handle asynchronous vim.ui.select
    -- looks a little confusing but execution is sequential from top to bottom
    check(config.options.home, "home", function()
        check(config.options.dailies, "dailies", function()
            check(config.options.weeklies, "weeklies", function()
                check(config.options.templates, "templates", function()
                    -- Note the `callback` in this last function call
                    check(config.options.image_subdir, "images", callback)
                end)
            end)
        end)
    end)
end

-- string, string -> string
-- Returns the new note's file name, accounting for UUID usage and any desired space substition.
-- Move to utils/files.lua?
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

-- string -> string
-- Returns the absolute path to a local file
-- Move to utils/files.lua
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
---    - is_daily_or_weekly : bool
---    - is_daily : bool
---    - is_weekly : bool
---    - template : suggested template based on opts
-- Move to utils/files.lua?
M.Pinfo = {
    fexists = false,
    title = "",
    filename = "",
    filepath = "",
    root_dir = "",
    sub_dir = "",
    is_daily_or_weekly = false,
    is_daily = false,
    is_weekly = false,
    template = "",
    calendar_info = nil,
}

-- table -> table
-- Returns a Pinfo table tailored to the file path or title specified in opts
-- Unsure of potential relation to new file paths and/or titles, check later
-- Keep with Pinfo
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

-- string, table -> table
--- resolve_path(p, opts)
--- inspects the path and returns a Pinfo table
-- Keep with Pinfo
function M.Pinfo:resolve_path(p, opts)
    opts = opts or {}
    opts.subdirs_in_links = opts.subdirs_in_links
        or config.options.subdirs_in_links

    self.fexists = M.file_exists(p)
    self.filepath = p
    self.root_dir = config.options.home
    self.is_daily_or_weekly = false
    self.is_daily = false
    self.is_weekly = false

    -- strip all dirs to get filename
    local pp = Path:new(p)
    local p_splits = pp:_split()
    self.filename = p_splits[#p_splits]
    self.title = self.filename:gsub(config.options.extension, "")

    if vim.startswith(p, config.options.home) then
        self.root_dir = config.options.home
    end
    if vim.startswith(p, config.options.dailies) then
        self.root_dir = config.options.dailies
        -- TODO: parse "title" into calendarinfo like in resolve_link
        -- not really necessary as the file exists anyway and therefore we don't need to instantiate a template
        self.is_daily_or_weekly = true
        self.is_daily = true
    end
    if vim.startswith(p, config.options.weeklies) then
        -- TODO: parse "title" into calendarinfo like in resolve_link
        -- not really necessary as the file exists anyway and therefore we don't need to instantiate a template
        self.root_dir = config.options.weeklies
        self.is_daily_or_weekly = true
        self.is_weekly = true
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
-- Returns a Pinfo table for the given title and options
function M.Pinfo:resolve_link(title, opts)
    -- Set options, preferring passed opts over user config
    opts = opts or {}
    opts.weeklies = opts.weeklies or config.options.weeklies
    opts.dailies = opts.dailies or config.options.dailies
    opts.home = opts.home or config.options.home
    opts.extension = opts.extension or config.options.extension
    opts.template_handling = opts.template_handling
        or config.options.template_handling
    opts.new_note_location = opts.new_note_location
        or config.options.new_note_location

    -- Set basic Pinfo values
    self.fexists = false
    self.title = title
    self.filename = title .. opts.extension
    self.filename = self.filename:gsub("^%./", "") -- strip potential leading ./
    self.root_dir = opts.home
    self.is_daily_or_weekly = false
    self.is_daily = false
    self.is_weekly = false
    self.template = nil
    self.calendar_info = nil

    -- Try checking for existence and assigning values as a weekly, then as a daily, then as a plain note in home
    if
        opts.weeklies
        and M.file_exists(opts.weeklies .. "/" .. self.filename)
    then
        -- TODO: parse "title" into calendarinfo like below
        -- not really necessary as the file exists anyway and therefore we don't need to instantiate a template
        -- if we still want calendar_info, just move the code for it out of `if self.fexists == false`.
        self.filepath = opts.weeklies .. "/" .. self.filename
        self.fexists = true
        self.root_dir = opts.weeklies
        self.is_daily_or_weekly = true
        self.is_weekly = true
    end
    if -- TODO: This should be able to convert to an elseif, I think. Weekly and daily file names are distinct
        opts.dailies
        and M.file_exists(opts.dailies .. "/" .. self.filename)
    then
        -- TODO: parse "title" into calendarinfo like below
        -- not really necessary as the file exists anyway and therefore we don't need to instantiate a template
        -- if we still want calendar_info, just move the code for it out of `if self.fexists == false`.
        self.filepath = opts.dailies .. "/" .. self.filename
        self.fexists = true
        self.root_dir = opts.dailies
        self.is_daily_or_weekly = true
        self.is_daily = true
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

    -- if we just cannot find the note, check if it's a daily or weekly one
    -- Note that fexists is not changed; This is prep in case a new note is made
    if self.fexists == false then
        -- TODO: if we're not smart, we also shouldn't need to try to set the calendar info..?
        --       I bet someone will want the info in there, so let's put it in if possible
        _, _, self.calendar_info = check_if_daily_or_weekly(self.title) -- will set today as default, so leave in!

        if opts.new_note_location == "smart" then
            self.filepath = opts.home .. "/" .. self.filename -- default
            self.is_daily, self.is_weekly, self.calendar_info =
                check_if_daily_or_weekly(self.title) -- TODO: Don't replicate call, simply save all values above
            if self.is_daily == true then
                self.root_dir = opts.dailies
                self.filepath = opts.dailies .. "/" .. self.filename
                self.is_daily_or_weekly = true
            end
            if self.is_weekly == true then
                self.root_dir = opts.weeklies
                self.filepath = opts.weeklies .. "/" .. self.filename
                self.is_daily_or_weekly = true
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
    self.template = M.note_type_templates.normal
    if opts.template_handling == "prefer_new_note" then
        self.template = M.note_type_templates.normal
    elseif opts.template_handling == "always_ask" then
        self.template = nil
    elseif opts.template_handling == "smart" then
        if self.is_daily then
            self.template = M.note_type_templates.daily
        elseif self.is_weekly then
            self.template = M.note_type_templates.weekly
        else
            self.template = M.note_type_templates.normal
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
-- Move to utils/files.lua
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
            actions.select_default:replace(picker_actions.select_default)
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

return M
