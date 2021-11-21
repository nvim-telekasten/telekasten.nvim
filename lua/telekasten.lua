local pickers = require "telescope.pickers"
local finders = require "telescope.finders"
local sorters = require "telescope.sorters"
local previewers = require "telescope.previewers"
local conf = require("telescope.config").values
local builtin = require "telescope.builtin"

local actions = require("telescope.actions")
local action_state = require "telescope.actions.state"

-- DEFAULT CONFIG
zkcfg = {
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


-- install_daily_finder
-- downloads the daily finder scripts to the configured `my_bin` directory
-- and makes it executable
install_daily_finder = function()
    local destpath = zkcfg.my_bin .. '/' .. zkcfg.daily_finder
    local cmd = downloader2cmd[zkcfg.downloader]
    vim.api.nvim_command('!'.. cmd .. ' ' .. destpath .. ' https://raw.githubusercontent.com/renerocksai/telekasten/main/ext_commands/daily_finder.sh')
    vim.api.nvim_command('!chmod +x ' .. destpath)
end

local path_to_linkname = function(p)
    local fn = vim.split(p, "/")
    fn = fn[#fn]
    fn = vim.split(fn, zkcfg.extension)
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
    local ret = vim.fn.system(zkcfg.daily_finder .. ' check')
    return ret ==  "OK\n" 
    -- return vim.fn.executable(zkcfg.daily_finder) == 1
end

-- 
-- find_daily_notes:
-- 
-- Select from daily notes
-- 
find_daily_notes = function(opts)
    if (check_local_finder() == true) then 
            builtin.find_files({
            prompt_title = "Find daily note",
            cwd = zkcfg.dailies,
            find_command = { zkcfg.daily_finder },
            entry_maker = zk_entry_maker,
       })
   end
end


-- 
-- insert_link:
-- 
-- Select from all notes and put a link in the current buffer
-- 
insert_link = function(opts)
    builtin.find_files({
        prompt_title = "Insert link to note",
        cwd = zkcfg.home,
        attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                local fn = path_to_linkname(selection.value)
                vim.api.nvim_put({ "[["..fn.."]]" }, "", false, true)
            end)
            return true
        end,
        find_command = { zkcfg.daily_finder },
        entry_maker = zk_entry_maker,
   })
end

-- 
-- follow_link:
-- 
-- find the file linked to by the word under the cursor
-- 
follow_link = function(opts)
    vim.cmd('normal yi]')
    local word = vim.fn.getreg('"0')
    builtin.find_files({
        prompt_title = "Follow link to note...",
        cwd = zkcfg.home,
        default_text = word,
        find_command = { zkcfg.daily_finder },
        entry_maker = zk_entry_maker,
   })
end


goto_today = function(opts)
    local word = os.date("%Y-%m-%d")
    builtin.find_files({
        prompt_title = "Follow link to note...",
        cwd = zkcfg.home,
        default_text = word,
        find_command = { zkcfg.daily_finder },
        entry_maker = zk_entry_maker,
   })
end

-- 
-- find_notes:
-- 
-- Select from notes
-- 
find_notes = function(opts)
    builtin.find_files({
        prompt_title = "Find notes by name",
        cwd = zkcfg.home,
        find_command = { zkcfg.daily_finder },
        entry_maker = zk_entry_maker,
   })
end

-- 
-- search_notes:
-- 
-- find the file linked to by the word under the cursor
-- 
search_notes = function(opts)
    builtin.live_grep({
        prompt_title = "Search in notes",
        cwd = zkcfg.home,
        search_dirs = { zkcfg.home },
        default_text = vim.fn.expand("<cword>"),
        find_command = { zkcfg.daily_finder },
   })
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
setup = function(cfg) 
    cfg = cfg or {}
   for k, v in pairs(cfg) do
       zkcfg[k] = v
   end
end

local M = {
    zkcfg = zkcfg,
    find_notes = find_notes,
    find_daily_notes = find_daily_notes,
    search_notes = search_notes,
    insert_link = insert_link,
    follow_link = follow_link,
    setup = setup,
    install_daily_finder = install_daily_finder,
    goto_today = goto_today,
}
print("telekasten reloaded")
return M
