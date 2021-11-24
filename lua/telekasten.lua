local builtin = require("telescope.builtin")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

-- declare locals for the nvim api stuff to avoid more lsp warnings
local vim = vim

-- ----------------------------------------------------------------------------
-- DEFAULT CONFIG
-- ----------------------------------------------------------------------------
local home = vim.fn.expand("~/zettelkasten")

local ZkCfg = {
	home = home,
	dailies = home .. "/" .. "daily",
	weeklies = home .. "/" .. "weekly",
	templates = home .. "/" .. "templates",
	extension = ".md",

	-- following a link to a non-existing note will create it
	follow_creates_nonexisting = true,
	dailies_create_nonexisting = true,
	weeklies_create_nonexisting = true,

	-- templates for new notes
	template_new_note = home .. "/" .. "templates/new_note.md",
	template_new_daily = home .. "/" .. "templates/daily_tk.md",
	template_new_weekly = home .. "/" .. "templates/weekly_tk.md",

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
}

-- ----------------------------------------------------------------------------

local note_type_templates = {
	normal = ZkCfg.template_new_note,
	daily = ZkCfg.template_new_daily,
	weekly = ZkCfg.template_new_weekly,
}

local function file_exists(fname)
	local f = io.open(fname, "r")
	-- print("checking for " .. fname)
	if f ~= nil then
		io.close(f)
		return true
	else
		return false
	end
end

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

local daymap = { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" }
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

local calenderinfo_today = function()
	local dinfo = os.date("*t")
	local opts = {}
	opts.date = os.date("%Y-%m-%d")
	opts.hdate = daymap[dinfo.wday]
		.. ", "
		.. monthmap[dinfo.month]
		.. " "
		.. dinfo.day
		.. daysuffix(dinfo.day)
		.. ", "
		.. dinfo.year
	opts.week = os.date("%V")
	opts.month = dinfo.month
	opts.year = dinfo.year
	opts.day = dinfo.day
	return opts
end

local function linesubst(line, title, calendar_info)
	local cinfo = calendar_info or calenderinfo_today()
	local substs = {
		date = cinfo.date,
		hdate = cinfo.hdate,
		week = cinfo.week,
		year = cinfo.year,
		title = title,
	}
	for k, v in pairs(substs) do
		line = line:gsub("{{" .. k .. "}}", v)
	end

	return line
end

local create_note_from_template = function(title, filepath, templatefn, calendar_info)
	-- first, read the template file
	local lines = {}
	for line in io.lines(templatefn) do
		lines[#lines + 1] = line
	end

	-- now write the output file, substituting vars line by line
	local ofile = io.open(filepath, "a")
	for _, line in pairs(lines) do
		ofile:write(linesubst(line, title, calendar_info) .. "\n")
	end

	ofile:close()
end

local path_to_linkname = function(p)
	local fn = vim.split(p, "/")
	fn = fn[#fn]
	fn = vim.split(fn, ZkCfg.extension)
	fn = fn[1]
	return fn
end

--
-- FindDailyNotes:
-- ---------------
--
-- Select from daily notes
--
local FindDailyNotes = function(opts)
	opts = opts or {}

	local today = os.date("%Y-%m-%d")
	local fname = ZkCfg.dailies .. "/" .. today .. ZkCfg.extension
	local fexists = file_exists(fname)
	if
		(fexists ~= true) and ((opts.dailies_create_nonexisting == true) or ZkCfg.dailies_create_nonexisting == true)
	then
		create_note_from_template(today, fname, note_type_templates.daily)
	end

	builtin.find_files({
		prompt_title = "Find daily note",
		cwd = ZkCfg.dailies,
		find_command = ZkCfg.find_command,
	})
end

--
-- FindWeeklyNotes:
-- ---------------
--
-- Select from daily notes
--
local FindWeeklyNotes = function(opts)
	opts = opts or {}

	local title = os.date("%Y-W%V")
	local fname = ZkCfg.weeklies .. "/" .. title .. ZkCfg.extension
	local fexists = file_exists(fname)
	if
		(fexists ~= true) and ((opts.weeklies_create_nonexisting == true) or ZkCfg.weeklies_create_nonexisting == true)
	then
		create_note_from_template(title, fname, note_type_templates.weekly)
	end

	builtin.find_files({
		prompt_title = "Find weekly note",
		cwd = ZkCfg.weeklies,
		find_command = ZkCfg.find_command,
	})
end

--
-- InsertLink:
-- -----------
--
-- Select from all notes and put a link in the current buffer
--
local InsertLink = function(_)
	builtin.find_files({
		prompt_title = "Insert link to note",
		cwd = ZkCfg.home,
		attach_mappings = function(prompt_bufnr, _)
			actions.select_default:replace(function()
				actions.close(prompt_bufnr)
				local selection = action_state.get_selected_entry()
				local fn = path_to_linkname(selection.value)
				vim.api.nvim_put({ "[[" .. fn .. "]]" }, "", false, true)
			end)
			return true
		end,
		find_command = ZkCfg.find_command,
	})
end

--
-- FollowLink:
-- -----------
--
-- find the file linked to by the word under the cursor
--
local FollowLink = function(opts)
	opts = opts or {}
	vim.cmd("normal yi]")
	local title = vim.fn.getreg('"0')

	-- check if fname exists anywhere
	local fexists = file_exists(ZkCfg.weeklies .. "/" .. title .. ZkCfg.extension)
	fexists = fexists or file_exists(ZkCfg.dailies .. "/" .. title .. ZkCfg.extension)
	fexists = fexists or file_exists(ZkCfg.home .. "/" .. title .. ZkCfg.extension)

	if
		(fexists ~= true) and ((opts.follow_creates_nonexisting == true) or ZkCfg.follow_creates_nonexisting == true)
	then
		local fname = ZkCfg.home .. "/" .. title .. ZkCfg.extension
		create_note_from_template(title, fname, note_type_templates.normal)
	end

	builtin.find_files({
		prompt_title = "Follow link to note...",
		cwd = ZkCfg.home,
		default_text = title,
		find_command = ZkCfg.find_command,
	})
end

--
-- YankLink:
-- -----------
--
-- Create and yank a [[link]] from the current note.
--
local YankLink = function()
	local title = "[[" .. path_to_linkname(vim.fn.expand("%")) .. "]]"
	vim.fn.setreg('"', title)
	print("yanked " .. title)
end

--
-- GotoToday:
-- ----------
--
-- find today's daily note and create it if necessary.
--
local GotoToday = function(opts)
	opts = opts or calenderinfo_today()
	local word = opts.date or os.date("%Y-%m-%d")

	local fname = ZkCfg.dailies .. "/" .. word .. ZkCfg.extension
	local fexists = file_exists(fname)
	if
		(fexists ~= true) and ((opts.follow_creates_nonexisting == true) or ZkCfg.follow_creates_nonexisting == true)
	then
		create_note_from_template(word, fname, note_type_templates.daily, opts)
	end

	builtin.find_files({
		prompt_title = "Goto day",
		cwd = ZkCfg.home,
		default_text = word,
		find_command = ZkCfg.find_command,
		attach_mappings = function(prompt_bufnr, _)
			actions.select_default:replace(function()
				actions.close(prompt_bufnr)

				-- open the new note
				if opts.calendar == true then
					vim.cmd("wincmd w")
				end
				vim.cmd("e " .. fname)
			end)
			return true
		end,
	})
end

--
-- FindNotes:
-- ----------
--
-- Select from notes
--
local FindNotes = function(_)
	builtin.find_files({
		prompt_title = "Find notes by name",
		cwd = ZkCfg.home,
		find_command = ZkCfg.find_command,
	})
end

--
-- SearchNotes:
-- ------------
--
-- find the file linked to by the word under the cursor
--
local SearchNotes = function(_)
	builtin.live_grep({
		prompt_title = "Search in notes",
		cwd = ZkCfg.home,
		search_dirs = { ZkCfg.home },
		default_text = vim.fn.expand("<cword>"),
		find_command = ZkCfg.find_command,
	})
end

--
-- CreateNote:
-- ------------
--
-- Prompts for title and creates note with default template
--
local function on_create(title)
	if title == nil then
		return
	end

	local fname = ZkCfg.home .. "/" .. title .. ZkCfg.extension
	local fexists = file_exists(fname)
	if fexists ~= true then
		create_note_from_template(title, fname, note_type_templates.normal)
	end

	builtin.find_files({
		prompt_title = "Created note...",
		cwd = ZkCfg.home,
		default_text = title,
		find_command = ZkCfg.find_command,
	})
end

local CreateNote = function(_)
	vim.ui.input({ prompt = "Title: " }, on_create)
end

--
-- CreateNoteSelectTemplate()
-- --------------------------
--
-- Prompts for title, then pops up telescope for template selection,
-- creates the new note by template and opens it

local function on_create_with_template(title)
	if title == nil then
		return
	end

	local fname = ZkCfg.home .. "/" .. title .. ZkCfg.extension
	local fexists = file_exists(fname)
	if fexists == true then
		-- open the new note
		vim.cmd("e " .. fname)
		return
	end

	builtin.find_files({
		prompt_title = "Select template...",
		cwd = ZkCfg.templates,
		find_command = ZkCfg.find_command,
		attach_mappings = function(prompt_bufnr, _)
			actions.select_default:replace(function()
				actions.close(prompt_bufnr)
				local template = ZkCfg.templates .. "/" .. action_state.get_selected_entry().value
				create_note_from_template(title, fname, template)
				-- open the new note
				vim.cmd("e " .. fname)
			end)
			return true
		end,
	})
end

local CreateNoteSelectTemplate = function(_)
	vim.ui.input({ prompt = "Title: " }, on_create_with_template)
end

--
-- GotoThisWeek:
-- -------------
--
-- find this week's weekly note and create it if necessary.
--
local GotoThisWeek = function(opts)
	opts = opts or {}

	local title = os.date("%Y-W%V")
	local fname = ZkCfg.weeklies .. "/" .. title .. ZkCfg.extension
	local fexists = file_exists(fname)
	if
		(fexists ~= true) and ((opts.weeklies_create_nonexisting == true) or ZkCfg.weeklies_create_nonexisting == true)
	then
		create_note_from_template(title, fname, note_type_templates.weekly)
	end

	builtin.find_files({
		prompt_title = "Goto this week:",
		cwd = ZkCfg.weeklies,
		default_text = title,
		find_command = ZkCfg.find_command,
	})
end

--
-- Calendar Stuff
-- --------------

-- return if a daily 'note exists' indicator (sign) should be displayed for a particular day
local CalendarSignDay = function(day, month, year)
	local fn = ZkCfg.dailies .. "/" .. string.format("%04d-%02d-%02d", year, month, day) .. ZkCfg.extension
	if file_exists(fn) then
		return 1
	end
	return 0
end

-- action on enter on a specific day:
-- preview in telescope, stay in calendar on cancel, open note in other window on accept
local CalendarAction = function(day, month, year, weekday, _)
	local today = string.format("%04d-%02d-%02d", year, month, day)
	local opts = {}
	opts.date = today
	opts.hdate = daymap[weekday] .. ", " .. monthmap[tonumber(month)] .. " " .. day .. daysuffix(day) .. ", " .. year
	opts.week = "n/a" -- TODO: calculate the week somehow
	opts.month = month
	opts.year = year
	opts.day = day
	opts.calendar = true
	GotoToday(opts)
end

local ShowCalendar = function(opts)
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
local SetupCalendar = function(opts)
	local defaults = ZkCfg.calendar_opts
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

-- Setup(cfg)
--
-- Overrides config with elements from cfg. See top of file for defaults.
--
local Setup = function(cfg)
	cfg = cfg or {}
	for k, v in pairs(cfg) do
		-- merge everything but calendar opts
		-- they will be merged later
		if k ~= "calendar_opts" then
			ZkCfg[k] = v
		end
	end
	if vim.fn.executable("rg") then
		ZkCfg.find_command = { "rg", "--files", "--sortr", "created" }
	else
		ZkCfg.find_command = nil
	end

	-- this looks a little messy
	if ZkCfg.plug_into_calendar then
		cfg.calendar_opts = cfg.calendar_opts or {}
		ZkCfg.calendar_opts = ZkCfg.calendar_opts or {}
		ZkCfg.calendar_opts.weeknm = cfg.calendar_opts.weeknm or ZkCfg.calendar_opts.weeknm or 1
		ZkCfg.calendar_opts.calendar_monday = cfg.calendar_opts.calendar_monday
			or ZkCfg.calendar_opts.calendar_monday
			or 1
		ZkCfg.calendar_opts.calendar_mark = cfg.calendar_opts.calendar_mark
			or ZkCfg.calendar_opts.calendar_mark
			or "left-fit"
		SetupCalendar(ZkCfg.calendar_opts)
	end
end

local M = {
	ZkCfg = ZkCfg,
	find_notes = FindNotes,
	find_daily_notes = FindDailyNotes,
	search_notes = SearchNotes,
	insert_link = InsertLink,
	follow_link = FollowLink,
	setup = Setup,
	goto_today = GotoToday,
	new_note = CreateNote,
	goto_thisweek = GotoThisWeek,
	find_weekly_notes = FindWeeklyNotes,
	yank_notelink = YankLink,
	create_note_sel_template = CreateNoteSelectTemplate,
	show_calendar = ShowCalendar,
	CalendarSignDay = CalendarSignDay,
	CalendarAction = CalendarAction,
}
return M
