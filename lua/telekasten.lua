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
local taglinks = require("taglinks.taglinks")
local tagutils = require("taglinks.tagutils")
local linkutils = require("taglinks.linkutils")
local Path = require("plenary.path")

-- declare locals for the nvim api stuff to avoid more lsp warnings
local vim = vim

-- ----------------------------------------------------------------------------
-- DEFAULT CONFIG
-- ----------------------------------------------------------------------------
local home = vim.fn.expand("~/zettelkasten")
local M = {}

M.Cfg = {
    home = home,

    -- if true, telekasten will be enabled when opening a note within the configured home
    take_over_my_home = true,

    dailies = home .. "/" .. "daily",
    weeklies = home .. "/" .. "weekly",
    templates = home .. "/" .. "templates",

    -- image subdir for pasting
    -- subdir name
    -- or nil if pasted images shouldn't go into a special subdir
    image_subdir = nil,

    -- markdown file extension
    extension = ".md",

    -- following a link to a non-existing note will create it
    follow_creates_nonexisting = true,
    dailies_create_nonexisting = true,
    weeklies_create_nonexisting = true,

    -- templates for new notes
    -- template_new_note = home .. "/" .. "templates/new_note.md",
    -- template_new_daily = home .. "/" .. "templates/daily_tk.md",
    -- template_new_weekly = home .. "/" .. "templates/weekly_tk.md",

    -- image link style
    -- wiki:     ![[image name]]
    -- markdown: ![](image_subdir/xxxxx.png)
    image_link_style = "markdown",

    -- when linking to a note in subdir/, create a [[subdir/title]] link
    -- instead of a [[title only]] link
    subdirs_in_links = true,

    -- integrate with calendar-vim
    plug_into_calendar = true,
    calendar_opts = {
        -- calendar week display mode: 1 .. 'WK01', 2 .. 'WK 1', 3 .. 'KW01', 4 .. 'KW 1', 5 .. '1'
        weeknm = 4,
        -- use monday as first day of week: 1 .. true, 0 .. false
        calendar_monday = 1,
        -- calendar mark: where to put mark for marked days: 'left', 'right', 'left-fit'
        calendar_mark = "left-fit",
    },
    close_after_yanking = false,
    insert_after_inserting = true,

    -- tag notation: '#tag', ':tag:', 'yaml-bare'
    tag_notation = "#tag",

    -- command palette theme: dropdown (window) or ivy (bottom panel)
    command_palette_theme = "ivy",

    -- tag list theme:
    -- get_cursor: small tag list at cursor; ivy and dropdown like above
    show_tags_theme = "ivy",
}

local function file_exists(fname)
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

-- ----------------------------------------------------------------------------
-- image stuff
local function imgFromClipboard()
    if vim.fn.executable("xclip") == 0 then
        vim.api.nvim_err_write("No xclip installed!\n")
        return
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

    local pngname = "pasted_img_" .. os.date("%Y%m%d%H%M%S") .. ".png"
    local pngpath = M.Cfg.home
    local relpath = pngname

    if M.Cfg.image_subdir then
        relpath = M.Cfg.image_subdir .. "/" .. pngname
        pngpath = M.Cfg.home .. "/" .. M.Cfg.image_subdir
    end
    pngpath = pngpath .. "/" .. pngname

    os.execute("xclip -selection clipboard -t image/png -o > " .. pngpath)
    if file_exists(pngpath) then
        if M.Cfg.image_link_style == "markdown" then
            vim.api.nvim_put({ "![](" .. relpath .. ")" }, "", true, true)
        else
            vim.api.nvim_put({ "![[" .. pngname .. "]]" }, "", true, true)
        end
    end
end
-- end of image stuff

M.note_type_templates = {
    normal = M.Cfg.template_new_note,
    daily = M.Cfg.template_new_daily,
    weekly = M.Cfg.template_new_weekly,
}

local function daysuffix(day)
    if (day == "1") or (day == "21") or (day == "31") then
        return "st"
    end
    if (day == "2") or (day == "22") then
        return "nd"
    end
    if (day == "3") or (day == "33") then
        return "rd"
    end
    return "th"
end

local daymap = {
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",
    "Sunday",
}
local monthmap = {
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
}

local dateformats = {
    date = "%Y-%m-%d",
    week = "%V",
    isoweek = "%Y-W%V",
}

local function calculate_dates(date)
    local time = os.time(date)
    local dinfo = os.date("*t", time) -- this normalizes the input to a full date table
    local oneday = 24 * 60 * 60 -- hours * days * seconds
    local oneweek = 7 * oneday
    local oneyear = 365 * oneday
    local df = dateformats

    local dates = {}

    -- this is to compensate for the calendar showing M-Su, but os.date Su is
    -- always wday = 1
    local wday = dinfo.wday - 1
    if wday == 0 then
        wday = 7
    end

    dates.year = dinfo.year
    dates.month = dinfo.month
    dates.day = dinfo.day
    dates.hdate = daymap[wday]
        .. ", "
        .. monthmap[dinfo.month]
        .. " "
        .. dinfo.day
        .. daysuffix(dinfo.day)
        .. ", "
        .. dinfo.year

    dates.date = os.date(df.date, time)
    dates.prevday = os.date(df.date, time - oneday)
    dates.nextday = os.date(df.date, time + oneday)
    dates.week = os.date(df.week, time)
    dates.prevweek = os.date(df.week, time - oneweek)
    dates.nextweek = os.date(df.week, time + oneweek)
    dates.isoweek = os.date(df.isoweek, time)
    dates.isoprevweek = os.date(df.isoweek, time - oneweek)
    dates.isonextweek = os.date(df.isoweek, time + oneweek)

    -- things get a bit hairy at the year rollover.  W01 only starts the first week ofs
    -- January if it has more than 3 days. Partial weeks with less than 4 days are
    -- considered W52, but os.date still sets the year as the new year, so Jan 1 2022
    -- would appear as being in 2022-W52.  That breaks linear linking respective
    -- of next/prev week, so we want to put the days of that partial week in
    -- January in 2021-W52.  This tweak will only change the ISO formatted week string.
    if dates.week == 52 and dates.month == 1 then
        dates.isoweek = os.date(df.isoweek, time - oneyear)
    end

    -- Find the Sunday that started this week regardless of the calendar
    -- display preference.  Then use that as the base to calculate the dates
    -- for the days of the current week.
    -- Finally, adjust Sunday to suit user calendar preference.
    local starting_sunday = time - (wday * oneday)
    local sunday_offset = 0
    if M.Cfg.calendar_opts.calendar_monday == 1 then
        sunday_offset = 7
    end
    dates.monday = os.date(df.date, starting_sunday + (1 * oneday))
    dates.tuesday = os.date(df.date, starting_sunday + (2 * oneday))
    dates.wednesday = os.date(df.date, starting_sunday + (3 * oneday))
    dates.thursday = os.date(df.date, starting_sunday + (4 * oneday))
    dates.friday = os.date(df.date, starting_sunday + (5 * oneday))
    dates.saturday = os.date(df.date, starting_sunday + (6 * oneday))
    dates.sunday = os.date(df.date, starting_sunday + (sunday_offset * oneday))

    return dates
end

local function linesubst(line, title, dates)
    if dates == nil then
        dates = calculate_dates()
    end

    local substs = {
        hdate = dates.hdate,
        week = dates.week,
        date = dates.date,
        isoweek = dates.isoweek,
        year = dates.year,

        prevday = dates.prevday,
        nextday = dates.nextday,
        prevweek = dates.prevweek,
        nextweek = dates.nextweek,
        isoprevweek = dates.isoprevweek,
        isonextweek = dates.isonextweek,

        sunday = dates.sunday,
        monday = dates.monday,
        tuesday = dates.tuesday,
        wednesday = dates.wednesday,
        thursday = dates.thursday,
        friday = dates.friday,
        saturday = dates.saturday,

        title = title,
    }
    for k, v in pairs(substs) do
        line = line:gsub("{{" .. k .. "}}", v)
    end

    return line
end

local function create_note_from_template(
    title,
    filepath,
    templatefn,
    calendar_info
)
    -- first, read the template file
    local lines = {}
    if file_exists(templatefn) then
        for line in io.lines(templatefn) do
            lines[#lines + 1] = line
        end
    end

    -- now write the output file, substituting vars line by line
    local ofile = io.open(filepath, "a")
    for _, line in pairs(lines) do
        ofile:write(linesubst(line, title, calendar_info) .. "\n")
    end

    ofile:close()
end

local function num_path_elems(p)
    return #vim.split(p, "/")
end

local function path_to_linkname(p, opts)
    local ln

    opts = opts or {}
    opts.subdirs_in_links = opts.subdirs_in_links or M.Cfg.subdirs_in_links

    local special_dir = false
    if
        M.Cfg.dailies
        and num_path_elems(p:gsub(M.Cfg.dailies .. "/", "")) == 1
    then
        ln = p:gsub(M.Cfg.dailies .. "/", "")
        special_dir = true
    end

    if
        M.Cfg.weeklies
        and num_path_elems(p:gsub(M.Cfg.weeklies .. "/", "")) == 1
    then
        ln = p:gsub(M.Cfg.weeklies .. "/", "")
        special_dir = true
    end

    if special_dir == false then
        ln = p:gsub(M.Cfg.home .. "/", "")
    end

    if not opts.subdirs_in_links then
        -- strip all subdirs
        local pp = Path:new(ln)
        local splits = pp:_split()
        ln = splits[#splits]
    end

    local title = vim.split(ln, M.Cfg.extension)
    title = title[1]
    return title
end

local function order_numeric(a, b)
    return a > b
end

-- local function endswith(s, ending)
-- 	return ending == "" or s:sub(-#ending) == ending
-- end

local function file_extension(fname)
    return fname:match("^.+(%..+)$")
end

local function filter_filetypes(flist, ftypes)
    local new_fl = {}
    ftypes = ftypes or { M.Cfg.extension }

    local ftypeok = {}
    for _, ft in pairs(ftypes) do
        ftypeok[ft] = true
    end

    for _, fn in pairs(flist) do
        if ftypeok[file_extension(fn)] then
            table.insert(new_fl, fn)
        end
    end
    return new_fl
end

local sourced_file = debug_utils.sourced_filepath()
M.base_directory = vim.fn.fnamemodify(sourced_file, ":h:h:h")
local media_files_base_directory = M.base_directory
    .. "/telescope-media-files.nvim"
local defaulter = utils.make_default_callable
local media_preview = defaulter(function(opts)
    local preview_cmd = media_files_base_directory .. "/scripts/vimg"
    if vim.fn.executable(preview_cmd) == 0 then
        print("Previewer not found: " .. preview_cmd)
        return conf.file_previewer(opts)
    end
    return previewers.new_termopen_previewer({
        get_command = opts.get_command or function(entry)
            local tmp_table = vim.split(entry.value, "\t")
            local preview = opts.get_preview_window()
            opts.cwd = opts.cwd and vim.fn.expand(opts.cwd) or vim.loop.cwd()
            if vim.tbl_isempty(tmp_table) then
                return { "echo", "" }
            end
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
local function find_files_sorted(opts)
    opts = opts or {}

    local file_list = scan.scan_dir(opts.cwd, {})
    local filter_extensions = opts.filter_extensions or M.Cfg.filter_extensions
    file_list = filter_filetypes(file_list, filter_extensions)
    table.sort(file_list, order_numeric)

    local counts = nil
    if opts.show_link_counts then
        counts = linkutils.generate_backlink_map(M.Cfg)
    end

    -- display with devicons
    local function iconic_display(display_entry)
        local display_opts = {
            path_display = function(_, e)
                return e:gsub(opts.cwd .. "/", "")
            end,
        }

        local hl_group
        local display = utils.transform_path(display_opts, display_entry.value)

        display, hl_group = utils.transform_devicons(
            display_entry.value,
            display,
            false
        )

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

picker_actions.post_open = function()
    vim.cmd("set ft=telekasten")
end

picker_actions.select_default = function(prompt_bufnr)
    local ret = action_set.select(prompt_bufnr, "default")
    picker_actions.post_open()
    return ret
end

function picker_actions.close(opts)
    opts = opts or {}
    return function(prompt_bufnr)
        actions.close(prompt_bufnr)
        if opts.erase then
            if file_exists(opts.erase_file) then
                vim.fn.delete(opts.erase_file)
            end
        end
    end
end

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

function picker_actions.paste_link(opts)
    opts = opts or {}
    opts.subdirs_in_links = opts.subdirs_in_links or M.Cfg.subdirs_in_links
    return function(prompt_bufnr)
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        local fn = path_to_linkname(selection.value, opts)
        local title = "[[" .. fn .. "]]"
        vim.api.nvim_put({ title }, "", true, true)
        if opts.insert_after_inserting or opts.i then
            vim.api.nvim_feedkeys("A", "m", false)
        end
    end
end

function picker_actions.yank_link(opts)
    return function(prompt_bufnr)
        opts = opts or {}
        opts.subdirs_in_links = opts.subdirs_in_links or M.Cfg.subdirs_in_links
        if opts.close_after_yanking then
            actions.close(prompt_bufnr)
        end
        local selection = action_state.get_selected_entry()
        local fn = path_to_linkname(selection.value, opts)
        local title = "[[" .. fn .. "]]"
        vim.fn.setreg('"', title)
        print("yanked " .. title)
    end
end

function picker_actions.paste_img_link(opts)
    return function(prompt_bufnr)
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        local fn = selection.value
        fn = fn:gsub(M.Cfg.home .. "/", "")
        local imglink = "![](" .. fn .. ")"
        vim.api.nvim_put({ imglink }, "", true, true)
        if opts.insert_after_inserting or opts.i then
            vim.api.nvim_feedkeys("A", "m", false)
        end
    end
end

function picker_actions.yank_img_link(opts)
    return function(prompt_bufnr)
        opts = opts or {}
        if opts.close_after_yanking then
            actions.close(prompt_bufnr)
        end
        local selection = action_state.get_selected_entry()
        local fn = selection.value
        fn = fn:gsub(M.Cfg.home .. "/", "")
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
local function FindDailyNotes(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or M.Cfg.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or M.Cfg.close_after_yanking

    local today = os.date(dateformats.date)
    local fname = M.Cfg.dailies .. "/" .. today .. M.Cfg.extension
    local fexists = file_exists(fname)
    if
        (fexists ~= true)
        and (
            (opts.dailies_create_nonexisting == true)
            or M.Cfg.dailies_create_nonexisting == true
        )
    then
        create_note_from_template(today, fname, M.note_type_templates.daily)
        opts.erase = true
        opts.erase_file = fname
    end

    find_files_sorted({
        prompt_title = "Find daily note",
        cwd = M.Cfg.dailies,
        find_command = M.Cfg.find_command,
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

--
-- FindWeeklyNotes:
-- ---------------
--
-- Select from daily notes
--
local function FindWeeklyNotes(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or M.Cfg.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or M.Cfg.close_after_yanking

    local title = os.date(dateformats.isoweek)
    local fname = M.Cfg.weeklies .. "/" .. title .. M.Cfg.extension
    local fexists = file_exists(fname)
    if
        (fexists ~= true)
        and (
            (opts.weeklies_create_nonexisting == true)
            or M.Cfg.weeklies_create_nonexisting == true
        )
    then
        create_note_from_template(title, fname, M.note_type_templates.weekly)
        opts.erase = true
        opts.erase_file = fname
    end

    find_files_sorted({
        prompt_title = "Find weekly note",
        cwd = M.Cfg.weeklies,
        find_command = M.Cfg.find_command,
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

--
-- InsertLink:
-- -----------
--
-- Select from all notes and put a link in the current buffer
--
local function InsertLink(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or M.Cfg.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or M.Cfg.close_after_yanking
    opts.subdirs_in_links = opts.subdirs_in_links or M.Cfg.subdirs_in_links

    find_files_sorted({
        prompt_title = "Insert link to note",
        cwd = M.Cfg.home,
        attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                local fn = path_to_linkname(selection.value, opts)
                vim.api.nvim_put({ "[[" .. fn .. "]]" }, "", true, true)
                if opts.i then
                    vim.api.nvim_feedkeys("A", "m", false)
                end
            end)
            map("i", "<c-y>", picker_actions.yank_link(opts))
            map("i", "<c-i>", picker_actions.paste_link(opts))
            map("n", "<c-y>", picker_actions.yank_link(opts))
            map("n", "<c-i>", picker_actions.paste_link(opts))
            map("i", "<c-cr>", picker_actions.paste_link(opts))
            map("n", "<c-cr>", picker_actions.paste_link(opts))
            return true
        end,
        find_command = M.Cfg.find_command,
    })
end

local function resolve_link(title)
    local fexists = false
    local filename = title .. M.Cfg.extension
    filename = filename:gsub("^%./", "") -- strip potential leading ./
    local best_root = M.Cfg.home

    if M.Cfg.weeklies and file_exists(M.Cfg.weeklies .. "/" .. filename) then
        filename = M.Cfg.weeklies .. "/" .. filename
        fexists = true
        best_root = M.Cfg.weeklies
    end
    if M.Cfg.dailies and file_exists(M.Cfg.dailies .. "/" .. filename) then
        filename = M.Cfg.dailies .. "/" .. filename
        fexists = true
        best_root = M.Cfg.dailies
    end
    if file_exists(M.Cfg.home .. "/" .. filename) then
        filename = M.Cfg.home .. "/" .. filename
        fexists = true
    end

    if fexists == false then
        -- now search for it in all subdirs
        local subdirs = scan.scan_dir(M.Cfg.home, { only_dirs = true })
        local tempfn
        for _, folder in pairs(subdirs) do
            tempfn = folder .. "/" .. filename
            -- [[testnote]]
            if file_exists(tempfn) then
                filename = tempfn
                fexists = true
                -- print("Found: " .. filename)
                break
            end
        end
    end

    if fexists == false then
        -- default fn for creation
        filename = M.Cfg.home .. "/" .. filename
    end
    return fexists, filename, best_root
end

-- local function check_for_link_or_tag()
local function check_for_link_or_tag()
    local line = vim.api.nvim_get_current_line()
    local col = vim.fn.col(".")
    return taglinks.is_tag_or_link_at(line, col, M.Cfg)
end

local function follow_url(url)
    -- we just leave it to the OS's handler to deal with what kind of URL it is
    local function format_command(cmd)
        return 'call jobstart(["'
            .. cmd
            .. '", "'
            .. url
            .. '"], {"detach": v:true})'
    end

    local command
    if vim.fn.has("mac") == 1 then
        command = format_command("open")
        vim.cmd(command)
    elseif vim.fn.has("unix") then
        command = format_command("xdg-open")
        vim.cmd(command)
    else
        print("Cannot open URLs on your operating system")
    end
end

--
-- FollowLink:
-- -----------
--
-- find the file linked to by the word under the cursor
--
local function FollowLink(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or M.Cfg.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or M.Cfg.close_after_yanking

    local search_mode = "files"
    local title
    local filename = ""
    local fexists

    -- first: check if we're in a tag or a link
    local kind, atcol, tag
    local best_root

    if opts.follow_tag ~= nil then
        kind = "tag"
        tag = opts.follow_tag
    else
        kind, atcol = check_for_link_or_tag()
    end

    if kind == "tag" then
        if atcol ~= nil then
            tag = taglinks.get_tag_at(
                vim.api.nvim_get_current_line(),
                atcol,
                M.Cfg
            )
        end
        search_mode = "tag"
        title = tag
    else
        if kind == "link" then
            -- we are in a link
            vim.cmd("normal yi]")
            title = vim.fn.getreg('"0')
            title = title:gsub("^(%[)(.+)(%])$", "%2")
        else
            -- we are in an external [link]
            vim.cmd("normal yi)")
            local url = vim.fn.getreg('"0')
            return follow_url(url)
        end

        local parts = vim.split(title, "#")

        -- if there is a #
        if #parts ~= 1 then
            search_mode = "heading"
            title = parts[2]
            filename = parts[1]
            parts = vim.split(title, "%^")
            if #parts ~= 1 then
                search_mode = "para"
                title = parts[2]
            end
        end
        if #filename > 0 then
            fexists, filename, _ = resolve_link(filename)
            if fexists == false then
                -- print("error")
                filename = ""
            end
        end
    end

    if search_mode == "files" then
        -- check if fname exists anywhere
        fexists, filename, best_root = resolve_link(title)
        if
            (fexists ~= true)
            and (
                (opts.follow_creates_nonexisting == true)
                or M.Cfg.follow_creates_nonexisting == true
            )
        then
            create_note_from_template(
                title,
                filename,
                M.note_type_templates.normal
            )
            opts.erase = true
            opts.erase_file = filename
        end

        find_files_sorted({
            prompt_title = "Follow link to note...",
            cwd = best_root,
            default_text = title,
            find_command = M.Cfg.find_command,
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

    if search_mode ~= "files" then
        local search_pattern = title
        local cwd = M.Cfg.home

        opts.cwd = cwd
        local counts = nil
        if opts.show_link_counts then
            counts = linkutils.generate_backlink_map(M.Cfg)
        end

        -- display with devicons
        local function iconic_display(display_entry)
            local display_opts = {
                path_display = function(_, e)
                    return e:gsub(opts.cwd .. "/", "")
                end,
            }

            local hl_group
            local display = utils.transform_path(
                display_opts,
                display_entry.value
            )

            display_entry.filn = display_entry.filn or display:gsub(":.*", "")
            display, hl_group = utils.transform_devicons(
                display_entry.filn,
                display,
                false
            )

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
                    local start, _, filn, lnum, col, text = string.find(
                        t,
                        [[([^:]+):(%d+):(%d+):(.*)]]
                    )

                    -- Handle Windows drive letter (e.g. "C:") at the beginning (if present)
                    if start == 3 then
                        filn = string.sub(t.value, 1, 3) .. filn
                    end

                    return filn, lnum, col, text
                end
            else
                return function(t)
                    local _, _, filn, lnum, col, text = string.find(
                        t,
                        [[([^:]+):(%d+):(%d+):(.*)]]
                    )
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
                        return Path:new({ t.cwd, t.filename }):absolute(), false
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
                        "-e",
                        prompt,
                        "--",
                    }
                end

                if #filename > 0 then
                    table.insert(search_command, filename)
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
        pickers.new({
            cwd = cwd,
            prompt_title = "Notes referencing `" .. title .. "`",
            default_text = search_pattern,
            -- link to specific file (a daily file): [[2021-02-22]]
            -- link to heading in specific file (a daily file): [[2021-02-22#Touchpoint]]
            -- link to heading globally [[#Touchpoint]]
            -- link to heading in specific file (a daily file): [[The cool note#^xAcSh-xxr]]
            -- link to paragraph globally [[#^xAcSh-xxr]]
            finder = live_grepper,
            previewer = conf.grep_previewer(opts),
            sorter = sorters.highlighter_only(opts),
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
        }):find()
    end
end

--
-- PreviewImg:
-- -----------
--
-- preview media
--
local function PreviewImg(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or M.Cfg.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or M.Cfg.close_after_yanking

    vim.cmd("normal yi)")
    local fname = vim.fn.getreg('"0')

    -- check if fname exists anywhere
    local fexists = file_exists(M.Cfg.home .. "/" .. fname)

    if fexists == true then
        find_files_sorted({
            prompt_title = "Preview image/media",
            cwd = M.Cfg.home,
            default_text = fname,
            find_command = M.Cfg.find_command,
            filter_extensions = {
                ".png",
                ".jpg",
                ".bmp",
                ".gif",
                ".pdf",
                ".mp4",
                ".webm",
            },
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
        })
    else
        print("File not found: " .. M.Cfg.home .. "/" .. fname)
    end
end

--
-- BrowseImg:
-- -----------
--
-- preview media
--
local function BrowseImg(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or M.Cfg.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or M.Cfg.close_after_yanking

    find_files_sorted({
        prompt_title = "Preview image/media",
        cwd = M.Cfg.home,
        find_command = M.Cfg.find_command,
        filter_extensions = {
            ".png",
            ".jpg",
            ".bmp",
            ".gif",
            ".pdf",
            ".mp4",
            ".webm",
        },
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
    })
end

--
-- FindFriends:
-- -----------
--
-- Find notes also linking to the link under cursor
--
local function FindFriends(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or M.Cfg.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or M.Cfg.close_after_yanking

    vim.cmd("normal yi]")
    local title = vim.fn.getreg('"0')
    title = title:gsub("^(%[)(.+)(%])$", "%2")

    builtin.live_grep({
        prompt_title = "Notes referencing `" .. title .. "`",
        cwd = M.Cfg.home,
        default_text = "\\[\\[" .. title .. "\\]\\]",
        find_command = M.Cfg.find_command,
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
end

--
-- YankLink:
-- -----------
--
-- Create and yank a [[link]] from the current note.
--
local function YankLink()
    local title = "[[" .. path_to_linkname(vim.fn.expand("%:p"), M.Cfg) .. "]]"
    vim.fn.setreg('"', title)
    print("yanked " .. title)
end

--
-- GotoDate:
-- ----------
--
-- find note for date and create it if necessary.
--
local function GotoDate(opts)
    opts.dates = calculate_dates(opts.date_table)
    opts.insert_after_inserting = opts.insert_after_inserting
        or M.Cfg.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or M.Cfg.close_after_yanking

    local word = opts.date or os.date(dateformats.date)

    local fname = M.Cfg.dailies .. "/" .. word .. M.Cfg.extension
    local fexists = file_exists(fname)
    if
        (fexists ~= true)
        and (
            (opts.follow_creates_nonexisting == true)
            or M.Cfg.follow_creates_nonexisting == true
        )
    then
        create_note_from_template(
            word,
            fname,
            M.note_type_templates.daily,
            opts.dates
        )
        opts.erase = true
        opts.erase_file = fname
    end

    find_files_sorted({
        prompt_title = "Goto day",
        cwd = M.Cfg.dailies,
        default_text = word,
        find_command = M.Cfg.find_command,
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

--
-- GotoToday:
-- ----------
--
-- find today's daily note and create it if necessary.
--
local function GotoToday(opts)
    opts = opts or {}
    local today = os.date(dateformats.date)
    opts.date_table = os.date("*t")
    opts.date = today
    GotoDate(opts)
end

--
-- FindNotes:
-- ----------
--
-- Select from notes
--
local function FindNotes(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or M.Cfg.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or M.Cfg.close_after_yanking

    find_files_sorted({
        prompt_title = "Find notes by name",
        cwd = M.Cfg.home,
        find_command = M.Cfg.find_command,
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
end

--
-- InsertImgLink:
-- --------------
--
-- Insert link to image / media, with optional preview
--
local function InsertImgLink(opts)
    opts = opts or {}
    find_files_sorted({
        prompt_title = "Find image/media",
        cwd = M.Cfg.home,
        find_command = M.Cfg.find_command,
        filter_extensions = {
            ".png",
            ".jpg",
            ".bmp",
            ".gif",
            ".pdf",
            ".mp4",
            ".webm",
        },
        preview_type = "media",

        attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                local fn = selection.value
                fn = fn:gsub(M.Cfg.home .. "/", "")
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
    })
end

--
-- SearchNotes:
-- ------------
--
-- find the file linked to by the word under the cursor
--
local function SearchNotes(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or M.Cfg.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or M.Cfg.close_after_yanking

    builtin.live_grep({
        prompt_title = "Search in notes",
        cwd = M.Cfg.home,
        search_dirs = { M.Cfg.home },
        default_text = vim.fn.expand("<cword>"),
        find_command = M.Cfg.find_command,
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
end

--
-- ShowBacklinks:
-- ------------
--
-- Find all notes linking to this one
--
local function ShowBacklinks(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or M.Cfg.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or M.Cfg.close_after_yanking

    local title = path_to_linkname(vim.fn.expand("%:p"), M.Cfg)
    -- or vim.api.nvim_buf_get_name(0)
    builtin.live_grep({
        results_title = "Backlinks to " .. title,
        prompt_title = "Search",
        cwd = M.Cfg.home,
        search_dirs = { M.Cfg.home },
        default_text = "\\[\\[" .. title .. "\\]\\]",
        find_command = M.Cfg.find_command,
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
end

--
-- CreateNote:
-- ------------
--
-- Prompts for title and creates note with default template
--
local function on_create(opts, title)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or M.Cfg.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or M.Cfg.close_after_yanking

    if title == nil then
        return
    end

    local fname = M.Cfg.home .. "/" .. title .. M.Cfg.extension
    local fexists = file_exists(fname)
    if fexists ~= true then
        create_note_from_template(title, fname, M.note_type_templates.normal)
        opts.erase = true
        opts.erase_file = fname
    end

    find_files_sorted({
        prompt_title = "Created note...",
        cwd = M.Cfg.home,
        default_text = title,
        find_command = M.Cfg.find_command,
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

local function CreateNote(opts)
    opts = opts or {}
    -- vim.ui.input causes ppl problems - see issue #4
    -- vim.ui.input({ prompt = "Title: " }, on_create)
    local title = vim.fn.input("Title: ")
    title = title:gsub("[" .. M.Cfg.extension .. "]+$", "")
    if #title > 0 then
        on_create(opts, title)
    end
end

--
-- CreateNoteSelectTemplate()
-- --------------------------
--
-- Prompts for title, then pops up telescope for template selection,
-- creates the new note by template and opens it

local function on_create_with_template(opts, title)
    if title == nil then
        return
    end

    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or M.Cfg.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or M.Cfg.close_after_yanking

    local fname = M.Cfg.home .. "/" .. title .. M.Cfg.extension
    local fexists = file_exists(fname)
    if fexists == true then
        -- open the new note
        vim.cmd("e " .. fname)
        picker_actions.post_open()
        return
    end

    find_files_sorted({
        prompt_title = "Select template...",
        cwd = M.Cfg.templates,
        find_command = M.Cfg.find_command,
        attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                -- local template = M.Cfg.templates .. "/" .. action_state.get_selected_entry().value
                local template = action_state.get_selected_entry().value
                create_note_from_template(title, fname, template)
                -- open the new note
                vim.cmd("e " .. fname)
                picker_actions.post_open()
            end)
            map("i", "<c-y>", picker_actions.yank_link(opts))
            map("i", "<c-i>", picker_actions.paste_link(opts))
            map("n", "<c-y>", picker_actions.yank_link(opts))
            map("n", "<c-i>", picker_actions.paste_link(opts))
            return true
        end,
    })
end

local function CreateNoteSelectTemplate(opts)
    opts = opts or {}
    -- vim.ui.input causes ppl problems - see issue #4
    -- vim.ui.input({ prompt = "Title: " }, on_create_with_template)
    local title = vim.fn.input("Title: ")
    title = title:gsub("[" .. M.Cfg.extension .. "]+$", "")
    if #title > 0 then
        on_create_with_template(opts, title)
    end
end

--
-- GotoThisWeek:
-- -------------
--
-- find this week's weekly note and create it if necessary.
--
local function GotoThisWeek(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or M.Cfg.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or M.Cfg.close_after_yanking

    local title = os.date(dateformats.isoweek)
    local fname = M.Cfg.weeklies .. "/" .. title .. M.Cfg.extension
    local fexists = file_exists(fname)
    if
        (fexists ~= true)
        and (
            (opts.weeklies_create_nonexisting == true)
            or M.Cfg.weeklies_create_nonexisting == true
        )
    then
        create_note_from_template(title, fname, M.note_type_templates.weekly)
        opts.erase = true
        opts.erase_file = fname
    end

    find_files_sorted({
        prompt_title = "Goto this week:",
        cwd = M.Cfg.weeklies,
        default_text = title,
        find_command = M.Cfg.find_command,
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

--
-- Calendar Stuff
-- --------------

-- return if a daily 'note exists' indicator (sign) should be displayed for a particular day
local function CalendarSignDay(day, month, year)
    local fn = M.Cfg.dailies
        .. "/"
        .. string.format("%04d-%02d-%02d", year, month, day)
        .. M.Cfg.extension
    if file_exists(fn) then
        return 1
    end
    return 0
end

-- action on enter on a specific day:
-- preview in telescope, stay in calendar on cancel, open note in other window on accept
local function CalendarAction(day, month, year, _, _)
    local opts = {}
    opts.date = string.format("%04d-%02d-%02d", year, month, day)
    opts.date_table = { year = year, month = month, day = day }
    opts.calendar = true
    GotoDate(opts)
end

local function ShowCalendar(opts)
    local defaults = {}
    defaults.cmd = "CalendarVR"
    defaults.vertical_resize = 1

    opts = opts or defaults
    vim.cmd(opts.cmd)
    if opts.vertical_resize then
        vim.cmd("vertical resize +" .. opts.vertical_resize)
    end
end

-- set up calendar integration: forward to our lua functions
local function SetupCalendar(opts)
    local defaults = M.Cfg.calendar_opts
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

        let g:calendar_monday = {{calendar_monday}}
        let g:calendar_mark = '{{calendar_mark}}'
        let g:calendar_weeknm = {{weeknm}}
    ]]

    for k, v in pairs(opts) do
        cmd = cmd:gsub("{{" .. k .. "}}", v)
    end
    vim.cmd(cmd)
end

local function ToggleTodo(opts)
    -- replace
    --       by -
    -- -     by - [ ]
    -- - [ ] by - [x]
    -- - [x] by -
    -- enter insert mode if opts.i == true
    opts = opts or {}
    local linenr = vim.api.nvim_win_get_cursor(0)[1]
    local curline = vim.api.nvim_buf_get_lines(0, linenr - 1, linenr, false)[1]
    local stripped = vim.trim(curline)
    local repline
    if
        vim.startswith(stripped, "- ") and not vim.startswith(stripped, "- [")
    then
        repline = curline:gsub("- ", "- [ ] ", 1)
    else
        if vim.startswith(stripped, "- [ ]") then
            repline = curline:gsub("- %[ %]", "- [x]", 1)
        else
            if vim.startswith(stripped, "- [x]") then
                repline = curline:gsub("- %[x%]", "-", 1)
            else
                repline = curline:gsub("(%S)", "- [ ] %1", 1)
            end
        end
    end
    vim.api.nvim_buf_set_lines(0, linenr - 1, linenr, false, { repline })
    if opts.i then
        vim.api.nvim_feedkeys("A", "m", false)
    end
end

local function FindAllTags(opts)
    opts = opts or {}
    local i = opts.i
    opts.cwd = M.Cfg.home
    opts.tag_notation = M.Cfg.tag_notation

    local tag_map = tagutils.do_find_all_tags(opts)
    local taglist = {}

    local max_tag_len = 0
    for k, v in pairs(tag_map) do
        taglist[#taglist + 1] = { tag = k, details = v }
        if #k > max_tag_len then
            max_tag_len = #k
        end
    end

    if M.Cfg.show_tags_theme == "get_cursor" then
        opts = themes.get_cursor({
            layout_config = {
                height = math.min(math.floor(vim.o.lines * 0.8), #taglist),
            },
        })
    elseif M.Cfg.show_tags_theme == "ivy" then
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
    opts.cwd = M.Cfg.home
    opts.tag_notation = M.Cfg.tag_notation
    opts.i = i
    pickers.new(opts, {
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
                actions._close(prompt_bufnr, true)

                -- TODO actions for insert tag, default action: search for tag
                local selection = action_state.get_selected_entry().value.tag
                local follow_opts = {
                    follow_tag = selection,
                    show_link_counts = true,
                }
                FollowLink(follow_opts)
            end)
            map("i", "<c-y>", picker_actions.yank_tag(opts))
            map("i", "<c-i>", picker_actions.paste_tag(opts))
            map("n", "<c-y>", picker_actions.yank_tag(opts))
            map("n", "<c-i>", picker_actions.paste_tag(opts))
            map("n", "<c-c>", picker_actions.close(opts))
            map("n", "<esc>", picker_actions.close(opts))
            return true
        end,
    }):find()
end

-- Setup(cfg)
--
-- Overrides config with elements from cfg. See top of file for defaults.
--
local function Setup(cfg)
    cfg = cfg or {}
    local debug = cfg.debug
    for k, v in pairs(cfg) do
        -- merge everything but calendar opts
        -- they will be merged later
        if k ~= "calendar_opts" then
            M.Cfg[k] = v
            if debug then
                print(
                    "Setup() setting `"
                        .. k
                        .. "`   ->   `"
                        .. tostring(v)
                        .. "`"
                )
            end
        end
    end

    -- TODO: this is obsolete:
    if vim.fn.executable("rg") == 1 then
        M.Cfg.find_command = { "rg", "--files", "--sortr", "created" }
    else
        M.Cfg.find_command = nil
    end

    -- this looks a little messy
    if M.Cfg.plug_into_calendar then
        cfg.calendar_opts = cfg.calendar_opts or {}
        M.Cfg.calendar_opts = M.Cfg.calendar_opts or {}
        M.Cfg.calendar_opts.weeknm = cfg.calendar_opts.weeknm
            or M.Cfg.calendar_opts.weeknm
            or 1
        M.Cfg.calendar_opts.calendar_monday = cfg.calendar_opts.calendar_monday
            or M.Cfg.calendar_opts.calendar_monday
            or 1
        M.Cfg.calendar_opts.calendar_mark = cfg.calendar_opts.calendar_mark
            or M.Cfg.calendar_opts.calendar_mark
            or "left-fit"
        SetupCalendar(M.Cfg.calendar_opts)
    end

    -- setup extensions to filter for
    M.Cfg.filter_extensions = cfg.filter_extensions or { M.Cfg.extension }

    -- provide fake filenames for template loading to fail silently if template is configured off
    M.Cfg.template_new_note = M.Cfg.template_new_note or "none"
    M.Cfg.template_new_daily = M.Cfg.template_new_daily or "none"
    M.Cfg.template_new_weekly = M.Cfg.template_new_weekly or "none"

    -- refresh templates
    M.note_type_templates = {
        normal = M.Cfg.template_new_note,
        daily = M.Cfg.template_new_daily,
        weekly = M.Cfg.template_new_weekly,
    }

    -- for previewers to pick up our syntax, we need to tell plenary to override `.md` with our syntax
    filetype.add_file("telekasten")
    -- setting the syntax moved into plugin/telekasten.vim
    -- and does not work

    if M.Cfg.take_over_my_home == true then
        vim.cmd(
            "au BufEnter "
                .. M.Cfg.home
                .. "/*"
                .. M.Cfg.extension
                .. " set ft=telekasten"
        )
    end

    if debug then
        print("Resulting config:")
        print("-----------------")
        print(vim.inspect(M.Cfg))
    end
end

M.find_notes = FindNotes
M.find_daily_notes = FindDailyNotes
M.search_notes = SearchNotes
M.insert_link = InsertLink
M.follow_link = FollowLink
M.setup = Setup
M.goto_today = GotoToday
M.new_note = CreateNote
M.goto_thisweek = GotoThisWeek
M.find_weekly_notes = FindWeeklyNotes
M.yank_notelink = YankLink
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

-- Telekasten command, completion
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
        }
    end,
}

TelekastenCmd.command = function(subcommand)
    local show = function(opts)
        opts = opts or {}
        pickers.new(opts, {
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

                    local selection = action_state.get_selected_entry().value[3]
                    selection()
                end)
                return true
            end,
        }):find()
    end
    if subcommand then
        print("trying subcommand " .. "`" .. subcommand .. "`")
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

        if M.Cfg.command_palette_theme == "ivy" then
            theme = themes.get_ivy()
        else
            theme = themes.get_dropdown({
                layout_config = { prompt_position = "top" },
            })
        end
        show(theme)
    end
end

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
