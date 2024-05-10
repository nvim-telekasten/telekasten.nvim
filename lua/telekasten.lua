local builtin = require("telescope.builtin")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local action_set = require("telescope.actions.set")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local scan = require("plenary.scandir")
local utils = require("telescope.utils")
local previewers = require("telescope.previewers")
local make_entry = require("telescope.make_entry")
local entry_display = require("telescope.pickers.entry_display")
local sorters = require("telescope.sorters")
local themes = require("telescope.themes")
local debug_utils = require("plenary.debug_utils")
local filetype = require("plenary.filetype")
local taglinks = require("telekasten.utils.taglinks")
local tagutils = require("telekasten.utils.tags")
local linkutils = require("telekasten.utils.links")
local dateutils = require("telekasten.utils.dates")
local fileutils = require("telekasten.utils.files")
local templates = require("telekasten.templates")
local Path = require("plenary.path")
local tkpickers = require("telekasten.pickers")
local tkutils = require("telekasten.utils")
local config = require("telekasten.config")

-- declare locals for the nvim api stuff to avoid more lsp warnings
local vim = vim

local M = {}

-- string, string -> string
-- Returns the new note's file name, accounting for UUID usage and any desired space substition.
-- Move to utils/files.lua?
local function generate_note_filename(uuid, title)
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
local function make_config_path_absolute(path)
    local ret = path
    if not (Path:new(path):is_absolute()) and path ~= nil then
        ret = config.options.home .. "/" .. path
    end

    if ret ~= nil then
        ret = ret:gsub("/$", "")
    end

    return ret
end

-- string, string, string -> N/A
-- No return, runs ripgrep and sed if and only if the global dir check passes
-- ripgrep finds all files with instances of 'old' in 'dir'
-- sed takes file list from rg and replaces all instances of 'old' with 'new'
-- Move to utils/files.lua? Arguably file related
local function recursive_substitution(dir, old, new)
    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        if vim.fn.executable("sed") == 0 then
            vim.api.nvim_err_write("Sed not installed!\n")
            return
        end

        old = tkutils.grep_escape(old)
        new = tkutils.grep_escape(new)

        local sedcommand = "sed -i"
        if vim.fn.has("mac") == 1 then
            sedcommand = "sed -i ''"
        end

        -- 's|\(\[\[foo\)\([]#|\]\)|\[\[MYTEST\2|g'
        local replace_cmd = "rg -0 -l -t markdown '"
            .. old
            .. "' "
            .. dir
            .. " | xargs -0 "
            .. sedcommand
            .. " 's|\\("
            .. old
            .. "\\)\\([]#|]\\)|"
            .. new
            .. "\\2|g' >/dev/null 2>&1"
        os.execute(replace_cmd)
    end)
end

-- N/A -> N/A
-- No return
-- Saves all modified buffers if auto_set_filetype and buffer's filetype is telekasten
-- or do so if not auto_set_filetype
local function save_all_mod_buffers()
    for i = 1, vim.fn.bufnr("$") do
        if
            vim.fn.getbufvar(i, "&mod") == 1
            and (
                (
                    config.options.auto_set_filetype == true
                    and vim.fn.getbufvar(i, "&filetype") == "telekasten"
                )
                or config.options.auto_set_filetype == false
            )
        then
            vim.cmd(i .. "bufdo w")
        end
    end
end

-- ----------------------------------------------------------------------------
-- image stuff
-- ----------------------------------------------------------------------------

-- string, string, string -> string
-- Return a relative path from the buffer to the image dir
-- Move to a utils/images.lua?
local function make_relative_path(bufferpath, imagepath, sep)
    sep = sep or "/" -- TODO: This seems UNIX-centric. Consider using something from os or plenary to get OS's file sep

    -- Split the buffer and image path into their dirs/files
    local buffer_dirs = {}
    for w in string.gmatch(bufferpath, "([^" .. sep .. "]+)") do
        buffer_dirs[#buffer_dirs + 1] = w
    end
    local image_dirs = {}
    for w in string.gmatch(imagepath, "([^" .. sep .. "]+)") do
        image_dirs[#image_dirs + 1] = w
    end

    -- The parts of the dir list that match won't matter, so skip them
    local i = 1
    while i < #image_dirs and i < #buffer_dirs do
        if image_dirs[i] ~= buffer_dirs[i] then
            break
        else
            i = i + 1
        end
    end

    -- Append ../ to walk up from the buffer location and the path downward
    -- to the location of the image file in order to create a relative path
    local relative_path = ""
    while i <= #image_dirs or i <= #buffer_dirs do
        if i <= #image_dirs then
            if relative_path == "" then
                relative_path = image_dirs[i]
            else
                relative_path = relative_path .. sep .. image_dirs[i]
            end
        end
        if i <= #buffer_dirs - 1 then
            relative_path = ".." .. sep .. relative_path
        end
        i = i + 1
    end

    return relative_path
end

-- N/A -> N/A
-- No return, copies png image from clipboard to a new file in the vault
-- and inserts link according to configured format
-- Move to a utils/images.lua?
local function imgFromClipboard()
    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        -- Define default paste commands in case of availability
        local paste_command = {}
        paste_command["xsel"] = function(dir, filename)
            local _image_path = vim.fn.system("xsel --clipboard --output")
            local image_path = _image_path:gsub("file://", "")
            if
                vim.fn
                    .system("file --mime-type -b " .. image_path)
                    :gsub("%s+", "")
                == "image/png"
            then
                return "cp " .. image_path .. " " .. dir .. "/" .. filename
            else
                return ""
            end
        end
        paste_command["xclip"] = function(dir, filename)
            return "xclip -selection clipboard -t image/png -o > "
                .. dir
                .. "/"
                .. filename
        end
        paste_command["osascript"] = function(dir, filename)
            return string.format(
                'osascript -e "tell application \\"System Events\\" to write (the clipboard as «class PNGf») to '
                    .. '(make new file at folder \\"%s\\" with properties {name:\\"%s\\"})"',
                dir,
                filename
            )
        end
        paste_command["wl-paste"] = function(dir, filename)
            return "wl-paste -n -t image/png > " .. dir .. "/" .. filename
        end

	-- Choose a command to use
	-- First, try to set to configured command if available
	-- Otherwise, set to first default command available on user's machine
        local get_paste_command
        if paste_command[config.options.clipboard_program] ~= nil then
            if vim.fn.executable(config.options.clipboard_program) ~= 1 then
                vim.api.nvim_err_write(
                    "The clipboard program specified [`"
                        .. config.options.clipboard_program
                        .. "`] is not executable or not in your $PATH\n"
                )
            end
            get_paste_command = paste_command[config.options.clipboard_program]
        elseif vim.fn.executable("xsel") == 1 then
            get_paste_command = paste_command["xsel"]
        elseif vim.fn.executable("xclip") == 1 then
            get_paste_command = paste_command["xclip"]
        elseif vim.fn.executable("wl-paste") == 1 then
            get_paste_command = paste_command["wl-paste"]
        elseif vim.fn.executable("osascript") == 1 then
            get_paste_command = paste_command["osascript"]
        else
            vim.api.nvim_err_write(
                "No clipboard programs found!\nChecked executables: xsel, xclip, wl-paste, osascript\n"
            )
        end

        -- TODO: check `xclip -selection clipboard -t TARGETS -o` for the occurence of `image/png`

        -- using plenary.job::new():sync() with on_stdout(_, data) unfortunately did some weird ASCII translation on the
        -- data, so the PNGs were invalid. It seems like 0d 0a and single 0a bytes were stripped by the plenary job:
        --
        -- plenary job version:
        -- $ hexdump -C /tmp/x.png|head
        -- 00000000  89 50 4e 47 1a 00 00 00  49 48 44 52 00 00 03 19  |.PNG....IHDR....|
        -- 00000010  00 00 01 c1 08 02 00 00  00 8a 73 e1 c3 00 00 00  |..........s.....|
        -- 00000020  09 70 48 59 73 00 00 0e  c4 00 00 0e c4 01 95 2b  |.pHYs..........+|
        -- 00000030  0e 1b 00 00 20 00 49 44  41 54 78 9c ec dd 77 58  |.... .IDATx...wX|
        -- 00000040  14 d7 fa 07 f0 33 bb b3  4b af 0b 2c 08 22 1d 04  |.....3..K..,."..|
        -- 00000050  05 11 10 1b a2 54 c5 1e  bb b1 c6 98 c4 68 72 4d  |.....T.......hrM|
        -- 00000060  e2 cd 35 37 26 b9 49 6e  6e 7e f7 a6 98 98 a8 29  |..57&.Inn~.....)|
        -- 00000070  26 6a 8c 51 63 8b bd 00  8a 58 40 b0 81 08 2a 45  |&j.Qc....X@...*E|
        -- 00000080  69 52 17 58 ca ee b2 f5  f7 c7 ea 4a 10 66 d7 01  |iR.X.......J.f..|
        -- 00000090  b1 e4 fb 79 7c f2 2c e7  cc 39 e7 3d 67 66 b3 2f  |...y|.,..9.=gf./|
        --
        -- OK version
        -- $ hexdump -C /tmp/x2.png|head
        -- 00000000  89 50 4e 47 0d 0a 1a 0a  00 00 00 0d 49 48 44 52  |.PNG........IHDR|
        -- 00000010  00 00 03 19 00 00 01 c1  08 02 00 00 00 8a 73 e1  |..............s.|
        -- 00000020  c3 00 00 00 09 70 48 59  73 00 00 0e c4 00 00 0e  |.....pHYs.......|
        -- 00000030  c4 01 95 2b 0e 1b 00 00  20 00 49 44 41 54 78 9c  |...+.... .IDATx.|
        -- 00000040  ec dd 77 58 14 d7 fa 07  f0 33 bb b3 4b af 0b 2c  |..wX.....3..K..,|
        -- 00000050  08 22 1d 04 05 11 10 1b  a2 54 c5 1e bb b1 c6 98  |.".......T......|
        -- 00000060  c4 68 72 4d e2 cd 35 37  26 b9 49 6e 6e 7e f7 a6  |.hrM..57&.Inn~..|
        -- 00000070  98 98 a8 29 26 6a 8c 51  63 8b bd 00 8a 58 40 b0  |...)&j.Qc....X@.|
        -- 00000080  81 08 2a 45 69 52 17 58  ca ee b2 f5 f7 c7 ea 4a  |..*EiR.X.......J|
        -- 00000090  10 66 d7 01 b1 e4 fb 79  7c f2 2c e7 cc 39 e7 3d  |.f.....y|.,..9.=|

	-- Get a destination to store the image in
        local pngname = "pasted_img_" .. os.date("%Y%m%d%H%M%S") .. ".png"
        local pngdir = config.options.image_subdir
                and config.options.image_subdir
            or config.options.home
        local png = Path:new(pngdir, pngname).filename
        local relpath = make_relative_path(vim.fn.expand("%:p"), png, "/")

	-- Try to paste the image to a file and check output to verify success
        local output = vim.fn.system(get_paste_command(pngdir, pngname))
        if output ~= "" then
            -- Remove empty file created by previous command if failed
            vim.fn.system("rm " .. png)
            vim.api.nvim_err_writeln(
                string.format(
                    "Unable to write image %s.\nIs there an image on the clipboard?\nSee also issue 131",
                    png
                )
            )
        end

        -- Either insert the proper link according to config or report the error
        if fileutils.file_exists(png) then
            if config.options.image_link_style == "markdown" then
                vim.api.nvim_put({ "![](" .. relpath .. ")" }, "", true, true)
            else
                vim.api.nvim_put({ "![[" .. pngname .. "]]" }, "", true, true)
            end
        else
            vim.api.nvim_err_writeln("Unable to write image " .. png)
        end
    end)
end

-- end of image stuff

-- string, string, string, string, table, function -> N/A
-- No return, only creates a new note file from a given template file
local function create_note_from_template(
    title,
    uuid,
    filepath,
    templatefn,
    calendar_info,
    callback
)
    -- first, read the template file
    local lines = {}
    if fileutils.file_exists(templatefn) then
        for line in io.lines(templatefn) do
            lines[#lines + 1] = line
        end
    end

    -- now write the output file, substituting vars line by line
    local file_dir = filepath:match("(.*/)") or ""
    fileutils.check_dir_and_ask(
        file_dir,
        "Create weekly dir",
        function(dir_succeed)
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
        end
    )
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
local Pinfo = {
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
function Pinfo:new(opts)
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
function Pinfo:resolve_path(p, opts)
    opts = opts or {}
    opts.subdirs_in_links = opts.subdirs_in_links
        or config.options.subdirs_in_links

    self.fexists = fileutils.file_exists(p)
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

-- string, table -> table
-- Returns a Pinfo table for the given title and options
function Pinfo:resolve_link(title, opts)
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
        and fileutils.file_exists(opts.weeklies .. "/" .. self.filename)
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
        and fileutils.file_exists(opts.dailies .. "/" .. self.filename)
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
    if fileutils.file_exists(opts.home .. "/" .. self.filename) then
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
            if fileutils.file_exists(tempfn) then
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
        if ftypeok[fileutils.get_extension(fn)] then
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

-- note picker actions
-- Move to utils/files.lua? Make sure to bring table entry definitions from below
local picker_actions = {}

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
local function find_files_sorted(opts)
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

-- N/A -> N/A
-- No return. If user config auto sets filetype or syntax, actually set them
-- Keep with picker_actions definition
picker_actions.post_open = function()
    if config.options.auto_set_filetype then
        vim.cmd("set ft=telekasten")
    end
    if config.options.auto_set_syntax then
        vim.cmd("set syntax=telekasten")
    end
end

-- int -> nil? action_set.select returns result of action_set.edit, but edit doesn't return a value
-- Keep with picker_actions definition
picker_actions.select_default = function(prompt_bufnr)
    local ret = action_set.select(prompt_bufnr, "default")
    picker_actions.post_open()
    return ret
end

-- table -> function
-- Returns a configured function mapped to a key while using the picker
function picker_actions.close(opts)
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
function picker_actions.paste_tag(opts)
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
function picker_actions.yank_tag(opts)
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
function picker_actions.paste_link(opts)
    opts = opts or {}
    opts.subdirs_in_links = opts.subdirs_in_links
        or config.options.subdirs_in_links
    return function(prompt_bufnr)
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        local pinfo = Pinfo:new({
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
function picker_actions.yank_link(opts)
    return function(prompt_bufnr)
        opts = opts or {}
        opts.subdirs_in_links = opts.subdirs_in_links
            or config.options.subdirs_in_links
        if opts.close_after_yanking then
            actions.close(prompt_bufnr)
        end
        local selection = action_state.get_selected_entry()
        local pinfo = Pinfo:new({
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
function picker_actions.paste_img_link(opts)
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
function picker_actions.yank_img_link(opts)
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

--
-- FindDailyNotes:
-- ---------------
--
-- Select from daily notes
--
-- table -> N/A
-- No return. Opens a picker looking for daily notes, creating new from template if needed
-- Move to utils/files.lua? Arguably file related
local function FindDailyNotes(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking

    -- If global dir check passes, defines a picker for daily files
    -- If today's daily doesn't exist, create one from template
    -- Either way, then open the picker
    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        local today = os.date(dateutils.dateformats.date)
        local fname = config.options.dailies
            .. "/"
            .. today
            .. config.options.extension
        local fexists = fileutils.file_exists(fname)
        local function picker()
            find_files_sorted({
                prompt_title = "Find daily note",
                cwd = config.options.dailies,
                find_command = config.options.find_command,
                search_pattern = "%d%d%d%d%-%d%d%-%d%d",
                search_depth = 1,
                attach_mappings = function(_, map)
                    actions.select_default:replace(
                        picker_actions.select_default
                    )
                    map("i", "<c-y>", picker_actions.yank_link(opts))
                    map("i", "<c-i>", picker_actions.paste_link(opts))
                    map("n", "<c-y>", picker_actions.yank_link(opts))
                    map("n", "<c-i>", picker_actions.paste_link(opts))
                    map("n", "<c-c>", picker_actions.close(opts))
                    map("n", "<esc>", picker_actions.close(opts))
                    return true
                end,
                sort = config.options.sort,
            })
        end
        if
            (fexists ~= true)
            and (
                (opts.dailies_create_nonexisting == true)
                or config.options.dailies_create_nonexisting == true
            )
        then
            create_note_from_template(
                today,
                nil,
                fname,
                M.note_type_templates.daily,
                nil,
                function()
                    opts.erase = true
                    opts.erase_file = fname
                    picker()
                end
            )
            return
        end
        picker()
    end)
end

--
-- FindWeeklyNotes:
-- ---------------
--
-- Select from daily notes
--
-- table -> N/A
-- No return. Defines a picker looking for weekly notes, creating a new one from template if needed
-- Move to utils/files.lua? Arguably file related. Keep with FindDailyNotes either way.
local function FindWeeklyNotes(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking

    -- If global dir check passes, set up a picker for weekly notes
    -- If this week's note does not exist, create from template
    -- Either way, then call the picker
    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        local title = os.date(dateutils.dateformats.isoweek)
        local fname = config.options.weeklies
            .. "/"
            .. title
            .. config.options.extension
        local fexists = fileutils.file_exists(fname)

        local function picker()
            find_files_sorted({
                prompt_title = "Find weekly note",
                cwd = config.options.weeklies,
                find_command = config.options.find_command,
                search_pattern = "%d%d%d%d%-W%d+",
                search_depth = 1,
                attach_mappings = function(_, map)
                    actions.select_default:replace(
                        picker_actions.select_default
                    )
                    map("i", "<c-y>", picker_actions.yank_link(opts))
                    map("i", "<c-i>", picker_actions.paste_link(opts))
                    map("n", "<c-y>", picker_actions.yank_link(opts))
                    map("n", "<c-i>", picker_actions.paste_link(opts))
                    map("n", "<c-c>", picker_actions.close(opts))
                    map("n", "<esc>", picker_actions.close(opts))
                    return true
                end,
                sort = config.options.sort,
            })
        end

        if
            (fexists ~= true)
            and (
                (opts.weeklies_create_nonexisting == true)
                or config.options.weeklies_create_nonexisting == true
            )
        then
            create_note_from_template(
                title,
                nil,
                fname,
                M.note_type_templates.weekly,
                nil,
                function()
                    opts.erase = true
                    opts.erase_file = fname
                    picker()
                end
            )
            return
        end
        picker()
    end)
end

--
-- InsertLink:
-- -----------
--
-- Select from all notes and put a link in the current buffer
-- table -> N/A
-- No return. Sets up a picker from which users can pick a note to insert a link to
local function InsertLink(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking
    opts.subdirs_in_links = opts.subdirs_in_links
        or config.options.subdirs_in_links

    -- If global dir check passes, set up a picker for picking a note
    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        local cwd = config.options.home
        local find_command = config.options.find_command
        local sort = config.options.sort
        local attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                if selection == nil then
                    selection = { filename = action_state.get_current_line() }
                end
                local pinfo = Pinfo:new({
                    filepath = selection.filename or selection.value,
                    opts,
                })
                vim.api.nvim_put(
                    { "[[" .. pinfo.title .. "]]" },
                    "",
                    false,
                    true
                )
                if opts.i then
                    vim.api.nvim_feedkeys("a", "m", false)
                end
            end)
            map("i", "<c-y>", picker_actions.yank_link(opts))
            map("i", "<c-i>", picker_actions.paste_link(opts))
            map("n", "<c-y>", picker_actions.yank_link(opts))
            map("n", "<c-i>", picker_actions.paste_link(opts))
            map("i", "<c-cr>", picker_actions.paste_link(opts))
            map("n", "<c-cr>", picker_actions.paste_link(opts))
            return true
        end

        -- Open picker for users to chose note, preferring live grep
        if opts.with_live_grep then
            builtin.live_grep({
                prompt_title = "Insert link to note with live grep",
                cwd = cwd,
                attach_mappings = attach_mappings,
                find_command = find_command,
                sort = sort,
            })
        else
            find_files_sorted({
                prompt_title = "Insert link to note",
                cwd = cwd,
                attach_mappings = attach_mappings,
                find_command = find_command,
                sort = sort,
            })
        end
    end)
end

-- N/A -> string, number
-- Returns "tag"/"link"/nil, location's column
-- Checks if the location under the cursor is a tag or link
-- Move to utils/links.lua?
local function check_for_link_or_tag()
    local line = vim.api.nvim_get_current_line()
    local col = vim.fn.col(".")
    return taglinks.is_tag_or_link_at(line, col, config.options)
end

-- string -> N/A
-- No return. Passes the given URL to the OS's tool for handling and opening URLs
-- Move to utils/links.lua?
local function follow_url(url)
    if config.options.follow_url_fallback then
        local cmd =
            string.gsub(config.options.follow_url_fallback, "{{url}}", url)
        return vim.cmd(cmd)
    end

    -- we just leave it to the OS's handler to deal with what kind of URL it is
    local function format_command(cmd)
        return 'call jobstart(["'
            .. cmd
            .. '", "'
            .. url
            .. '"], {"detach": v:true})'
    end

    -- Choose OS-appropriate command and run it if possible
    local command
    if vim.fn.has("mac") == 1 then
        command = format_command("open")
        vim.cmd(command)
    elseif vim.fn.has("unix") then
        command = format_command("xdg-open")
        vim.cmd(command)
    else
        print("Cannot open URLs on your operating system") -- TODO: Figure out how to do this on Windows
    end
end

--
-- PreviewImg:
-- -----------
--
-- preview media
--
-- table -> N/A
-- No return. Takes text under cursor by normal yi, and if this is an image path, show it in a picker
-- USER FACING, leave in place
local function PreviewImg(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking

    -- If global dir check passes, then back up the current register "0 and yank what's under the cursor
    -- If the yanked text is a file name for a local image, present the preview in a picker
    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        local saved_reg = vim.fn.getreg('"0')
        vim.cmd("normal yi)")
        local fname = vim.fn.getreg('"0'):gsub("^img/", "")
        vim.fn.setreg('"0', saved_reg)

        -- check if fname exists anywhere
        local imageDir = config.options.image_subdir or config.options.home
        local fexists = fileutils.file_exists(imageDir .. "/" .. fname)

        if fexists == true then
            find_files_sorted({
                prompt_title = "Preview image/media",
                cwd = imageDir,
                default_text = fname,
                find_command = config.options.find_command,
                filter_extensions = config.options.media_extensions,
                preview_type = "media",
                attach_mappings = function(prompt_bufnr, map)
                    actions.select_default:replace(function()
                        actions.close(prompt_bufnr)
                    end)
                    map("i", "<c-y>", picker_actions.yank_img_link(opts))
                    map("i", "<c-i>", picker_actions.paste_img_link(opts))
                    map("n", "<c-y>", picker_actions.yank_img_link(opts))
                    map("n", "<c-i>", picker_actions.paste_img_link(opts))
                    map("i", "<c-cr>", picker_actions.paste_img_link(opts))
                    map("n", "<c-cr>", picker_actions.paste_img_link(opts))
                    return true
                end,
                sort = config.options.sort,
            })
        else
            print("File not found: " .. config.options.home .. "/" .. fname)
        end
    end)
end

--
-- BrowseImg:
-- -----------
--
-- preview media
--
-- table -> N/A
-- No return. Opens a picker filtering to only media for users to browse
-- USER FACING, leave in place
local function BrowseImg(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking

    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        find_files_sorted({
            prompt_title = "Preview image/media",
            cwd = config.options.home,
            find_command = config.options.find_command,
            filter_extensions = config.options.media_extensions,
            preview_type = "media",
            attach_mappings = function(prompt_bufnr, map)
                actions.select_default:replace(function()
                    actions.close(prompt_bufnr)
                end)
                map("i", "<c-y>", picker_actions.yank_img_link(opts))
                map("i", "<c-i>", picker_actions.paste_img_link(opts))
                map("n", "<c-y>", picker_actions.yank_img_link(opts))
                map("n", "<c-i>", picker_actions.paste_img_link(opts))
                map("i", "<c-cr>", picker_actions.paste_img_link(opts))
                map("n", "<c-cr>", picker_actions.paste_img_link(opts))
                return true
            end,
            sort = config.options.sort,
        })
    end)
end

--
-- FindFriends:
-- -----------
--
-- Find notes also linking to the link under cursor
--
-- table -> N/A
-- No return. Opens a picker filtering to only notes linking to the note linked under the cursor
-- USER FACING, leave in place
local function FindFriends(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking

    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        -- Back up register "0, yank and save link under cursor, and restore "0
        local saved_reg = vim.fn.getreg('"0')
        vim.cmd("normal yi]")
        local title = vim.fn.getreg('"0')
        vim.fn.setreg('"0', saved_reg)

        title = linkutils.remove_alias(title)
        title = title:gsub("^(%[)(.+)(%])$", "%2")

        builtin.live_grep({
            prompt_title = "Notes referencing `" .. title .. "`",
            cwd = config.options.home,
            default_text = "\\[\\[" .. title .. "([#|].+)?\\]\\]",
            find_command = config.options.find_command,
            attach_mappings = function(_, map)
                actions.select_default:replace(picker_actions.select_default)
                map("i", "<c-y>", picker_actions.yank_link(opts))
                map("i", "<c-i>", picker_actions.paste_link(opts))
                map("n", "<c-y>", picker_actions.yank_link(opts))
                map("n", "<c-i>", picker_actions.paste_link(opts))
                map("i", "<c-cr>", picker_actions.paste_link(opts))
                map("n", "<c-cr>", picker_actions.paste_link(opts))
                return true
            end,
        })
    end)
end

--
-- YankLink:
-- -----------
--
-- Create and yank a [[link]] from the current note.
--
-- N/A -> N/A, puts link to current note in unnamed register ""
-- USER FACING, leace in place
local function YankLink()
    local title = "[["
        .. Pinfo:new({ filepath = vim.fn.expand("%:p"), config.options }).title
        .. "]]"
    vim.fn.setreg('"', title)
    print("yanked " .. title)
end

-- string, string -> N/A
-- No return. Update links with name change if configured to
-- Move to utils/files.lua
local function rename_update_links(oldfile, newname)
    if config.options.rename_update_links == true then
        -- Only look for the first part of the link, so we do not touch to #heading or #^paragraph
        -- Should use regex instead to ensure it is a proper link
        local oldlink = "[[" .. oldfile.title
        local newlink = "[[" .. newname

        -- Save open buffers before looking for links to replace
        if #(vim.fn.getbufinfo({ bufmodified = 1 })) > 1 then
            vim.ui.select({ "Yes (default)", "No" }, {
                prompt = "Telekasten.nvim: "
                    .. "Save all modified buffers before updating links?",
            }, function(answer)
                if answer ~= "No" then
                    save_all_mod_buffers()
                end
            end)
        end

        recursive_substitution(config.options.home, oldlink, newlink)
        recursive_substitution(config.options.dailies, oldlink, newlink)
        recursive_substitution(config.options.weeklies, oldlink, newlink)
    end
end

--
-- RenameNote:
-- -----------
--
-- Prompt for new note title, rename the note and update all links.
--
-- N/A -> N/A
-- USER FACING, leave in place
local function RenameNote()
    local oldfile =
        Pinfo:new({ filepath = vim.fn.expand("%:p"), config.options })

    fileutils.prompt_title(
        config.options.extension,
        oldfile.title,
        function(newname)
            local newpath = newname:match("(.*/)") or ""
            newpath = config.options.home .. "/" .. newpath

            -- If no subdir specified, place the new note in the same place as old note
            if
                config.options.subdirs_in_links == true
                and newpath == config.options.home .. "/"
                and oldfile.sub_dir ~= ""
            then
                newname = oldfile.sub_dir .. "/" .. newname
            end

            local fname = config.options.home
                .. "/"
                .. newname
                .. config.options.extension
            local fexists = fileutils.file_exists(fname)
            if fexists then
                tkutils.print_error("File alreay exists. Renaming abandonned")
                return
            end

            -- Savas newfile, delete buffer of old one and remove old file
            if newname ~= "" and newname ~= oldfile.title then
                fileutils.check_dir_and_ask(
                    newpath,
                    "Renamed file",
                    function(success)
                        if not success then
                            return
                        end

                        local oldTitle = oldfile.title:gsub(" ", "\\ ")
                        vim.cmd(
                            "saveas "
                                .. config.options.home
                                .. "/"
                                .. newname
                                .. config.options.extension
                        )
                        vim.cmd(
                            "bdelete " .. oldTitle .. config.options.extension
                        )
                        os.execute(
                            "rm "
                                .. config.options.home
                                .. "/"
                                .. oldTitle
                                .. config.options.extension
                        )
                        rename_update_links(oldfile, newname)
                    end
                )
            else
                rename_update_links(oldfile, newname)
            end
        end
    )
end

--
-- GotoDate:
-- ----------
--
-- find note for date and create it if necessary.
--
-- table -> N/A
-- Move to utils/files.lua?
local function GotoDate(opts)
    opts.dates = dateutils.calculate_dates(
        opts.date_table,
        config.options.calendar_opts.calendar_monday
    )
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking
    opts.journal_auto_open = opts.journal_auto_open
        or config.options.journal_auto_open

    local word = opts.date or os.date(dateutils.dateformats.date)

    local fname = config.options.dailies
        .. "/"
        .. word
        .. config.options.extension
    local fexists = fileutils.file_exists(fname)
    local function picker()
        if opts.journal_auto_open then
            if opts.calendar == true then
                -- ensure that the calendar window is not improperly overwritten
                vim.cmd("wincmd w")
            end
            vim.cmd("e " .. fname)
        else
            find_files_sorted({
                prompt_title = "Goto day",
                cwd = config.options.dailies,
                default_text = word,
                find_command = config.options.find_command,
                attach_mappings = function(prompt_bufnr, map)
                    actions.select_default:replace(function()
                        actions.close(prompt_bufnr)

                        -- open the new note
                        if opts.calendar == true then
                            vim.cmd("wincmd w")
                        end
                        vim.cmd("e " .. fname)
                        picker_actions.post_open()
                    end)
                    map("i", "<c-y>", picker_actions.yank_link(opts))
                    map("i", "<c-i>", picker_actions.paste_link(opts))
                    map("n", "<c-y>", picker_actions.yank_link(opts))
                    map("n", "<c-i>", picker_actions.paste_link(opts))
                    map("n", "<c-c>", picker_actions.close(opts))
                    map("n", "<esc>", picker_actions.close(opts))
                    return true
                end,
            })
        end
    end

    if
        (fexists ~= true)
        and (
            (opts.dailies_create_nonexisting == true)
            or config.options.dailies_create_nonexisting == true
        )
    then
        create_note_from_template(
            word,
            nil,
            fname,
            M.note_type_templates.daily,
            opts.dates,
            function()
                opts.erase = true
                opts.erase_file = fname
                picker()
            end
        )
        return
    end

    picker()
end

--
-- GotoToday:
-- ----------
--
-- find today's daily note and create it if necessary.
--
-- table -> N/A
-- USER FACING, leave in place
local function GotoToday(opts)
    opts = opts or {}

    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        local today = os.date(dateutils.dateformats.date)
        opts.date_table = os.date("*t")
        opts.date = today
        opts.dailies_create_nonexisting = true -- Always use template for GotoToday
        GotoDate(opts)
    end)
end

--
-- FindNotes:
-- ----------
--
-- Select from notes
--
-- table -> N/A
-- USER FACING, leave in place
local function FindNotes(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking

    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        local cwd = config.options.home
        local find_command = config.options.find_command
        local sort = config.options.sort
        local attach_mappings = function(_, map)
            actions.select_default:replace(picker_actions.select_default)
            map("i", "<c-y>", picker_actions.yank_link(opts))
            map("i", "<c-i>", picker_actions.paste_link(opts))
            map("n", "<c-y>", picker_actions.yank_link(opts))
            map("n", "<c-i>", picker_actions.paste_link(opts))
            map("i", "<c-cr>", picker_actions.paste_link(opts))
            map("n", "<c-cr>", picker_actions.paste_link(opts))
            if config.options.enable_create_new then
                map("i", "<c-n>", picker_actions.create_new(opts))
                map("n", "<c-n>", picker_actions.create_new(opts))
            end
            return true
        end

        if opts.with_live_grep then
            builtin.live_grep({
                prompt_title = "Find notes by live grep",
                cwd = cwd,
                find_command = find_command,
                attach_mappings = attach_mappings,
                sort = sort,
            })
        else
            find_files_sorted({
                prompt_title = "Find notes by name",
                cwd = cwd,
                find_command = find_command,
                attach_mappings = attach_mappings,
                sort = sort,
            })
        end
    end)
end

--
-- InsertImgLink:
-- --------------
--
-- Insert link to image / media, with optional preview
--
-- table -> N/A
-- USER FACING, leave in place
local function InsertImgLink(opts)
    opts = opts or {}

    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        find_files_sorted({
            prompt_title = "Find image/media",
            cwd = config.options.home,
            find_command = config.options.find_command,
            filter_extensions = config.options.media_extensions,
            preview_type = "media",
            attach_mappings = function(prompt_bufnr, map)
                actions.select_default:replace(function()
                    actions.close(prompt_bufnr)
                    local selection = action_state.get_selected_entry()
                    local fn = selection.value
                    fn = make_relative_path(vim.fn.expand("%:p"), fn, "/")
                    vim.api.nvim_put({ "![](" .. fn .. ")" }, "", true, true)
                    if opts.i then
                        vim.api.nvim_feedkeys("A", "m", false)
                    end
                end)
                map("i", "<c-y>", picker_actions.yank_img_link(opts))
                map("i", "<c-i>", picker_actions.paste_img_link(opts))
                map("n", "<c-y>", picker_actions.yank_img_link(opts))
                map("n", "<c-i>", picker_actions.paste_img_link(opts))
                map("i", "<c-cr>", picker_actions.paste_img_link(opts))
                map("n", "<c-cr>", picker_actions.paste_img_link(opts))
                return true
            end,
            sort = config.options.sort,
        })
    end)
end

--
-- SearchNotes:
-- ------------
--
-- find the file linked to by the word under the cursor
--
-- table -> N/A
-- USER FACING, leave in place
local function SearchNotes(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking

    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        builtin.live_grep({
            prompt_title = "Search in notes",
            cwd = config.options.home,
            search_dirs = { config.options.home },
            default_text = opts.default_text or vim.fn.expand("<cword>"),
            find_command = config.options.find_command,
            attach_mappings = function(_, map)
                actions.select_default:replace(picker_actions.select_default)
                map("i", "<c-y>", picker_actions.yank_link(opts))
                map("i", "<c-i>", picker_actions.paste_link(opts))
                map("n", "<c-y>", picker_actions.yank_link(opts))
                map("n", "<c-i>", picker_actions.paste_link(opts))
                map("i", "<c-cr>", picker_actions.paste_link(opts))
                map("n", "<c-cr>", picker_actions.paste_link(opts))
                return true
            end,
        })
    end)
end

--
-- ShowBacklinks:
-- ------------
--
-- Find all notes linking to this one
--
-- table -> N/A
-- USER FACING, leave in place
local function ShowBacklinks(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking

    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        local title =
            Pinfo:new({ filepath = vim.fn.expand("%:p"), config.options }).title
        -- or vim.api.nvim_buf_get_name(0)

        local escaped_title = string.gsub(title, "%(", "\\(")
        escaped_title = string.gsub(escaped_title, "%)", "\\)")

        builtin.live_grep({
            results_title = "Backlinks to " .. title,
            prompt_title = "Search",
            cwd = config.options.home,
            search_dirs = { config.options.home },
            default_text = "\\[\\[" .. escaped_title .. "([#|].+)?\\]\\]",
            find_command = config.options.find_command,
            attach_mappings = function(_, map)
                actions.select_default:replace(picker_actions.select_default)
                map("i", "<c-y>", picker_actions.yank_link(opts))
                map("i", "<c-i>", picker_actions.paste_link(opts))
                map("n", "<c-y>", picker_actions.yank_link(opts))
                map("n", "<c-i>", picker_actions.paste_link(opts))
                map("i", "<c-cr>", picker_actions.paste_link(opts))
                map("n", "<c-cr>", picker_actions.paste_link(opts))
                return true
            end,
        })
    end)
end

--
-- CreateNoteSelectTemplate()
-- --------------------------
--
-- Prompts for title, then pops up telescope for template selection,
-- creates the new note by template and opens it
-- table, string -> N/A
-- Move? Used by CreateNoteSelectTemplate and FollowLink
local function on_create_with_template(opts, title)
    if title == nil then
        return
    end

    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking
    opts.new_note_location = opts.new_note_location
        or config.options.new_note_location
    opts.template_handling = opts.template_handling
        or config.options.template_handling
    local uuid_type = opts.uuid_type or config.options.uuid_type

    local uuid = fileutils.new_uuid(uuid_type)
    local pinfo = Pinfo:new({
        title = generate_note_filename(uuid, title),
        opts,
    })
    local fname = pinfo.filepath
    if pinfo.fexists == true then
        -- open the new note
        vim.cmd("e " .. fname)
        picker_actions.post_open()
        return
    end

    find_files_sorted({
        prompt_title = "Select template...",
        cwd = config.options.templates,
        find_command = config.options.find_command,
        attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                -- local template = config.options.templates .. "/" .. action_state.get_selected_entry().value
                local template = action_state.get_selected_entry().value
                -- TODO: pass in the calendar_info returned from the pinfo
                create_note_from_template(
                    title,
                    uuid,
                    fname,
                    template,
                    pinfo.calendar_info,
                    function()
                        -- open the new note
                        vim.cmd("e " .. fname)
                        picker_actions.post_open()
                    end
                )
            end)
            map("i", "<c-y>", picker_actions.yank_link(opts))
            map("i", "<c-i>", picker_actions.paste_link(opts))
            map("n", "<c-y>", picker_actions.yank_link(opts))
            map("n", "<c-i>", picker_actions.paste_link(opts))
            return true
        end,
    })
end

-- table -> N/A
-- No return, select template and create new note
-- USER FACING, leave in place
local function CreateNoteSelectTemplate(opts)
    opts = opts or {}

    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        -- get the current working directory
        local current_dir = vim.fn.getcwd()
        -- change the cwd to the configured home directory, so tab completion
        -- works for the folders in that directory
        vim.fn.chdir(config.options.home)
        fileutils.prompt_title(config.options.extension, nil, function(title)
            on_create_with_template(opts, title)
        end)
        -- change back to the original directory
        vim.fn.chdir(current_dir)
    end)
end

--
-- CreateNote:
-- ------------
--
-- Prompts for title and creates note with default template
--
-- table, string -> N/A
-- Move? Used in CreateNote and picker_actions.create_new
local function on_create(opts, title)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking
    opts.new_note_location = opts.new_note_location
        or config.options.new_note_location
    opts.template_handling = opts.template_handling
        or config.options.template_handling
    local uuid_type = opts.uuid_type or config.options.uuid_type

    if title == nil then
        return
    end

    local uuid = fileutils.new_uuid(uuid_type)
    local pinfo = Pinfo:new({
        title = generate_note_filename(uuid, title),
        opts,
    })
    local fname = pinfo.filepath

    local function picker()
        find_files_sorted({
            prompt_title = "Created note...",
            cwd = pinfo.root_dir,
            default_text = generate_note_filename(uuid, title),
            find_command = config.options.find_command,
            attach_mappings = function(_, map)
                actions.select_default:replace(picker_actions.select_default)
                map("i", "<c-y>", picker_actions.yank_link(opts))
                map("i", "<c-i>", picker_actions.paste_link(opts))
                map("n", "<c-y>", picker_actions.yank_link(opts))
                map("n", "<c-i>", picker_actions.paste_link(opts))
                map("n", "<c-c>", picker_actions.close(opts))
                map("n", "<esc>", picker_actions.close(opts))
                return true
            end,
        })
    end
    if pinfo.fexists ~= true then
        -- TODO: pass in the calendar_info returned in pinfo
        create_note_from_template(
            title,
            uuid,
            fname,
            pinfo.template,
            pinfo.calendar_info,
            function()
                opts.erase = true
                opts.erase_file = fname
                picker()
            end
        )
        return
    end

    picker()
end

-- table -> N/A
-- USER FACING, leave in place
local function CreateNote(opts)
    opts = opts or {}

    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        if config.options.template_handling == "always_ask" then
            return CreateNoteSelectTemplate(opts)
        end

        -- get the current working directory
        local current_dir = vim.fn.getcwd()
        -- change the cwd to the configured home directory, so tab completion
        -- works for the folders in that directory
        vim.fn.chdir(config.options.home)
        fileutils.prompt_title(config.options.extension, nil, function(title)
            on_create(opts, title)
        end)
        -- change back to the original directory
        vim.fn.chdir(current_dir)
    end)
end

--
-- FollowLink:
-- -----------
--
-- find the file linked to by the word under the cursor
--
-- table -> N/A
-- USER FACING, leave in place
local function FollowLink(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking

    opts.template_handling = opts.template_handling
        or config.options.template_handling
    opts.new_note_location = opts.new_note_location
        or config.options.new_note_location
    local uuid_type = opts.uuid_type or config.options.uuid_type

    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        local search_mode = "files"
        local title
        local filename_part = ""

        -- first: check if we're in a tag or a link
        local kind
        local globArg = ""

        if opts.follow_tag ~= nil then
            kind = "tag"
            title = opts.follow_tag
            if opts.templateDir ~= nil then
                globArg = "--glob=!" .. "**/" .. opts.templateDir .. "/*.md"
            end
        else
            kind, _ = check_for_link_or_tag()
        end

        if kind == "tag" then
            search_mode = "tag"
            if title == nil then
                local saved_reg = vim.fn.getreg('"0')
                vim.cmd("normal yiw")
                title = vim.fn.getreg('"0')
                vim.fn.setreg('"0', saved_reg)
            end
        else
            local saved_reg = vim.fn.getreg('"0')
            if kind == "link" then
                -- we are in a link
                vim.cmd("normal yi]")
                title = vim.fn.getreg('"0')
                title = title:gsub("^(%[)(.+)(%])$", "%2")
                title = title:gsub("%s*\n", " ")
                title = linkutils.remove_alias(title)
            else
                -- we are in an external [link]
                vim.cmd("normal yi)")
                local url = vim.fn.getreg('"0')
                vim.fn.setreg('"0', saved_reg)
                return follow_url(url)
            end
            vim.fn.setreg('"0', saved_reg)

            local parts = vim.split(title, "#")

            -- if there is a #
            if #parts ~= 1 then
                search_mode = "heading"
                title = parts[2]
                filename_part = parts[1]
                parts = vim.split(title, "%^")
                if #parts ~= 1 then
                    search_mode = "para"
                    title = parts[2]
                end
            end

            -- this applies to heading and para search_mode
            -- if we cannot find the file, revert to global heading search by
            -- setting filename to empty string
            if #filename_part > 0 then
                local pinfo = Pinfo:new({ title = filename_part })
                filename_part = pinfo.filepath
                if pinfo.fexists == false then
                    -- print("error")
                    filename_part = ""
                end
            end
        end

        if search_mode == "files" then
            -- check if subdir exists
            local filepath = title:match("(.*/)") or ""
            filepath = config.options.home .. "/" .. filepath
            fileutils.check_dir_and_ask(filepath, "", function()
                -- check if fname exists anywhere
                local pinfo = Pinfo:new({ title = title })
                local function picker()
                    find_files_sorted({
                        prompt_title = "Follow link to note...",
                        cwd = pinfo.root_dir,
                        default_text = title,
                        find_command = config.options.find_command,
                        attach_mappings = function(_, map)
                            actions.select_default:replace(
                                picker_actions.select_default
                            )
                            map("i", "<c-y>", picker_actions.yank_link(opts))
                            map("i", "<c-i>", picker_actions.paste_link(opts))
                            map("n", "<c-y>", picker_actions.yank_link(opts))
                            map("n", "<c-i>", picker_actions.paste_link(opts))
                            map("n", "<c-c>", picker_actions.close(opts))
                            map("n", "<esc>", picker_actions.close(opts))
                            return true
                        end,
                        sort = config.options.sort,
                    })
                end

                if
                    (pinfo.fexists ~= true)
                    and (
                        (opts.follow_creates_nonexisting == true)
                        or config.options.follow_creates_nonexisting == true
                    )
                then
                    if opts.template_handling == "always_ask" then
                        return on_create_with_template(opts, title)
                    end

                    if #pinfo.filepath > 0 then
                        local uuid = fileutils.new_uuid(uuid_type)
                        create_note_from_template(
                            title,
                            uuid,
                            pinfo.filepath,
                            pinfo.template,
                            pinfo.calendar_info,
                            function()
                                opts.erase = true
                                opts.erase_file = pinfo.filepath
                                picker()
                            end
                        )
                        return
                    end
                end

                picker()
            end)
        end

        if search_mode ~= "files" then
            local search_pattern = title
            local cwd = config.options.home

            opts.cwd = cwd
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
                local display =
                    utils.transform_path(display_opts, display_entry.value)

                display_entry.filn = display_entry.filn
                    or display:gsub(":.*", "")
                display, hl_group =
                    utils.transform_devicons(display_entry.filn, display, false)

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
                local fn = entry.filename
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

            local lookup_keys = {
                value = 1,
                ordinal = 1,
            }

            local find = (function()
                if Path.path.sep == "\\" then
                    return function(t)
                        local start, _, filn, lnum, col, text =
                            string.find(t, [[([^:]+):(%d+):(%d+):(.*)]])

                        -- Handle Windows drive letter (e.g. "C:") at the beginning (if present)
                        if start == 3 then
                            filn = string.sub(t.value, 1, 3) .. filn
                        end

                        return filn, lnum, col, text
                    end
                else
                    return function(t)
                        local _, _, filn, lnum, col, text =
                            string.find(t, [[([^:]+):(%d+):(%d+):(.*)]])
                        return filn, lnum, col, text
                    end
                end
            end)()

            local parse = function(t)
                -- print("t: ", vim.inspect(t))
                local filn, lnum, col, text = find(t.value)

                local ok
                ok, lnum = pcall(tonumber, lnum)
                if not ok then
                    lnum = nil
                end

                ok, col = pcall(tonumber, col)
                if not ok then
                    col = nil
                end

                t.filn = filn
                t.lnum = lnum
                t.col = col
                t.text = text

                return { filn, lnum, col, text }
            end

            local function entry_maker(_)
                local mt_vimgrep_entry

                opts = opts or {}

                -- local disable_devicons = opts.disable_devicons
                -- local disable_coordinates = opts.disable_coordinates or true
                local only_sort_text = opts.only_sort_text

                local execute_keys = {
                    path = function(t)
                        if Path:new(t.filename):is_absolute() then
                            return t.filename, false
                        else
                            return Path:new({ t.cwd, t.filename }):absolute(),
                                false
                        end
                    end,
                    filename = function(t)
                        return parse(t)[1], true
                    end,
                    lnum = function(t)
                        return parse(t)[2], true
                    end,
                    col = function(t)
                        return parse(t)[3], true
                    end,
                    text = function(t)
                        return parse(t)[4], true
                    end,
                }

                -- For text search only, the ordinal value is actually the text.
                if only_sort_text then
                    execute_keys.ordinal = function(t)
                        return t.text
                    end
                end

                mt_vimgrep_entry = {
                    cwd = vim.fn.expand(opts.cwd or vim.loop.cwd()),
                    __index = function(t, k)
                        local raw = rawget(mt_vimgrep_entry, k)
                        if raw then
                            return raw
                        end

                        local executor = rawget(execute_keys, k)
                        if executor then
                            local val, save = executor(t)
                            if save then
                                rawset(t, k, val)
                            end
                            return val
                        end

                        return rawget(t, rawget(lookup_keys, k))
                    end,
                }

                --
                if opts.show_link_counts then
                    mt_vimgrep_entry.display = make_display
                else
                    mt_vimgrep_entry.display = iconic_display
                end

                return function(line)
                    return setmetatable({ line }, mt_vimgrep_entry)
                end
            end

            opts.entry_maker = entry_maker(opts)

            local live_grepper = finders.new_job(
                function(prompt)
                    if not prompt or prompt == "" then
                        return nil
                    end

                    local search_command = {
                        "rg",
                        "--vimgrep",
                        "-e",
                        "^#+\\s" .. prompt,
                        "--",
                    }
                    if search_mode == "para" then
                        search_command = {
                            "rg",
                            "--vimgrep",
                            "-e",
                            "\\^" .. prompt,
                            "--",
                        }
                    end

                    if search_mode == "tag" then
                        search_command = {
                            "rg",
                            "--vimgrep",
                            globArg,
                            "-e",
                            prompt,
                            "--",
                        }
                    end

                    if #filename_part > 0 then
                        table.insert(search_command, filename_part)
                    else
                        table.insert(search_command, cwd)
                    end

                    local ret = vim.tbl_flatten({ search_command })
                    return ret
                end,
                opts.entry_maker or make_entry.gen_from_vimgrep(opts),
                opts.max_results,
                opts.cwd
            )

            -- builtin.live_grep({
            local picker = pickers.new(opts, {
                cwd = cwd,
                prompt_title = "Notes referencing `" .. title .. "`",
                default_text = search_pattern,
                initial_mode = "insert",
                -- link to specific file (a daily file): [[2021-02-22]]
                -- link to heading in specific file (a daily file): [[2021-02-22#Touchpoint]]
                -- link to heading globally [[#Touchpoint]]
                -- link to heading in specific file (a daily file): [[The cool note#^xAcSh-xxr]]
                -- link to paragraph globally [[#^xAcSh-xxr]]
                finder = live_grepper,
                previewer = conf.grep_previewer(opts),
                sorter = sorters.highlighter_only(opts),
                attach_mappings = function(_, map)
                    actions.select_default:replace(
                        picker_actions.select_default
                    )
                    map("i", "<c-y>", picker_actions.yank_link(opts))
                    map("i", "<c-i>", picker_actions.paste_link(opts))
                    map("n", "<c-y>", picker_actions.yank_link(opts))
                    map("n", "<c-i>", picker_actions.paste_link(opts))
                    map("i", "<c-cr>", picker_actions.paste_link(opts))
                    map("n", "<c-cr>", picker_actions.paste_link(opts))
                    return true
                end,
            })
            picker:find()
        end
    end)
end

--
-- GotoThisWeek:
-- -------------
--
-- find this week's weekly note and create it if necessary.
--
-- table -> N/A
-- USER FACING, leave in place
local function GotoThisWeek(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking
    opts.journal_auto_open = opts.journal_auto_open
        or config.options.journal_auto_open

    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        local dinfo = dateutils.calculate_dates(
            nil,
            config.options.calendar_opts.calendar_monday
        )
        local title = dinfo.isoweek
        local fname = config.options.weeklies
            .. "/"
            .. title
            .. config.options.extension
        local fexists = fileutils.file_exists(fname)
        local function picker()
            if opts.journal_auto_open then
                if opts.calendar == true then
                    -- ensure that the calendar window is not improperly overwritten
                    vim.cmd("wincmd w")
                end
                vim.cmd("e " .. fname)
            else
                find_files_sorted({
                    prompt_title = "Goto this week:",
                    cwd = config.options.weeklies,
                    default_text = title,
                    find_command = config.options.find_command,
                    attach_mappings = function(_, map)
                        actions.select_default:replace(
                            picker_actions.select_default
                        )
                        map("i", "<c-y>", picker_actions.yank_link(opts))
                        map("i", "<c-i>", picker_actions.paste_link(opts))
                        map("n", "<c-y>", picker_actions.yank_link(opts))
                        map("n", "<c-i>", picker_actions.paste_link(opts))
                        map("n", "<c-c>", picker_actions.close(opts))
                        map("n", "<esc>", picker_actions.close(opts))
                        return true
                    end,
                })
            end
        end

        if
            (fexists ~= true)
            and (
                (opts.weeklies_create_nonexisting == true)
                or config.options.weeklies_create_nonexisting == true
            )
        then
            create_note_from_template(
                title,
                nil,
                fname,
                M.note_type_templates.weekly,
                nil,
                function()
                    opts.erase = true
                    opts.erase_file = fname
                    picker()
                end
            )
            return
        end

        picker()
    end)
end

--
-- Calendar Stuff
-- --------------

-- return if a daily 'note exists' indicator (sign) should be displayed for a particular day
-- number, number, number -> number (0 or 1)
-- USER FACING, Leave in place
local function CalendarSignDay(day, month, year)
    local fn = config.options.dailies
        .. "/"
        .. string.format("%04d-%02d-%02d", year, month, day)
        .. config.options.extension
    if fileutils.file_exists(fn) then
        return 1
    end
    return 0
end

-- action on enter on a specific day:
-- preview in telescope, stay in calendar on cancel, open note in other window on accept
-- number, number, number, _, _ -> N/A
-- USER FACING, leave in place
local function CalendarAction(day, month, year, _, _)
    local opts = {}
    opts.date = string.format("%04d-%02d-%02d", year, month, day)
    opts.date_table = { year = year, month = month, day = day }
    opts.calendar = true
    GotoDate(opts)
end

-- table -> N/A
-- USER FACING, leave in place
local function ShowCalendar(opts)
    local defaults = {}
    defaults.cmd = "CalendarVR"
    defaults.vertical_resize = 1

    opts = opts or defaults
    vim.cmd(opts.cmd)
    if opts.vertical_resize then
        vim.cmd("vertical resize +" .. opts.vertical_resize)
    end
    vim.cmd([[
      set signcolumn=no
      set nonumber
      set norelativenumber
    ]])
end

-- set up calendar integration: forward to our lua functions
-- table -> N/A
-- No return, uses vim commands to set up the calendar
-- Move to config.lua?
local function SetupCalendar(opts)
    local defaults = config.options.calendar_opts
    opts = opts or defaults

    local cmd = [[
        function! MyCalSign(day, month, year)
            return luaeval('require("telekasten").CalendarSignDay(_A[1], _A[2], _A[3])', [a:day, a:month, a:year])
        endfunction

        function! MyCalAction(day, month, year, weekday, dir)
            " day : day
            " month : month
            " year year
            " weekday : day of week (monday=1)
            " dir : direction of calendar
            return luaeval('require("telekasten").CalendarAction(_A[1], _A[2], _A[3], _A[4], _A[5])',
                                                                 \ [a:day, a:month, a:year, a:weekday, a:dir])
        endfunction

        function! MyCalBegin()
            " too early, windown doesn't exist yet
            " cannot resize
        endfunction

        let g:calendar_sign = 'MyCalSign'
        let g:calendar_action = 'MyCalAction'
        " let g:calendar_begin = 'MyCalBegin'

        let g:calendar_mark = '{{calendar_mark}}'
        let g:calendar_weeknm = {{weeknm}}
    ]]

    for k, v in pairs(opts) do
        cmd = cmd:gsub("{{" .. k .. "}}", v)
    end
    vim.cmd(cmd)
    if opts.calendar_monday == 1 then
        vim.cmd("let g:calendar_monday = 1")
    end
end

-- table -> N/A
-- No return. Toggles todo status under the cursor
-- USER FACING, leave in place
local function ToggleTodo(opts)
    -- replace
    --       by -
    -- -     by - [ ]
    -- - [ ] by - [x]
    -- - [x] by -
    -- enter insert mode if opts.i == true
    -- if opts.v = true, then look for marks to toggle
    opts = opts or {}
    local startline = vim.api.nvim_buf_get_mark(0, "<")[1]
    local endline = vim.api.nvim_buf_get_mark(0, ">")[1]
    local cursorlinenr = vim.api.nvim_win_get_cursor(0)[1]
    -- to avoid the visual range marks not being reset when calling
    -- command from normal mode
    vim.api.nvim_buf_set_mark(0, "<", 0, 0, {})
    vim.api.nvim_buf_set_mark(0, ">", 0, 0, {})
    if startline <= 0 or endline <= 0 or opts.v ~= true then
        startline = cursorlinenr
        endline = cursorlinenr
    end
    for curlinenr = startline, endline do
        local curline =
            vim.api.nvim_buf_get_lines(0, curlinenr - 1, curlinenr, false)[1]
        local stripped = vim.trim(curline)
        local repline
        if
            vim.startswith(stripped, "- ")
            and not vim.startswith(stripped, "- [")
        then
            repline = curline:gsub("%- ", "- [ ] ", 1)
        else
            if vim.startswith(stripped, "- [ ]") then
                repline = curline:gsub("%- %[ %]", "- [x]", 1)
            else
                if vim.startswith(stripped, "- [x]") then
                    if opts.onlyTodo then
                        repline = curline:gsub("%- %[x%]", "- [ ]", 1)
                    else
                        repline = curline:gsub("%- %[x%]", "-", 1)
                    end
                else
                    repline = curline:gsub("(%S)", "- [ ] %1", 1)
                end
            end
        end
        vim.api.nvim_buf_set_lines(
            0,
            curlinenr - 1,
            curlinenr,
            false,
            { repline }
        )
        if opts.i then
            vim.api.nvim_feedkeys("A", "m", false)
        end
    end
end

-- table -> N/A
-- USER FACING, leave in place
local function FindAllTags(opts)
    opts = opts or {}
    local i = opts.i
    opts.cwd = config.options.home
    opts.tag_notation = config.options.tag_notation
    local templateDir = Path:new(config.options.templates)
        :make_relative(config.options.home)
    opts.templateDir = templateDir
    opts.rg_pcre = config.options.rg_pcre

    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        local tag_map = tagutils.do_find_all_tags(opts)
        local taglist = {}

        local max_tag_len = 0
        for k, v in pairs(tag_map) do
            taglist[#taglist + 1] = { tag = k, details = v }
            if #k > max_tag_len then
                max_tag_len = #k
            end
        end

        if config.options.show_tags_theme == "get_cursor" then
            opts = themes.get_cursor({
                layout_config = {
                    height = math.min(math.floor(vim.o.lines * 0.8), #taglist),
                },
            })
        elseif config.options.show_tags_theme == "ivy" then
            opts = themes.get_ivy({
                layout_config = {
                    prompt_position = "top",
                    height = math.min(math.floor(vim.o.lines * 0.8), #taglist),
                },
            })
        else
            opts = themes.get_dropdown({
                layout_config = {
                    prompt_position = "top",
                    height = math.min(math.floor(vim.o.lines * 0.8), #taglist),
                },
            })
        end
        -- re-apply
        opts.cwd = config.options.home
        opts.tag_notation = config.options.tag_notation
        opts.i = i
        pickers
            .new(opts, {
                prompt_title = "Tags",
                finder = finders.new_table({
                    results = taglist,
                    entry_maker = function(entry)
                        return {
                            value = entry,
                            -- display = entry.tag .. ' \t (' .. #entry.details .. ' matches)',
                            display = string.format(
                                "%" .. max_tag_len .. "s ... (%3d matches)",
                                entry.tag,
                                #entry.details
                            ),
                            ordinal = entry.tag,
                        }
                    end,
                }),
                sorter = conf.generic_sorter(opts),
                attach_mappings = function(prompt_bufnr, map)
                    actions.select_default:replace(function()
                        -- actions for insert tag, default action: search for tag
                        local selection =
                            action_state.get_selected_entry().value.tag
                        local follow_opts = {
                            follow_tag = selection,
                            show_link_counts = false,
                            templateDir = templateDir,
                        }
                        actions._close(prompt_bufnr, false)
                        vim.schedule(function()
                            FollowLink(follow_opts)
                        end)
                    end)
                    map("i", "<c-y>", picker_actions.yank_tag(opts))
                    map("i", "<c-i>", picker_actions.paste_tag(opts))
                    map("n", "<c-y>", picker_actions.yank_tag(opts))
                    map("n", "<c-i>", picker_actions.paste_tag(opts))
                    map("n", "<c-c>", picker_actions.close(opts))
                    map("n", "<esc>", picker_actions.close(opts))
                    return true
                end,
            })
            :find()
    end)
end

-- Setup(cfg)
--
-- Overrides config with elements from cfg. See top of file for defaults.
--
-- table -> N/A
-- Maybe fold into _setup? Also used in chdir, though...
local function Setup(cfg)
    cfg = cfg or {}

    -- Setup base user configuration and apply it, use default automatically for
    -- the rest
    config.setup(cfg)

    -- Temporary shortcut to remove
    M.note_type_templates = {
        normal = config.options.template_new_note,
        daily = config.options.template_new_daily,
        weekly = config.options.template_new_weekly,
    }

    -- TODO: this is obsolete:
    -- But still used somehow. Maybe we could use Plenary.scan_dir?
    if vim.fn.executable("rg") == 1 then
        config.options.find_command = { "rg", "--files", "--sortr", "created" }
    else
        config.options.find_command = nil
    end

    -- this looks a little messy
    if config.options.plug_into_calendar then
        cfg.calendar_opts = cfg.calendar_opts or {}
        config.options.calendar_opts = config.options.calendar_opts or {}
        config.options.calendar_opts.weeknm = cfg.calendar_opts.weeknm
            or config.options.calendar_opts.weeknm
            or 1
        config.options.calendar_opts.calendar_monday = cfg.calendar_opts.calendar_monday
            or config.options.calendar_opts.calendar_monday
            or 1
        config.options.calendar_opts.calendar_mark = cfg.calendar_opts.calendar_mark
            or config.options.calendar_opts.calendar_mark
            or "left-fit"
        SetupCalendar(config.options.calendar_opts)
    end

    -- setup extensions to filter for
    config.options.filter_extensions = cfg.filter_extensions
        or { config.options.extension }

    -- provide fake filenames for template loading to fail silently if template is configured off
    config.options.template_new_note = config.options.template_new_note
        or "none"
    config.options.template_new_daily = config.options.template_new_daily
        or "none"
    config.options.template_new_weekly = config.options.template_new_weekly
        or "none"

    -- refresh templates
    M.note_type_templates = {
        normal = config.options.template_new_note,
        daily = config.options.template_new_daily,
        weekly = config.options.template_new_weekly,
    }

    -- for previewers to pick up our syntax, we need to tell plenary to override `.md` with our syntax
    if config.options.auto_set_filetype or config.options.auto_set_syntax then
        filetype.add_file("telekasten")
    end
    -- setting the syntax moved into plugin/telekasten.vim
    -- and does not work

    if config.options.take_over_my_home == true then
        if config.options.auto_set_filetype then
            vim.cmd(
                "au BufEnter "
                    .. config.options.home
                    .. "/*"
                    .. config.options.extension
                    .. " set ft=telekasten"
            )
        end
    end

    -- Convert all directories in full path
    config.options.image_subdir =
        make_config_path_absolute(config.options.image_subdir)
    config.options.dailies = make_config_path_absolute(config.options.dailies)
    config.options.weeklies = make_config_path_absolute(config.options.weeklies)
    config.options.templates =
        make_config_path_absolute(config.options.templates)

    -- Check if ripgrep is compiled with --pcre
    -- ! This will need to be fixed when neovim moves to lua >=5.2 by the following:
    -- config.options.rg_pcre = os.execute("echo 'hello' | rg --pcr2 hello &> /dev/null") or false

    config.options.rg_pcre = false
    local has_pcre =
        os.execute("echo 'hello' | rg --pcre2 hello > /dev/null 2>&1")
    if has_pcre == 0 then
        config.options.rg_pcre = true
    end
    config.options.media_previewer = config.options.media_previewer
    config.options.media_extensions = config.options.media_extensions
end

-- table -> N/A
-- USER FACING, leave in place
local function _setup(cfg)
    if cfg.vaults ~= nil and cfg.default_vault ~= nil then
        M.vaults = cfg.vaults
        cfg.vaults = nil
        Setup(M.vaults[cfg.default_vault])
    elseif cfg.vaults ~= nil and cfg.vaults["default"] ~= nil then
        M.vaults = cfg.vaults
        cfg.vaults = nil
        Setup(M.vaults["default"])
    elseif cfg.home ~= nil then
        M.vaults = cfg.vaults or {}
        cfg.vaults = nil
        M.vaults["default"] = cfg
        Setup(cfg)
    end
end

-- table -> N/A
-- USER FACING, leave in place
local function ChangeVault(opts)
    tkpickers.vaults(M, opts)
end

-- table -> N/A
-- USER FACING, leave in place
local function chdir(cfg)
    Setup(cfg)
end

-- Define all user facing functions
M.find_notes = FindNotes
M.find_daily_notes = FindDailyNotes
M.search_notes = SearchNotes
M.insert_link = InsertLink
M.follow_link = FollowLink
M.setup = _setup
M.goto_today = GotoToday
M.new_note = CreateNote
M.goto_thisweek = GotoThisWeek
M.find_weekly_notes = FindWeeklyNotes
M.yank_notelink = YankLink
M.rename_note = RenameNote
M.new_templated_note = CreateNoteSelectTemplate
M.show_calendar = ShowCalendar
M.CalendarSignDay = CalendarSignDay
M.CalendarAction = CalendarAction
M.paste_img_and_link = imgFromClipboard
M.toggle_todo = ToggleTodo
M.show_backlinks = ShowBacklinks
M.find_friends = FindFriends
M.insert_img_link = InsertImgLink
M.preview_img = PreviewImg
M.browse_media = BrowseImg
M.taglinks = taglinks
M.show_tags = FindAllTags
M.switch_vault = ChangeVault
M.chdir = chdir

-- Telekasten command, completion
-- Move above definition of user facing functions just above
local TelekastenCmd = {
    commands = function()
        return {
            { "find notes", "find_notes", M.find_notes },
            { "find daily notes", "find_daily_notes", M.find_daily_notes },
            { "search in notes", "search_notes", M.search_notes },
            { "insert link", "insert_link", M.insert_link },
            { "follow link", "follow_link", M.follow_link },
            { "goto today", "goto_today", M.goto_today },
            { "new note", "new_note", M.new_note },
            { "goto thisweek", "goto_thisweek", M.goto_thisweek },
            { "find weekly notes", "find_weekly_notes", M.find_weekly_notes },
            { "yank link to note", "yank_notelink", M.yank_notelink },
            { "rename note", "rename_note", M.rename_note },
            {
                "new templated note",
                "new_templated_note",
                M.new_templated_note,
            },
            { "show calendar", "show_calendar", M.show_calendar },
            {
                "paste image from clipboard",
                "paste_img_and_link",
                M.paste_img_and_link,
            },
            { "toggle todo", "toggle_todo", M.toggle_todo },
            { "show backlinks", "show_backlinks", M.show_backlinks },
            { "find friend notes", "find_friends", M.find_friends },
            {
                "browse images, insert link",
                "insert_img_link",
                M.insert_img_link,
            },
            { "preview image under cursor", "preview_img", M.preview_img },
            { "browse media", "browse_media", M.browse_media },
            { "panel", "panel", M.panel },
            { "show tags", "show_tags", M.show_tags },
            { "switch vault", "switch_vault", M.switch_vault },
        }
    end,
}

-- string -> N/A
-- Keep with TelekastenCmd just above
TelekastenCmd.command = function(subcommand)
    local show = function(opts)
        opts = opts or {}
        pickers
            .new(opts, {
                prompt_title = "Command palette",
                finder = finders.new_table({
                    results = TelekastenCmd.commands(),
                    entry_maker = function(entry)
                        return {
                            value = entry,
                            display = entry[1],
                            ordinal = entry[2],
                        }
                    end,
                }),
                sorter = conf.generic_sorter(opts),
                attach_mappings = function(prompt_bufnr, _)
                    actions.select_default:replace(function()
                        -- important: actions.close(bufnr) is not enough
                        -- it resulted in: preview_img NOT receiving the prompt as default text
                        -- apparently it has sth to do with keeping insert mode
                        actions._close(prompt_bufnr, true)

                        local selection =
                            action_state.get_selected_entry().value[3]
                        selection()
                    end)
                    return true
                end,
            })
            :find()
    end
    if subcommand then
        -- print("trying subcommand " .. "`" .. subcommand .. "`")
        for _, entry in pairs(TelekastenCmd.commands()) do
            if entry[2] == subcommand then
                local selection = entry[3]
                selection()
                return
            end
        end
        print("No such subcommand: `" .. subcommand .. "`")
    else
        local theme

        if config.options.command_palette_theme == "ivy" then
            theme = themes.get_ivy()
        else
            theme = themes.get_dropdown({
                layout_config = { prompt_position = "top" },
            })
        end
        show(theme)
    end
end

-- table -> function
-- Keep with other picker_actions
function picker_actions.create_new(opts)
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

-- nvim completion function for completing :Telekasten sub-commands
-- N/A -> [string]
-- Keep with TelekastenCmd above
TelekastenCmd.complete = function()
    local candidates = {}
    for k, v in pairs(TelekastenCmd.commands()) do
        candidates[k] = v[2]
    end
    return candidates
end

M.panel = TelekastenCmd.command
M.Command = TelekastenCmd

return M
