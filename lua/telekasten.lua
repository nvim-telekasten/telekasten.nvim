local builtin = require "telescope.builtin"
local actions = require("telescope.actions") local action_state = require "telescope.actions.state"

-- declare locals for the nvim api stuff to avoid more lsp warnings
local vim = vim


-- ----------------------------------------------------------------------------
-- DEFAULT CONFIG
-- ----------------------------------------------------------------------------
local home = vim.fn.expand("~/zettelkasten")

ZkCfg = {
    home         = home,
    dailies      = home .. '/' .. 'daily',
    weeklies     = home .. '/' .. 'weekly',
    extension    = ".md",


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

local note_type_templates = {
    normal = ZkCfg.template_new_note,
    daily = ZkCfg.template_new_daily,
    weekly = ZkCfg.template_new_weekly,
}

local function file_exists(fname)
   local f=io.open(fname,"r")
   print("checking for " .. fname)
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
FindDailyNotes = function(opts)
    opts = {} or opts

    local today = os.date("%Y-%m-%d")
    local fname = ZkCfg.dailies .. '/' .. today .. ZkCfg.extension
    local fexists = file_exists(fname)
    if ((fexists ~= true) and ((opts.dailies_create_nonexisting == true) or ZkCfg.dailies_create_nonexisting == true)) then
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
FindWeeklyNotes = function(opts)
    opts = {} or opts

    local title = os.date("%Y-W%V")
    local fname = ZkCfg.weeklies .. '/' .. title .. ZkCfg.extension
    local fexists = file_exists(fname)
    if ((fexists ~= true) and ((opts.weeklies_create_nonexisting == true) or ZkCfg.weeklies_create_nonexisting == true)) then
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
InsertLink = function(opts)
    opts = {} or opts
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
        find_command = ZkCfg.find_command,
   })
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

    -- check if fname exists anywhere
    local fexists = file_exists(ZkCfg.weeklies .. '/' .. title .. ZkCfg.extension)
    fexists = fexists or file_exists(ZkCfg.dailies .. '/' .. title .. ZkCfg.extension)
    fexists = fexists or file_exists(ZkCfg.home .. '/' .. title .. ZkCfg.extension)

    if ((fexists ~= true) and ((opts.follow_creates_nonexisting == true) or ZkCfg.follow_creates_nonexisting == true)) then
        local fname = ZkCfg.home .. '/' .. title .. ZkCfg.extension
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
YankLink = function()
    local title = '[[' .. path_to_linkname(vim.fn.expand('%')) .. ']]'
    vim.fn.setreg('"', title)
    print('yanked ' .. title)
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

    builtin.find_files({
        prompt_title = "Goto today",
        cwd = ZkCfg.home,
        default_text = word,
        find_command = ZkCfg.find_command,
    })
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
        find_command = ZkCfg.find_command,
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
-- find the file linked to by the word under the cursor
--
local function on_create(title)
    if (title == nil) then return end

    local fname = ZkCfg.home .. '/' .. title .. ZkCfg.extension
    local fexists = file_exists(fname)
    if (fexists ~= true) then
        create_note_from_template(title, fname, note_type_templates.normal)
    end

    builtin.find_files({
        prompt_title = "Created note...",
        cwd = ZkCfg.home,
        default_text = title,
        find_command = ZkCfg.find_command,
    })
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
    opts = {} or opts

    local title = os.date("%Y-W%V")
    local fname = ZkCfg.weeklies .. '/' .. title .. ZkCfg.extension
    local fexists = file_exists(fname)
    if ((fexists ~= true) and ((opts.weeklies_create_nonexisting == true) or ZkCfg.weeklies_create_nonexisting == true)) then
        create_note_from_template(title, fname, note_type_templates.weekly)
    end

    builtin.find_files({
        prompt_title = "Goto this week:",
        cwd = ZkCfg.weeklies,
        default_text = title,
        find_command = ZkCfg.find_command,
    })
end


-- Setup(cfg)
--
-- Overrides config with elements from cfg. See top of file for defaults.
--
Setup = function(cfg)
    cfg = cfg or {}
    for k, v in pairs(cfg) do
       ZkCfg[k] = v
    end
    if vim.fn.executable('rg') then
        ZkCfg.find_command = { 'rg', '--files', '--sortr', 'created',  }
    else
        ZkCfg.find_command = nil
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
}
return M

