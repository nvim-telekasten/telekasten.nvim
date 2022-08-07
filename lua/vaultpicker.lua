local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values

local M = {}
local vaults = function(telekasten, opts)
    opts = opts or {}
    local vaults = telekasten.vaults
    local _vaults = {}
    for k, v in pairs(vaults) do
        table.insert(_vaults, { k, v })
    end
    pickers.new(opts, {
        prompt_title = "Vaults",
        finder = finders.new_table({
            results = _vaults,
            entry_maker = function(entry)
                return {
                    value = entry,
                    display = entry[1],
                    ordinal = entry[1],
                }
            end,
        }),
        sorter = conf.generic_sorter(opts),
        attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                -- print(vim.inspect(selection))
                telekasten.chdir(selection.value[2])
            end)
            return true
        end,
    }):find()
end

M.vaults = vaults

return M
