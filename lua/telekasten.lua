local builtin = require "telescope.builtin"

local actions = require("telescope.actions")
local action_state = require "telescope.actions.state"

-- declare locals for the nvim api stuff to avoid more lsp warnings
local vim = vim 
local api = api

-- DEFAULT CONFIG
ZkCfg = {
     home         = vim.fn.expand("~/zettelkasten"),
     dailies      = vim.fn.expand("~/zettelkasten/daily"),
     extension    = ".md",
     daily_finder = "daily_finder.sh",

     -- where to install the daily_finder,
     -- (must be a dir in your PATH)
     my_bin       = vim.fn.expand('~/bin'),

     -- download tool for daily_finder installation: curl or wget
     downloader = 'curl',
     -- downloader = 'wget',  -- wget is supported, too
 }

local downloader2cmd = {
    curl = 'curl -o',
    wget = 'wget -O',
}


-- InstallDailyFinder
-- downloads the daily finder scripts to the configured `my_bin` directory
-- and makes it executable
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
--
-- Select from daily notes
--
FindDailyNotes = function(opts)
    opts = {} or opts
    if (check_local_finder() == true) then
            builtin.find_files({
            prompt_title = "Find daily note",
            cwd = ZkCfg.dailies,
            find_command = { ZkCfg.daily_finder },
            entry_maker = zk_entry_maker,
       })
   end
end


--
-- InsertLink:
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
        find_command = { ZkCfg.daily_finder },
        entry_maker = zk_entry_maker,
   })
end

--
-- FollowLink:
--
-- find the file linked to by the word under the cursor
--
FollowLink = function(opts)
    opts = {} or opts
    vim.cmd('normal yi]')
    local word = vim.fn.getreg('"0')
    builtin.find_files({
        prompt_title = "Follow link to note...",
        cwd = ZkCfg.home,
        default_text = word,
        find_command = { ZkCfg.daily_finder },
        entry_maker = zk_entry_maker,
   })
end


GotoToday = function(opts)
    print('local version')
    opts = {} or opts
    local word = os.date("%Y-%m-%d")
    builtin.find_files({
        prompt_title = "Follow link to note...",
        cwd = ZkCfg.home,
        default_text = word,
        find_command = { ZkCfg.daily_finder },
        entry_maker = zk_entry_maker,
   })
end

--
-- FindNotes:
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
        find_command = { ZkCfg.daily_finder },
   })
end

local function file_exists(name)
   local f=io.open(name,"r")
   if f~=nil then io.close(f) return true else return false end
end

local create_note_by_tilte = function (title)
  -- set the filename based on the current date
  -- local filepath = vim.g['wiki_root']..'journal/'..os.date('%Y-%m-%d')..'.md'
  local filepath = ZkCfg.home

  -- if the file doesn't exist
  -- then created file and write date to the top of the file
  if not file_exists(filepath) then
    local file = io.open(filepath, 'a')
    io.output(file)
    io.write(os.date("# %a, %d %B '%y"))
    io.close(file)
  end
  api.nvim_command('edit '..filepath)
end

--[[
-- interesting snippet:
    function file_exists(name)
       local f=io.open(name,"r")
       if f~=nil then io.close(f) return true else return false end
    end

    local api = vim.api
    local M = {}
    function M.currentEntry()

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



-- setup(cfg)
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
}
print('local version')
return M
