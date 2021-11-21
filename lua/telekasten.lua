local builtin = require "telescope.builtin"

local actions = require("telescope.actions")
local action_state = require "telescope.actions.state"

-- declare locals for the nvim api stuff to avoid more lsp warnings
local vim = vim


-- ----------------------------------------------------------------------------
-- DEFAULT CONFIG
-- ----------------------------------------------------------------------------
local home = vim.fn.expand("~/zettelkasten")

ZkCfg = {
    home         = home,
    dailies      = vim.fn.expand("~/zettelkasten/daily"),
    weeklies     = vim.fn.expand("~/zettelkasten/weekly"),
    extension    = ".md",
    daily_finder = "daily_finder.sh",

    -- where to install the daily_finder,
    -- (must be a dir in your PATH)
    my_bin       = vim.fn.expand('~/bin'),

    -- download tool for daily_finder installation: curl or wget
    downloader = 'curl',
    -- downloader = 'wget',  -- wget is supported, too

    -- following a link to a non-existing note will create it
    follow_creates_nonexisting = true,
    dailies_create_nonexisting = true,
    weeklies_create_nonexisting = true,

    -- templates for new notes
    template_new_note   = home .. '/' .. 'templates/new_note.md',
    template_new_daily  = home .. '/' .. 'templates/daily_tk.md',
    template_new_weekly = home .. '/' .. 'templates/weekly_tk.md',
}

-- ----------------------------------------------------------------------------



local downloader2cmd = {
    curl = 'curl -o',
    wget = 'wget -O',
}

local note_type_templates = {
    normal = ZkCfg.template_new_note,
    daily = ZkCfg.template_new_daily,
    weekly = ZkCfg.template_new_weekly,
}


local function file_exists(fname)
   local f=io.open(fname,"r")
   if f~=nil then io.close(f) return true else return false end
end

local function daysuffix(day)
    if((day == '1') or (day == '21') or (day == '31')) then return 'st' end
    if((day == '2') or (day == '22')) then return 'nd' end
    if((day == '3') or (day == '33')) then return 'rd' end
    return 'th'
end

local function linesubst(line, title)
    local substs = {
        date = os.date('%Y-%m-%d'),
        hdate = os.date('%A, %B %dx, %Y'):gsub('x', daysuffix(os.date('%d'))),
        week = os.date('%V'),
        year = os.date('%Y'),
        title = title,
    }
    for k, v in pairs(substs) do
        line = line:gsub("{{"..k.."}}", v)
    end

    return line
end

local create_note_from_template = function (title, filepath, templatefn)
    -- first, read the template file
    local lines = {}
    for line in io.lines(templatefn) do
        lines[#lines+1] = line
    end

    -- now write the output file, substituting vars line by line
    local ofile = io.open(filepath, 'a')
    for _, line in pairs(lines) do
        ofile:write(linesubst(line, title) .. '\n')
    end

    ofile:close()
end



--
-- InstallDailyFinder:
-- -------------------
--
-- downloads the daily finder scripts to the configured `my_bin` directory
-- and makes it executable
--
InstallDailyFinder = function()
    local destpath = ZkCfg.my_bin .. '/' .. ZkCfg.daily_finder
    local cmd = downloader2cmd[ZkCfg.downloader]
    vim.api.nvim_command('!'.. cmd .. ' ' .. destpath .. ' https://raw.githubusercontent.com/renerocksai/telekasten.nvim/main/ext_commands/daily_finder.sh')
    vim.api.nvim_command('!chmod +x ' .. destpath)
end

local path_to_linkname = function(p)
    local fn = vim.split(p, "/")
    fn = fn[#fn]
    fn = vim.split(fn, ZkCfg.extension)
    fn = fn[1]
    return fn
end

local zk_entry_maker = function(entry)
    return {
        value = entry,
        display = path_to_linkname(entry),
        ordinal = entry,
    }
end


local check_local_finder = function()
    local ret = vim.fn.system(ZkCfg.daily_finder .. ' check')
    return ret ==  "OK\n"
    -- return vim.fn.executable(ZkCfg.daily_finder) == 1
end



--
-- FindDailyNotes:
-- ---------------
--
-- Select from daily notes
--
FindDailyNotes = function(opts)
    opts = {} or opts

    local today = os.date("%Y-%m-%d")
    local fname = ZkCfg.dailies .. '/' .. today .. ZkCfg.extension
    local fexists = file_exists(fname)
    if ((fexists ~= true) and ((opts.dailies_create_nonexisting == true) or ZkCfg.dailies_create_nonexisting == true)) then
        create_note_from_template(today, fname, note_type_templates.daily)
    end

    if (check_local_finder() == true) then
            builtin.find_files({
            prompt_title = "Find daily note",
            cwd = ZkCfg.dailies,
            find_command = { ZkCfg.daily_finder },
            entry_maker = zk_entry_maker,
       })
   else
       print("Daily finder not found. Try :lua require('telekasten').install_daily_finder()")
   end
end



--
-- FindWeeklyNotes:
-- ---------------
--
-- Select from daily notes
--
FindWeeklyNotes = function(opts)
    opts = {} or opts

    local title = os.date("%Y-W%V")
    local fname = ZkCfg.weeklies .. '/' .. title .. ZkCfg.extension
    local fexists = file_exists(fname)
    if ((fexists ~= true) and ((opts.weeklies_create_nonexisting == true) or ZkCfg.weeklies_create_nonexisting == true)) then
        create_note_from_template(title, fname, note_type_templates.weekly)
    end

    if (check_local_finder() == true) then
            builtin.find_files({
            prompt_title = "Find weekly note",
            cwd = ZkCfg.weeklies,
            find_command = { ZkCfg.daily_finder },
            entry_maker = zk_entry_maker,
       })
   else
       print("Daily finder not found. Try :lua require('telekasten').install_daily_finder()")
   end
end



--
-- InsertLink:
-- -----------
--
-- Select from all notes and put a link in the current buffer
--
InsertLink = function(opts)
    opts = {} or opts
    if (check_local_finder() == true) then
        builtin.find_files({
            prompt_title = "Insert link to note",
            cwd = ZkCfg.home,
            attach_mappings = function(prompt_bufnr, map)
                map = map -- get rid of lsp error
                actions.select_default:replace(function()
                    actions.close(prompt_bufnr)
                    local selection = action_state.get_selected_entry()
                    local fn = path_to_linkname(selection.value)
                    vim.api.nvim_put({ "[["..fn.."]]" }, "", false, true)
                end)
                return true
            end,
            find_command = { ZkCfg.daily_finder },
            entry_maker = zk_entry_maker,
       })
   else
       print("Daily finder not found. Try :lua require('telekasten').install_daily_finder()")
   end
end



--
-- FollowLink:
-- -----------
--
-- find the file linked to by the word under the cursor
--
FollowLink = function(opts)
    opts = {} or opts
    vim.cmd('normal yi]')
    local title = vim.fn.getreg('"0')

    local fname = ZkCfg.home .. '/' .. title .. ZkCfg.extension
    local fexists = file_exists(fname)
    if ((fexists ~= true) and ((opts.follow_creates_nonexisting == true) or ZkCfg.follow_creates_nonexisting == true)) then
        create_note_from_template(title, fname, note_type_templates.normal)
    end

    if (check_local_finder() == true) then
        builtin.find_files({
            prompt_title = "Follow link to note...",
            cwd = ZkCfg.home,
            default_text = title,
            find_command = { ZkCfg.daily_finder },
            entry_maker = zk_entry_maker,
       })
   else
       print("Daily finder not found. Try :lua require('telekasten').install_daily_finder()")
   end
end



--
-- GotoToday:
-- ----------
--
-- find today's daily note and create it if necessary.
--
GotoToday = function(opts)
    opts = {} or opts
    local word = os.date("%Y-%m-%d")

    local fname = ZkCfg.dailies .. '/' .. word .. ZkCfg.extension
    local fexists = file_exists(fname)
    if ((fexists ~= true) and ((opts.follow_creates_nonexisting == true) or ZkCfg.follow_creates_nonexisting == true)) then
        create_note_from_template(word, fname, note_type_templates.daily)
    end

    if (check_local_finder() == true) then
        builtin.find_files({
            prompt_title = "Goto today",
            cwd = ZkCfg.home,
            default_text = word,
            find_command = { ZkCfg.daily_finder },
            entry_maker = zk_entry_maker,
       })
   else
       print("Daily finder not found. Try :lua require('telekasten').install_daily_finder()")
   end
end



--
-- FindNotes:
-- ----------
--
-- Select from notes
--
FindNotes = function(opts)
    opts = {} or opts
    builtin.find_files({
        prompt_title = "Find notes by name",
        cwd = ZkCfg.home,
        find_command = { ZkCfg.daily_finder },
        entry_maker = zk_entry_maker,
   })
end



--
-- SearchNotes:
-- ------------
--
-- find the file linked to by the word under the cursor
--
SearchNotes = function(opts)
    opts = {} or opts

    if (check_local_finder() == true) then
        builtin.live_grep({
            prompt_title = "Search in notes",
            cwd = ZkCfg.home,
            search_dirs = { ZkCfg.home },
            default_text = vim.fn.expand("<cword>"),
            find_command = { ZkCfg.daily_finder },
       })
   else
       print("Daily finder not found. Try :lua require('telekasten').install_daily_finder()")
   end
end



--
-- CreateNote:
-- ------------
--
-- find the file linked to by the word under the cursor
--
local function on_create(title)
    if (title == nil) then return end

    local fname = ZkCfg.home .. '/' .. title .. ZkCfg.extension
    local fexists = file_exists(fname)
    if (fexists ~= true) then
        create_note_from_template(title, fname, note_type_templates.normal)
    end

    if (check_local_finder() == true) then
        builtin.find_files({
            prompt_title = "Created note...",
            cwd = ZkCfg.home,
            default_text = title,
            find_command = { ZkCfg.daily_finder },
            entry_maker = zk_entry_maker,
       })
   else
       print("Daily finder not found. Try :lua require('telekasten').install_daily_finder()")
   end

end

CreateNote = function(opts)
    opts = {} or opts
    vim.ui.input({prompt = 'Title: '}, on_create)
end



--
-- GotoThisWeek:
-- ----------
--
-- find this week's weekly note and create it if necessary.
--
GotoThisWeek = function(opts)
    print('local version')
    opts = {} or opts

    local title = os.date("%Y-W%V")
    local fname = ZkCfg.weeklies .. '/' .. title .. ZkCfg.extension
    local fexists = file_exists(fname)
    if ((fexists ~= true) and ((opts.weeklies_create_nonexisting == true) or ZkCfg.weeklies_create_nonexisting == true)) then
        create_note_from_template(title, fname, note_type_templates.weekly)
    end

    if (check_local_finder() == true) then
        builtin.find_files({
            prompt_title = "Goto this week:",
            cwd = ZkCfg.weeklies,
            default_text = title,
            find_command = { ZkCfg.daily_finder },
            entry_maker = zk_entry_maker,
       })
   else
       print("Daily finder not found. Try :lua require('telekasten').install_daily_finder()")
   end
end



-- Setup(cfg)
--
-- Overrides config with elements from cfg
-- Valid keys are:
--     - home : path to zettelkasten folder
--     - dailies : path to folder of daily notes
--     - extension : extension of note files (.md)
--     - daily_finder: executable that finds daily notes and sorts them by date
--                     as long as we have no lua equivalent, this will be necessary
--
Setup = function(cfg)
    cfg = cfg or {}
   for k, v in pairs(cfg) do
       ZkCfg[k] = v
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
    install_daily_finder = InstallDailyFinder,
    goto_today = GotoToday,
    new_note = CreateNote,
    goto_thisweek = GotoThisWeek,
    find_weekly_notes = FindWeeklyNotes,
}
print('local version')
return M




--[[
-- interesting snippet:
      -- set the filename based on the current date
      local filepath = vim.g['wiki_root']..'journal/'..os.date('%Y-%m-%d')..'.md'

      -- if the file doesn't exist
      -- then created file and write date to the top of the file
      if not file_exists(filepath) then
        file = io.open(filepath, 'a')
        io.output(file)
        io.write(os.date("# %a, %d %B '%y"))
        io.close(file)
      end
      api.nvim_command('edit '..filepath)
    end
    return M
--]]

