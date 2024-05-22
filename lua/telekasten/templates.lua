-- Template handling

local dateutils = require("telekasten.utils.dates")

local M = {}
local vim = vim

function M.subst_templated_values(line, title, dates, uuid, calendar_monday)
    -- Various date formats
    if dates == nil then
        dates = dateutils.calculate_dates(nil, calendar_monday)
    end

    -- {{uuid}}: note UUID if any
    if uuid == nil then
        uuid = ""
    end

    -- {{shorttitle}}: only filename, not full subdir paths
    local shorttitle = string.match(title, "^.+/(.+)$")
    if shorttitle == nil then
        shorttitle = title
    end

    -- Expend the substitutions table and proceed
    local substs = vim.tbl_extend("error", dates, {
        title = title:gsub("^%l", string.upper),
        shorttitle = shorttitle:gsub("^%l", string.upper),
        uuid = uuid,
    })

    for k, v in pairs(substs) do
        line = line:gsub("{{" .. k .. "}}", v)
    end

    return line
end

return M
