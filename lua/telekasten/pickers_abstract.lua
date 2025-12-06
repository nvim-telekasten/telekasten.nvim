local M = {}

-- Helper to resolve paths to absolute paths
function M.resolve_path(path, cwd)
  if not path or path == '' then return nil end -- Handle nil or empty paths
  cwd = cwd or vim.fn.getcwd()

  -- Check if the path is already absolute (handles Unix and Windows paths)
  -- Unix: starts with /
  -- Windows: starts with C:/ or C:\
  local is_absolute = path:match("^/.*") or path:match("^[A-Za-z]:[/\\]?.*")

  local resolved_path
  if is_absolute then
    resolved_path = vim.fn.fnamemodify(path, ":p")
  else
    -- Join cwd and path, then normalize
    -- Ensure consistent path separators before joining
    local joined_path = cwd .. '/' .. path
    resolved_path = vim.fn.fnamemodify(joined_path, ":p")
  end

  -- For Windows compatibility, ensure forward slashes
  resolved_path = resolved_path:gsub('\\', '/')

  return resolved_path
end

-- declare locals for the nvim api stuff to avoid more lsp warnings
local vim = vim or {
  notify = function(msg, level) print("Notify:", msg) end,
  log = { levels = { ERROR = 1 } }
}

-- Picker abstraction layer for fzf-lua, telescope, and snacks.nvim
-- Provides a unified interface for Telekasten pickers

-- Configuration
M.config = {
  -- Default picker to use: "telescope", "fzf", or "snacks"
  default = "telescope",
  
  -- Picker-specific configurations
  telescope = {
    -- Telescope-specific options
  },
  
  fzf = {
    -- Fzf-lua specific options
  },
  
  snacks = {
    -- Snacks.nvim specific options
  }
}

-- Initialize the picker abstraction
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

-- Get the currently configured picker backend with fallback
function M.get_picker()
  local configured_picker = M.config.default
  local available_pickers = {
    telescope = pcall(require, "telescope"),
    fzf = pcall(require, "fzf-lua"),
    snacks = pcall(require, "snacks"),
  }

  if available_pickers[configured_picker] then
    return configured_picker
  else
    vim.notify(
      "Configured picker '" .. configured_picker .. "' is not available. Falling back to 'telescope'.",
      vim.log.levels.WARN
    )
    if available_pickers.telescope then
      M.config.default = "telescope"
      return "telescope"
    else
      vim.notify(
        "No picker backend is available. Please install 'telescope.nvim', 'fzf-lua', or 'snacks.nvim'.",
        vim.log.levels.ERROR
      )
      return nil -- No functional picker available
    end
  end
end

-- Set the picker backend
function M.set_picker(backend)
  if backend ~= "telescope" and backend ~= "fzf" and backend ~= "snacks" then
    vim.notify("Invalid picker backend: " .. backend, vim.log.levels.ERROR)
    return
  end
  M.config.default = backend
end

-- Core picker functions that work across all backends

-- Find files picker
function M.find_files(opts)
  opts = opts or {}
  return M.find_files_with_options(opts)
end

-- Grep picker (live grep)
function M.grep_string(opts)
  opts = opts or {}
  return M.live_grep_with_options(opts)
end

-- Select from a generic list of strings (e.g., file paths)
function M.select_from_list(list, opts)
  opts = vim.tbl_extend("force", { prompt_title = "Select Item", on_select = nil }, opts or {})
  local picker = M.get_picker()

  if not picker then return end

  if picker == "telescope" then
    return M._telescope_select_from_list(list, opts)
  elseif picker == "fzf" then
    return M._fzf_select_from_list(list, opts)
  elseif picker == "snacks" then
    return M._snacks_select_from_list(list, opts)
  else
    vim.notify("Unsupported picker backend for select_from_list: " .. picker, vim.log.levels.ERROR)
  end
end

-- Telekasten-specific find files picker with options
-- Supports Telekasten-specific parameters like search_pattern, filter_extensions, preview_type, etc.
function M.find_files_with_options(opts)
  opts = opts or {}
  local picker = M.get_picker()

  if not picker then return end
  
  if picker == "telescope" then
    return M._telescope_find_files_with_options(opts)
  elseif picker == "fzf" then
    return M._fzf_find_files_with_options(opts)
  elseif picker == "snacks" then
    return M._snacks_find_files_with_options(opts)
  else
    vim.notify("Unsupported picker backend for find_files_with_options: " .. picker, vim.log.levels.ERROR)
  end
end

-- Telekasten-specific live grep picker with options
-- Supports Telekasten-specific parameters like default_text, search_dirs, etc.
function M.live_grep_with_options(opts)
  opts = opts or {}
  local picker = M.get_picker()

  if not picker then return end
  
  if picker == "telescope" then
    return M._telescope_live_grep_with_options(opts)
  elseif picker == "fzf" then
    return M._fzf_live_grep_with_options(opts)
  elseif picker == "snacks" then
    return M._snacks_live_grep_with_options(opts)
  else
    vim.notify("Unsupported picker backend for live_grep_with_options: " .. picker, vim.log.levels.ERROR)
  end
end

-- Buffers picker
function M.buffers(opts)
  opts = opts or {}
  local picker = M.get_picker()

  if not picker then return end
  
  if picker == "telescope" then
    return M._telescope_buffers(opts)
  elseif picker == "fzf" then
    return M._fzf_buffers(opts)
  elseif picker == "snacks" then
    return M._snacks_buffers(opts)
  else
    vim.notify("Unsupported picker backend for buffers: " .. picker, vim.log.levels.ERROR)
  end
end

-- Tags picker
function M.tags(opts)
  opts = opts or {}
  local picker = M.get_picker()

  if not picker then return end
  
  if picker == "telescope" then
    return M._telescope_tags(opts)
  elseif picker == "fzf" then
    return M._fzf_tags(opts)
  elseif picker == "snacks" then
    return M._snacks_tags(opts)
  else
    vim.notify("Unsupported picker backend for tags: " .. picker, vim.log.levels.ERROR)
  end
end

-- Telescope implementations
function M._telescope_find_files(opts)
  local builtin = require("telescope.builtin")
  builtin.find_files(opts)
end

function M._telescope_grep_string(opts)
  local builtin = require("telescope.builtin")
  builtin.grep_string(opts)
end

function M._telescope_buffers(opts)
  local builtin = require("telescope.builtin")
  builtin.buffers(opts)
end

function M._telescope_tags(opts)
  local builtin = require("telescope.builtin")
  builtin.tags(opts)
end

function M._telescope_select_from_list(list, opts)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local list_opts = vim.tbl_extend("force", {
    prompt_title = opts.prompt_title,
    finder = finders.new_table({
      results = list,
      entry_maker = opts.entry_maker or function(entry)
        return { value = entry, display = entry, ordinal = entry }
      end,
    }),
    sorter = opts.sorter or conf.generic_sorter({}),
    previewer = opts.previewer,
  }, M.config.telescope, opts)

  list_opts.attach_mappings = function(prompt_bufnr, map)
    if opts.on_select then
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if selection then
          opts.on_select(selection.value)
        end
      end)
    end
    if opts.attach_mappings then
      opts.attach_mappings(prompt_bufnr, map)
    end
    return true
  end

  pickers.new({}, list_opts):find()
end

-- Fzf-lua implementations
function M._fzf_find_files(opts)
  local fzf = require("fzf-lua")
  fzf.files(opts)
end

function M._fzf_grep_string(opts)
  local fzf = require("fzf-lua")
  fzf.grep(opts)
end

function M._fzf_buffers(opts)
  local fzf = require("fzf-lua")
  fzf.buffers(opts)
end

function M._fzf_tags(opts)
  local fzf = require("fzf-lua")
  fzf.btags(opts)  -- btags for buffer tags
end

function M._fzf_select_from_list(list, opts)
  local fzf = require("fzf-lua")

  local fzf_opts = vim.tbl_extend("force", {
    prompt = opts.prompt_title,
    file_icons = true, -- Enable devicons
    actions = {
      ["default"] = function(selected, fzf_opts_passed)
        if opts.on_select and selected[1] then
          opts.on_select(selected[1])
        end
      end,
    },
    -- Pass find_command and sort if available in opts
    cmd = opts.find_command or nil,
    sort = opts.sort or nil,
  }, M.config.fzf, opts)

  fzf.fzf_exec(list, fzf_opts)
end

-- Snacks.nvim implementations
function M._snacks_find_files(opts)
  local snacks = require("snacks")
  snacks.picker.files(opts)
end

function M._snacks_grep_string(opts)
  local snacks = require("snacks")
  snacks.picker.grep(opts)
end

function M._snacks_buffers(opts)
  local snacks = require("snacks")
  snacks.picker.buffers(opts)
end

function M._snacks_tags(opts)
  local snacks = require("snacks")
  snacks.picker.tags(opts)
end

function M._snacks_select_from_list(list, opts)
  local snacks = require("snacks")

  local snacks_opts = vim.tbl_extend("force", {
    prompt = opts.prompt_title,
    icons = true, -- Enable devicons
    confirm = function(selected)
      if opts.on_select and selected then
        opts.on_select(selected.value)
      end
    end,
    -- Pass find_command and sort if available in opts
    cmd = opts.find_command or nil,
    args = opts.find_command and { opts.find_command } or nil, -- Snacks might need cmd in args
    sort = opts.sort or nil,
  }, M.config.snacks, opts)

  snacks.picker.select(list, snacks_opts)
end

-- Enhanced picker functions with Telekasten-specific behavior

-- Telekasten-specific find files with options
function M._telescope_find_files_with_options(opts)
  local builtin = require("telescope.builtin")
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local find_opts = vim.tbl_extend("force", {
    prompt_title = opts.prompt_title,
    cwd = opts.cwd,
    find_command = opts.find_command,
    search_pattern = opts.search_pattern,
    search_depth = opts.search_depth,
    preview_type = opts.preview_type,
    default_text = opts.default_text,
    sort = opts.sort,
  }, M.config.telescope, opts) -- Merge Telekasten config and user opts

  if opts.filter_extensions then
    find_opts.file_ignore_patterns = {}
    for _, ext in ipairs(opts.filter_extensions) do
      table.insert(find_opts.file_ignore_patterns, "*" .. ext)
    end
  end

  -- Handle on_select callback for Telescope
  find_opts.attach_mappings = function(prompt_bufnr, map)
    -- If on_select is provided, replace the default action
    if opts.on_select then
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if selection then
          local path = selection.filename or selection.value
          opts.on_select(M.resolve_path(path, find_opts.cwd))
        end
      end)
    end

    -- If attach_mappings is provided, call it to set up additional keys
    if opts.attach_mappings then
      opts.attach_mappings(prompt_bufnr, map)
    end
    return true
  end

  builtin.find_files(find_opts)
end

function M._fzf_find_files_with_options(opts)
  local fzf = require("fzf-lua")

  local fzf_opts = vim.tbl_extend("force", {
    prompt = opts.prompt_title,
    cwd = opts.cwd,
    cmd = opts.find_command,
    sort = opts.sort,
  }, M.config.fzf, opts) -- Merge Telekasten config and user opts

  -- Handle on_select callback for fzf-lua
  if opts.on_select then
    fzf_opts.actions = {
      ["default"] = function(selected, fzf_opts_passed)
        if selected[1] then
          opts.on_select(M.resolve_path(selected[1], fzf_opts.cwd))
        end
      end
    }
  elseif opts.attach_mappings then
    -- fzf-lua uses actions instead of attach_mappings
    -- This is a simplification, as Telekasten's attach_mappings is Telescope-specific
    -- We might need a more complex mapping if we want full compatibility
  end

  fzf.files(fzf_opts)
end

function M._snacks_find_files_with_options(opts)
  local snacks = require("snacks")

  local snacks_opts = vim.tbl_extend("force", {
    prompt = opts.prompt_title,
    cwd = opts.cwd,
    cmd = opts.find_command or nil,
    args = opts.find_command and { opts.find_command } or nil, -- Snacks might need cmd in args
    sort = opts.sort or nil,
  }, M.config.snacks, opts) -- Merge Telekasten config and user opts

  if opts.search_pattern then
    snacks_opts.search = opts.search_pattern
  end

  -- Handle on_select callback for Snacks.nvim
  if opts.on_select then
    snacks_opts.confirm = function(selected)
      if selected then
        opts.on_select(M.resolve_path(selected.file, snacks_opts.cwd))
      end
    end
  elseif opts.attach_mappings then
    -- snacks uses confirm/actions instead of attach_mappings
  end

  snacks.picker.files(snacks_opts)
end

-- Telekasten-specific live grep with options
function M._telescope_live_grep_with_options(opts)
  local builtin = require("telescope.builtin")
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local grep_opts = vim.tbl_extend("force", {
    prompt_title = opts.prompt_title,
    cwd = opts.cwd,
    find_command = opts.find_command,
    default_text = opts.default_text,
    search_dirs = opts.search_dirs,
    sort = opts.sort,
  }, M.config.telescope, opts) -- Merge Telekasten config and user opts

  -- Handle on_select callback for Telescope
  grep_opts.attach_mappings = function(prompt_bufnr, map)
    -- If on_select is provided, replace the default action
    if opts.on_select then
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if selection then
          local path = selection.filename or selection.value
          opts.on_select(M.resolve_path(path, grep_opts.cwd))
        end
      end)
    end

    -- If attach_mappings is provided, call it to set up additional keys
    if opts.attach_mappings then
      opts.attach_mappings(prompt_bufnr, map)
    end
    return true
  end

  builtin.live_grep(grep_opts)
end

function M._fzf_live_grep_with_options(opts)
  local fzf = require("fzf-lua")

  local fzf_opts = vim.tbl_extend("force", {
    prompt = opts.prompt_title,
    cwd = opts.cwd,
    search = opts.default_text,
    cmd = opts.find_command,
    sort = opts.sort,
  }, M.config.fzf, opts) -- Merge Telekasten config and user opts

  -- Handle on_select callback for fzf-lua
  if opts.on_select then
    fzf_opts.actions = vim.tbl_extend("force", fzf_opts.actions or {}, {
      ["default"] = function(selected, fzf_opts_passed)
        if selected[1] then
          opts.on_select(M.resolve_path(selected[1], fzf_opts.cwd))
        end
      end
    })
  end

  fzf.live_grep(fzf_opts)
end

function M._snacks_live_grep_with_options(opts)
  local snacks = require("snacks")

  local snacks_opts = vim.tbl_extend("force", {
    prompt = opts.prompt_title,
    cwd = opts.cwd,
    search = opts.default_text,
    cmd = opts.find_command or nil,
    args = opts.find_command and { opts.find_command } or nil, -- Snacks might need cmd in args
    sort = opts.sort or nil,
  }, M.config.snacks, opts) -- Merge Telekasten config and user opts

  -- Handle on_select callback for Snacks.nvim
  if opts.on_select then
    snacks_opts.confirm = function(selected)
      if selected then
        opts.on_select(M.resolve_path(selected.file, snacks_opts.cwd))
      end
    end
  end

  snacks.picker.grep(snacks_opts)
end

-- Select a file and return just the path (for Telekasten link creation)
function M.select_file_path(prompt, cwd, on_confirm)
  local picker = M.get_picker()

  if not picker then return end
  
  if picker == "telescope" then
    return M._telescope_select_file_path(prompt, cwd, on_confirm)
  elseif picker == "fzf" then
    return M._fzf_select_file_path(prompt, cwd, on_confirm)
  elseif picker == "snacks" then
    return M._snacks_select_file_path(prompt, cwd, on_confirm)
  else
    vim.notify("Unsupported picker backend for select_file_path: " .. picker, vim.log.levels.ERROR)
  end
end

-- Select a file and open it for editing
function M.select_and_edit_file(prompt, cwd)
  local picker = M.get_picker()

  if not picker then return end
  
  if picker == "telescope" then
    return M._telescope_select_and_edit_file(prompt, cwd)
  elseif picker == "fzf" then
    return M._fzf_select_and_edit_file(prompt, cwd)
  elseif picker == "snacks" then
    return M._snacks_select_and_edit_file(prompt, cwd)
  else
    vim.notify("Unsupported picker backend for select_and_edit_file: " .. picker, vim.log.levels.ERROR)
  end
end

-- Telescope implementations for enhanced functions
function M._telescope_select_file_path(prompt, cwd, on_confirm)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  
   -- Determine which find command to use
   local find_cmd = "find"  -- default fallback
   if vim.fn.executable("fd") == 1 then
     find_cmd = "fd"
   elseif vim.fn.executable("fdfind") == 1 then
     find_cmd = "fdfind"
   elseif vim.fn.executable("rg") == 1 then
     find_cmd = "rg"
   end
   
   pickers.new({}, {
     prompt_title = prompt,
     finder = finders.new_oneshot_job(find_cmd, {
       "--type", "f", "--hidden", "--exclude", ".git"
     }, {
       cwd = cwd
     }),
      sorter = conf.generic_sorter({}),
     attach_mappings = function(prompt_bufnr, map)
       actions.select_default:replace(function()
         local selection = action_state.get_selected_entry()
         actions.close(prompt_bufnr)
         if on_confirm and selection then
            on_confirm(M.resolve_path(selection.value, cwd))  -- Return just the path
         end
       end)
       return true
     end,
   }):find()
end

function M._telescope_select_and_edit_file(prompt, cwd)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  
  pickers.new({}, {
      prompt_title = prompt,
      finder = finders.new_oneshot_job(function()
        -- Determine which find command to use
        local find_cmd
        if vim.fn.executable("fd") == 1 then
          find_cmd = "fd"
        elseif vim.fn.executable("fdfind") == 1 then
          find_cmd = "fdfind"
        elseif vim.fn.executable("rg") == 1 then
          find_cmd = "rg"
        else
          find_cmd = "find"
        end
        return {find_cmd, "--type", "f", "--hidden", "--exclude", ".git"}, {cwd = cwd}
      end),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local selection = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if selection and selection.value then
          vim.cmd("edit " .. vim.fn.fnameescape(M.resolve_path(selection.value, cwd)))
        end
      end)
      return true
    end,
  }):find()
end

-- Fzf-lua implementations for enhanced functions
function M._fzf_select_file_path(prompt, cwd, on_confirm)
  local fzf = require("fzf-lua")
  
  fzf.files({
    prompt = prompt,
    cwd = cwd,
    actions = {
      ["default"] = function(selected, opts)
        if on_confirm and selected[1] then
          on_confirm(M.resolve_path(selected[1], cwd))  -- Return just the path
        end
      end
    }
  })
end

function M._fzf_select_and_edit_file(prompt, cwd)
  local fzf = require("fzf-lua")
  
  fzf.files({
    prompt = prompt,
    cwd = cwd,
    actions = {
      ["default"] = function(selected, opts)
        if selected[1] then
          vim.cmd("edit " .. vim.fn.fnameescape(M.resolve_path(selected[1], cwd)))
        end
      end
    }
  })
end

-- Snacks.nvim implementations for enhanced functions
function M._snacks_select_file_path(prompt, cwd, on_confirm)
  local snacks = require("snacks")
  
  snacks.picker.files({
    prompt = prompt,
    cwd = cwd,
    confirm = function(selected)
      if on_confirm and selected then
        on_confirm(M.resolve_path(selected.file, cwd))  -- Return just the path
      end
    end
  })
end

function M._snacks_select_and_edit_file(prompt, cwd)
  local snacks = require("snacks")
  
  snacks.picker.files({
    prompt = prompt,
    cwd = cwd,
    confirm = function(selected)
      if selected then
        vim.cmd("edit " .. vim.fn.fnameescape(M.resolve_path(selected.file, cwd)))
      end
    end
  })
end

return M