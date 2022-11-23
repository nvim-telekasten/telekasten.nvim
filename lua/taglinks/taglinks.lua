local M = {}

M.is_tag_or_link_at = function(line, col, opts)
    opts = opts or {}
    local initial_col = col

    local char
    local is_tagline = opts.tag_notation == "yaml-bare"
        and line:sub(1, 4) == "tags"

    local seen_bracket = false
    local seen_parenthesis = false
    local seen_hashtag = false
    local cannot_be_tag = false

    -- Solves [[Link]]
    --     at ^
    -- In this case we try to move col forward to match the link.
    if "[" == line:sub(col, col) then
        col = math.max(col + 1, string.len(line))
    end

    while col >= 1 do
        char = line:sub(col, col)

        if seen_bracket then
            if char == "[" then
                return "link", col + 2
            end
        end

        if seen_parenthesis then
            -- Media link, currently identified by not link nor tag
            if char == "]" then
                return nil, nil
            end
        end

        if char == "[" then
            seen_bracket = true
        elseif char == "(" then
            seen_parenthesis = true
        end

        if is_tagline == true then
            if char == " " or char == "\t" or char == "," or char == ":" then
                if col ~= initial_col then
                    return "tag", col + 1
                end
            end
        else
            if char == "#" then
                seen_hashtag = true
            end
            -- Tags should have a space before #, if not we are likely in a link
            if char == " " and seen_hashtag and opts.tag_notation == "#tag" then
                if not cannot_be_tag then
                    return "tag", col
                end
            end

            if char == ":" and opts.tag_notation == ":tag:" then
                if not cannot_be_tag then
                    return "tag", col
                end
            end
        end

        if char == " " or char == "\t" then
            cannot_be_tag = true
        end
        col = col - 1
    end
    return nil, nil
end

M.get_tag_at = function(line, col, opts)
    -- we ignore the rule: no tags begin with a numeric digit
    local endcol = col + 1
    local pattern = "[%w-_/]"
    local char
    while endcol <= #line do
        char = line:sub(endcol, endcol)
        if char:match(pattern) == nil then
            if opts.tag_notation == ":tag:" then
                if char == ":" then
                    local tag = line:sub(col, endcol)
                    return tag
                end
            else
                return line:sub(col, endcol - 1)
            end
        end
        endcol = endcol + 1
    end
    -- we exhausted the line
    return line:sub(col, endcol)
end

-------------
-- testing --
-------------

local function _eval(line, col, opts)
    local kind, newcol = M.is_tag_or_link_at(line, col, opts)
    return { kind = kind, col = newcol, line = line }
end

local function _print_debug(x, prefix)
    prefix = prefix or ""
    for k, v in pairs(x) do
        print(prefix .. k .. ": " .. tostring(v))
    end
end

local function _expect(x, y)
    for k, v in pairs(y) do
        if x[k] ~= v then
            print("expected:")
            _print_debug(y, "  ")
            print("got:")
            _print_debug(x, "  ")
            assert(false)
        end
    end
end

M._testme = function()
    local line = ""
    local col = 10
    local opts = {}
    local tag
    local ret
    assert(_eval(line, col, opts).kind == nil)

    -- #tags
    opts.tag_notation = "#tag"

    line = "this is a #tag in a line"

    -- lets find it
    col = 13
    _expect(_eval(line, col, opts), { col = 11, kind = "tag" })
    ret = _eval(line, col, opts)
    tag = M.get_tag_at(line, ret.col, opts)
    -- print('tag .. `' .. tag .. '`')
    assert(tag == "#tag")

    -- lets be in the space after
    col = 15
    _expect(_eval(line, col, opts), { col = nil, kind = nil })

    -- lets be in the next word
    col = 16
    _expect(_eval(line, col, opts), { col = nil, kind = nil })

    -- lets be in the prev word
    col = 9
    _expect(_eval(line, col, opts), { col = nil, kind = nil })

    -- lets change the tag notation but hit the tag col
    col = 13
    opts.tag_notation = ":tag:"
    _expect(_eval(line, col, opts), { col = nil, kind = nil })

    -- :tags:
    opts.tag_notation = ":tag:"

    line = "this is a :tag: in a line"

    -- lets find it
    col = 13
    _expect(_eval(line, col, opts), { col = 11, kind = "tag" })
    ret = _eval(line, col, opts)
    tag = M.get_tag_at(line, ret.col, opts)
    assert(tag == ":tag:")

    -- lets be in the space after
    col = 16
    _expect(_eval(line, col, opts), { col = nil, kind = nil })

    -- lets be in the next word
    col = 17
    _expect(_eval(line, col, opts), { col = nil, kind = nil })

    -- lets be in the prev word
    col = 9
    _expect(_eval(line, col, opts), { col = nil, kind = nil })

    -- lets change the tag notation but hit the tag col
    col = 13
    opts.tag_notation = "#tag"
    _expect(_eval(line, col, opts), { col = nil, kind = nil })

    -- tagline
    line = "tags: [ first, second, third]"
    opts.tag_notation = "yaml-bare"

    col = 13
    _expect(_eval(line, col, opts), { col = 9, kind = "tag" })
    ret = _eval(line, col, opts)
    tag = M.get_tag_at(line, ret.col, opts)
    assert(tag == "first")

    col = 9
    _expect(_eval(line, col, opts), { col = 9, kind = "tag" })

    col = 14
    _expect(_eval(line, col, opts), { col = nil, kind = nil })

    col = 18
    _expect(_eval(line, col, opts), { col = 16, kind = "tag" })

    --
    line = "this is a [[link]] line"
    col = 13
    _expect(_eval(line, col, opts), { col = 13, kind = "link" })

    line = "this is a [[link]] line"
    col = 15
    _expect(_eval(line, col, opts), { col = 13, kind = "link" })
end

return M
