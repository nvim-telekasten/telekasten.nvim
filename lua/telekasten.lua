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
     home         = "~/zettelkasten",
     dailies      = "~/zettelkasten/daily",
     extension    = ".md",
     daily_finder = "undaily_finder.sh",
     
     -- where to install the daily_finder, 
     -- (must be a dir in your PATH)
     my_bin       = '~/bin',   

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



-- 
-- find_daily_notes:
-- 
-- Select from daily notes
-- 
find_daily_notes = function(opts)
    builtin.find_files({
    prompt_title = "Find daily note",
    cwd = zkcfg.dailies,
    find_command = { zkcfg.daily_finder },
    entry_maker = zk_entry_maker,
   })
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
        entry_maker = zk_entry_maker,
   })
end

-- 
-- follow_link:
-- 
-- find the file linked to by the word under the cursor
-- 
follow_link = function(opts)
    builtin.find_files({
        prompt_title = "Follow link to note...",
        cwd = zkcfg.home,
        default_text = vim.fn.expand("<cword>"),
        entry_maker = zk_entry_maker,
   })
end

-- 
-- find_notes:
-- 
-- Select from daily notes
-- 
local find_notes = function(opts)
  local find_command = opts.find_command
  local hidden = opts.hidden
  local no_ignore = opts.no_ignore
  local follow = opts.follow
  local search_dirs = opts.search_dirs

  if search_dirs then
    for k, v in pairs(search_dirs) do
      search_dirs[k] = vim.fn.expand(v)
    end
  end

  if not find_command then
    if 1 == vim.fn.executable "fd" then
      find_command = { "fd", "--type", "f" }
      if hidden then
        table.insert(find_command, "--hidden")
      end
      if no_ignore then
        table.insert(find_command, "--no-ignore")
      end
      if follow then
        table.insert(find_command, "-L")
      end
      if search_dirs then
        table.insert(find_command, ".")
        for _, v in pairs(search_dirs) do
          table.insert(find_command, v)
        end
      end
    elseif 1 == vim.fn.executable "fdfind" then
      find_command = { "fdfind", "--type", "f" }
      if hidden then
        table.insert(find_command, "--hidden")
      end
      if no_ignore then
        table.insert(find_command, "--no-ignore")
      end
      if follow then
        table.insert(find_command, "-L")
      end
      if search_dirs then
        table.insert(find_command, ".")
        for _, v in pairs(search_dirs) do
          table.insert(find_command, v)
        end
      end
    elseif 1 == vim.fn.executable "rg" then
      find_command = { "rg", "--files" }
      if hidden then
        table.insert(find_command, "--hidden")
      end
      if no_ignore then
        table.insert(find_command, "--no-ignore")
      end
      if follow then
        table.insert(find_command, "-L")
      end
      if search_dirs then
        for _, v in pairs(search_dirs) do
          table.insert(find_command, v)
        end
      end
    elseif 1 == vim.fn.executable "find" and vim.fn.has "win32" == 0 then
      find_command = { "find", ".", "-type", "f" }
      if not hidden then
        table.insert(find_command, { "-not", "-path", "*/.*" })
        find_command = flatten(find_command)
      end
      if no_ignore ~= nil then
        log.warn "The `no_ignore` key is not available for the `find` command in `find_files`."
      end
      if follow then
        table.insert(find_command, "-L")
      end
      if search_dirs then
        table.remove(find_command, 2)
        for _, v in pairs(search_dirs) do
          table.insert(find_command, 2, v)
        end
      end
    elseif 1 == vim.fn.executable "where" then
      find_command = { "where", "/r", ".", "*" }
      if hidden ~= nil then
        log.warn "The `hidden` key is not available for the Windows `where` command in `find_files`."
      end
      if no_ignore ~= nil then
        log.warn "The `no_ignore` key is not available for the Windows `where` command in `find_files`."
      end
      if follow ~= nil then
        log.warn "The `follow` key is not available for the Windows `where` command in `find_files`."
      end
      if search_dirs ~= nil then
        log.warn "The `search_dirs` key is not available for the Windows `where` command in `find_files`."
      end
    end
  end

  if not find_command then
    print(
      "You need to install either find, fd, or rg. "
        .. "You can also submit a PR to add support for another file finder :)"
    )
    return
  end

  if opts.cwd then
    opts.cwd = vim.fn.expand(opts.cwd)
  end

  opts.entry_maker = opts.entry_maker or make_entry.gen_from_file(opts)

  pickers.new(opts, {
    prompt_title = "Find Files",
    finder = finders.new_oneshot_job(find_command, opts),
    previewer = conf.file_previewer(opts),
    sorter = conf.file_sorter(opts),
  }):find()
end


--[[
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
    find_daily_notes = find_daily_notes,
    insert_link = insert_link,
    follow_link = follow_link,
    find_notes = find_filenames,
    setup = setup,
    install_daily_finder = install_daily_finder,
}
print("telekasten reloaded")
return M
