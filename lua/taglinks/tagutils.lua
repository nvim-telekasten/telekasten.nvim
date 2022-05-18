local Job = require("plenary.job")

local M = {}
local hashtag_re =
    "(^|\\s|'|\")((?!(#[a-fA-F0-9]{3})(\\W|$)|(#[a-fA-F0-9]{6})(\\W|$))#[a-zA-ZÀ-ÿ]+[a-zA-ZÀ-ÿ0-9/\\-_]*)"
local colon_re = "(^|\\s):[a-zA-ZÀ-ÿ]+[a-zA-ZÀ-ÿ0-9/\\-_]*:"
local yaml_re =
    "(^|\\s)tags:\\s*\\[([a-zA-ZÀ-ÿ]+[a-zA-ZÀ-ÿ0-9/\\-_]*(,\\s)*)*]"

local function command_find_all_tags(opts)
    opts = opts or {}
    opts.cwd = opts.cwd or "."
    opts.templateDir = opts.templateDir or ""

    -- do not list tags in the template directory
    local globArg = ""
    if opts.templateDir ~= "" then
        globArg = "--glob=!" .. "**/" .. opts.templateDir .. "/*.md"
    end

    local re = hashtag_re

    if opts.tag_notation == ":tag:" then
        re = colon_re
    end

    if opts.tag_notation == "yaml-bare" then
        re = yaml_re
    end

    return "rg",
        {
            "--vimgrep",
            "--pcre2",
            globArg,
            "-o",
            re,
            "--",
            opts.cwd,
        }
end

-- strips away leading ' or " , then trims whitespace
local function trim(s)
    if s:sub(1, 1) == '"' or s:sub(1, 1) == "'" then
        s = s:sub(2)
    end
    return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

local function insert_tag(tbl, tag, entry)
    entry.t = tag
    if tbl[tag] == nil then
        tbl[tag] = { entry }
    else
        tbl[tag][#tbl[tag] + 1] = entry
    end
end

local function split(line, sep, n)
    local startpos = 0
    local endpos
    local ret = {}
    for _ = 1, n - 1 do
        endpos = line:find(sep, startpos + 1)
        ret[#ret + 1] = line:sub(startpos + 1, endpos - 1)
        startpos = endpos
    end
    -- now the remainder
    ret[n] = line:sub(startpos + 1)
    return ret
end

local function yaml_to_tags(line, entry, ret)
    local _, startpos = line:find("tags%s*:%s*%[")
    local global_end = line:find("%]")

    line = line:sub(startpos + 1, global_end)

    local i = 1
    local j
    local prev_i = 1
    local tag
    while true do
        i, j = line:find("%s*.*%s*,", i)
        if i == nil then
            tag = line:sub(prev_i)
            tag = tag:gsub("%s*(.*)%s*", "%1")
        else
            tag = line:sub(i, j)
            tag = tag:gsub("%s*(.*)%s*,", "%1")
        end

        local new_entry = {}

        -- strip trailing ]
        tag = tag:gsub("]", "")
        new_entry.t = tag
        new_entry.l = entry.l
        new_entry.fn = entry.fn
        new_entry.c = startpos + (i or prev_i)
        insert_tag(ret, tag, new_entry)
        if i == nil then
            break
        end
        i = j + 1
        prev_i = i
    end
end

local function parse_entry(opts, line, ret)
    local s = split(line, ":", 4)
    local fn, l, c, t = s[1], s[2], s[3], s[4]

    t = trim(t)
    local entry = { fn = fn, l = l, c = c }

    if opts.tag_notation == "yaml-bare" then
        yaml_to_tags(t, entry, ret)
    elseif opts.tag_notation == ":tag:" then
        insert_tag(ret, t, entry)
    else
        insert_tag(ret, t, entry)
    end
end

M.do_find_all_tags = function(opts)
    local cmd, args = command_find_all_tags(opts)
    --print(cmd .. " " .. vim.inspect(args))
    local ret = {}
    local _ = Job
        :new({
            command = cmd,
            args = args,
            enable_recording = true,
            on_exit = function(j, return_val)
                if return_val == 0 then
                    for _, line in pairs(j:result()) do
                        parse_entry(opts, line, ret)
                    end
                else
                    print("rg return value: " .. tostring(return_val))
                    print("stderr: ", vim.inspect(j:stderr_result()))
                end
            end,
            on_stderr = function(err, data, _)
                print("error: " .. tostring(err) .. "data: " .. data)
            end,
        })
        :sync()
    -- print("final results: " .. vim.inspect(ret))
    return ret
end
return M
