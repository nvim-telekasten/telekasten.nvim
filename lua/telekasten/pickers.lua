-- lua/telekasten/pickers.lua
-- Updated to use picker abstraction

local M = {}

local picker = require("telekasten.picker")

-- Pick between the various configured vaults
function M.vaults(telekasten, opts)
    opts = opts or {}
    local vaults = telekasten.vaults
    local _vaults = {}

    for k, v in pairs(vaults) do
        table.insert(_vaults, { k, v })
    end

    picker.custom_picker({
        prompt_title = "Vaults",
        results = _vaults,
        entry_maker = function(entry)
            return {
                value = entry,
                display = entry[1],
                ordinal = entry[1],
            }
        end,
        attach_mappings = function(prompt_bufnr, map)
            map("i", "<cr>", function()
                local selection = picker.actions.get_selection()
                picker.actions.close()(prompt_bufnr)
                telekasten.chdir(selection.value[2])
            end)
            map("n", "<cr>", function()
                local selection = picker.actions.get_selection()
                picker.actions.close()(prompt_bufnr)
                telekasten.chdir(selection.value[2])
            end)
            return true
        end,
    })
end

return M
