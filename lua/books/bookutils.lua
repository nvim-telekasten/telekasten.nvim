-- local async = require("plenary.async")
local NuiTree = require("nui.tree")
local NuiLine = require("nui.line")
local NuiSplit = require("nui.split")
local Keymap = require("nui.utils.keymap")
local Input = require("nui.input")
local tagutils = require("taglinks.tagutils")
local scan = require("plenary.scandir")

local M = {}
M.state = {}
M.book_tree = nil

-- helper function to check if a table contains a specific value
local function table_contains(table, val)
    for _, value in pairs(table) do
        if value == val then
            return true
        end
    end
    return false
end

M.filterTags = function(logic, A, B, C)
    -- check if A contains all elements of B and no elements from C
    local contains_all_b = true
    local contains_any_b = false
    local contains_no_c = true
    for _, b_elem in ipairs(B) do
        if not table_contains(A, b_elem) then
            contains_all_b = false
            break
        end
    end
    for _, b_elem in ipairs(B) do
        if table_contains(A, b_elem) then
            contains_any_b = true
            break
        end
    end
    for _, c_elem in ipairs(C) do
        if table_contains(A, c_elem) then
            contains_no_c = false
            break
        end
    end

    -- output results
    if logic == "and" then
        if contains_all_b and contains_no_c then
            return true
        else
            return false
        end
    else
        if contains_any_b and contains_no_c then
            return true
        else
            return false
        end
    end
end

M.log = function(message)
    local log_file_path = "/Users/lucas/tmp/lualog.log"
    local log_file = io.open(log_file_path, "a")
    io.output(log_file)
    io.write(message .. "\n")
    io.close(log_file)
end

M.split_and_trim = function(str, delimiter)
    local substrings = {}
    local pattern = "[^" .. delimiter .. "]+"
    for substring in string.gmatch(str, pattern) do
        table.insert(substrings, (string.gsub(substring, "^%s*(.-)%s*$", "%1")))
    end
    return substrings
end

-- TODO: cache mtimes and only update if changed

-- The reason we go over all notes in one go, is: backlinks
-- We generate 2 maps: one containing the number of links within a note
--    and a second one containing the number of backlinks to a note
-- Since we're parsing all notes anyway, we can mark linked notes as backlinked from the currently parsed note
M.generate_book_map = function(mytitle)
    local opts = M.Cfg
    assert(opts ~= nil, "opts must not be nil")
    -- TODO: check for code blocks
    -- local in_fenced_code_block = false
    -- also watch out for \t tabbed code blocks or ones with leading spaces that don't end up in a - or * list

    -- first, find all notes
    assert(opts.extension ~= nil, "Error: need extension in opts!")
    assert(opts.home ~= nil, "Error: need home dir in opts!")

    -- async seems to have lost await and we don't want to enter callback hell, hence we go sync here
    -- local subdir_list = scan.scan_dir(opts.home, { only_dirs = true })
    local file_list = {}
    -- transform the file list
    local _x = scan.scan_dir(opts.home, {
        search_pattern = function(entry)
            return entry:sub(-#opts.extension) == opts.extension
        end,
    })

    for _, v in pairs(_x) do
        file_list[v] = true
    end

    M.state.note_list = file_list

    -- now process all the notes
    local backlinks = {}
    for note_fn, _ in pairs(file_list) do
        -- go over file line by line
        local found = false
        for line in io.lines(note_fn) do
            if line:match("%[%[" .. mytitle .. "%]%]") then
                found = true
                break
            end
        end
        if found then
            backlinks[note_fn] = true
        end
    end

    return backlinks
end

M.find_buffer_by_name = function(name)
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        local buf_name = vim.api.nvim_buf_get_name(buf)
        if buf_name == name then
            return buf
        end
    end
    return -1
end

M.get_modified_buffers = function()
    local modified_buffers = {}
    for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
        local buffer_name = vim.api.nvim_buf_get_name(buffer)
        if buffer_name == nil or buffer_name == "" then
            buffer_name = "[No Name]#" .. buffer
        end
        modified_buffers[buffer_name] =
            vim.api.nvim_buf_get_option(buffer, "modified")
    end
    return modified_buffers
end

M.open_file = function(winid_openin, winid_from, path, open_cmd)
    local escaped_path = vim.fn.fnameescape(path)
    open_cmd = open_cmd or "edit"
    if open_cmd == "edit" or open_cmd == "e" then
        -- If the file is already open, switch to it.
        local bufnr = M.find_buffer_by_name(path)
        if bufnr > 0 then
            open_cmd = "b"
        end
    end
    vim.api.nvim_set_current_win(winid_openin)
    pcall(vim.cmd, open_cmd .. " " .. escaped_path)
    -- vim.cmd(open_cmd .. " " .. escaped_path)

    vim.api.nvim_set_current_win(winid_from)
end

M.revisit = function(Pinfo)
    -- get all notes link to this note
    local backlink_title = {}
    local backlinks = M.generate_book_map(M.state.center_note.title)
    for backlink_note, _ in pairs(backlinks) do
        backlink_title[#backlink_title + 1] = {
            title = Pinfo:new({ filepath = backlink_note, M.Cfg }).title,
            filepath = backlink_note,
            fexists = true,
        }
    end
    --
    -- get all notes link from this note
    -- and, get all todo items in this note
    local linksInNote = {}
    local todoInNote = {}
    local tmp = vim.api.nvim_buf_get_lines(M.state.main_bufnr, 0, -1, false)
    for _, line in pairs(tmp) do
        for w in string.gmatch(line, "%[%[(.-)%]%]") do
            local tmpInfo = Pinfo:new({ title = w, M.Cfg })
            linksInNote[#linksInNote + 1] = {
                ln = _,
                link = w,
                filepath = tmpInfo.filepath,
                fexists = tmpInfo.fexists,
            }
        end
        local todoMatch = string.match(line, "- %[[ ]%] (.+)$")
        if todoMatch ~= nil then
            todoInNote[#todoInNote + 1] = { ln = _, todo = todoMatch }
        end
    end

    local opts = M.state.opts
    opts.this_file = M.state.center_note.filepath
    local tag_map = tagutils.do_find_all_tags(opts)
    local taglist = {}

    local max_tag_len = 0
    for k, v in pairs(tag_map) do
        taglist[#taglist + 1] = { tag = k, details = v }
        if #k > max_tag_len then
            max_tag_len = #k
        end
    end

    local nodes = {}
    table.insert(
        nodes,
        NuiTree.Node({
            text = (opts.book_use_emoji and "🧠" or "#")
                .. " "
                .. M.state.center_note.title,
        })
    )
    -- table.insert(nodes, NuiTree.Node({ text = "  " }))
    local tags = {}
    for _, entry in pairs(taglist) do
        -- local display = string.format(
        --     "%" .. max_tag_len .. "s ... (%3d matches)",
        --     entry.tag,
        --     #entry.details
        -- )
        local display = entry.tag .. " (" .. #entry.details .. ")"

        table.insert(
            tags,
            NuiTree.Node({
                text = display,
                type = "tag",
                matches = #entry.details,
                details = entry.details,
            })
        )
    end
    table.insert(
        nodes,
        NuiTree.Node({
            id = "--tags",
            text = (opts.book_use_emoji and "🏷️" or "#") .. " Tags",
        }, tags)
    )
    local links = {}
    for _, entry in pairs(backlink_title) do
        local display = "[[" .. entry.title .. "]]"
        table.insert(
            links,
            NuiTree.Node({
                text = display,
                filepath = entry.filepath,
                fexists = entry.fexists,
                type = "backlink",
                ser = _,
            })
        )
    end
    table.insert(
        links,
        NuiTree.Node({
            text = (opts.book_use_emoji and "⭐️" or ">>")
                .. " "
                .. M.state.center_note.title
                .. " "
                .. (opts.book_use_emoji and "⭐️" or "<<"),
            id = "--thisnote",
            filepath = M.state.center_note.filepath,
            fexists = true,
            type = "centernote",
            ser = #backlink_title + 1,
        })
    )
    for _, entry in pairs(linksInNote) do
        local display = "[[" .. entry.link .. "]]"
        table.insert(
            links,
            NuiTree.Node({
                text = display,
                filepath = entry.filepath,
                fexists = entry.fexists,
                ser = #backlink_title + 1 + _,
                type = "link",
            })
        )
    end
    table.insert(
        nodes,
        NuiTree.Node({
            id = "--links",
            text = (opts.book_use_emoji and "🔗" or "#") .. " Links",
        }, links)
    )

    local todos = {}
    for _, entry in pairs(todoInNote) do
        -- local display = "[ ]" .. entry.todo
        local display = entry.todo
        --TODO: add line number to node data
        table.insert(
            todos,
            NuiTree.Node({
                text = display,
                ser = _,
                l = entry.ln,
                type = "todo",
            })
        )
    end
    table.insert(
        nodes,
        NuiTree.Node({
            id = "--todos",
            text = (opts.book_use_emoji and "❎" or "#") .. " Todos",
        }, todos)
    )

    local tree = NuiTree({
        winid = M.state.book_win,
        bufnr = M.state.book_bufnr,
        nodes = nodes,
        get_node_id = function(node)
            if node.id then
                return node.id
            end
            return "-" .. math.random()
        end,
        prepare_node = function(node)
            local line = NuiLine()

            line:append(string.rep("  ", node:get_depth() - 1))

            if node:has_children() then
                line:append(
                    node:is_expanded() and " " or " ",
                    "SpecialChar"
                )
            else
                line:append("  ")
            end

            line:append(node.text)

            return line
        end,
    })

    M.state.section_tag_line = 2
    M.state.section_link_line = M.state.section_tag_line + #tags + 1
    M.state.center_note_line = M.state.section_link_line + #backlink_title + 1
    M.state.section_todo_line = M.state.center_note_line + #linksInNote + 1

    if #backlink_title > 0 then
        M.state.parent_lines = {
            M.state.center_note_line - #backlink_title,
            M.state.center_note_line - 1,
        }
    else
        M.state.parent_lines = nil
    end

    if #linksInNote > 0 then
        M.state.children_lines = {
            M.state.center_note_line + 1,
            M.state.center_note_line + #linksInNote,
        }
    else
        M.state.children_lines = nil
    end

    return tree
end

M.movebetween = function(what, line_number, a, b)
    if what == "p" then
        return line_number <= a and b
            or (line_number <= b + 1 and line_number - 1 or b)
    else
        return line_number >= b and a
            or (line_number >= a - 1 and line_number + 1 or a)
    end
end

M.TkBookMoveCursorTo = function(file)
    if M.book_tree and M.state and M.state.section_link_line then
        for _, node in pairs(M.book_tree.nodes.by_id) do
            if
                (
                    node.type == "link"
                    or node.type == "backlink"
                    or node.type == "centernote"
                )
                and node.filepath == file
                and node.ser
            then
                vim.api.nvim_win_set_cursor(
                    M.state.book_win,
                    { M.state.section_link_line + node.ser, 6 }
                )
                break
            end
        end
    end
end

M.TkBookGotoCenterNote = function()
    vim.api.nvim_set_current_win(M.state.main_win)
    M.open_file(
        M.state.main_win,
        M.state.book_win,
        M.state.center_note.filepath,
        "edit"
    )
    vim.api.nvim_set_current_win(M.state.book_win)
    vim.api.nvim_win_set_cursor(
        M.state.book_win,
        { M.state.center_note_line, 6 }
    )
end

local showHelp = function()
    local Popup = require("nui.popup")
    local event = require("nui.utils.autocmd").event

    local popup = Popup({
        enter = true,
        focusable = true,
        border = {
            style = "rounded",
            text = {
                top = "[ Help ]",
                top_align = "center",
            },
            padding = {
                top = 1,
                left = 2,
            },
        },
        relative = "editor",
        position = "50%",
        size = {
            width = "80%",
            height = "60%",
        },
        ns_id = "TelekastenBook.nvim",
        buf_options = {
            buftype = "nofile",
            modifiable = true,
            swapfile = false,
            filetype = "text",
            undolevels = -1,
        },
    })

    -- mount/open the component
    popup:mount()

    -- unmount component when cursor leaves buffer
    popup:on(event.BufLeave, function()
        popup:unmount()
    end)
    popup:map("n", "<esc>", function()
        vim.cmd("q")
    end, { noremap = true })
    popup:map("n", "q", function()
        vim.cmd("q")
    end, { noremap = true })
    popup:map("n", "?", function()
        vim.cmd("q")
    end, { noremap = true })

    -- set content
    vim.api.nvim_buf_set_lines(popup.bufnr, 0, 1, false, {
        "In book window:                            | In search window",
        "  ?   bring up this help                   |   ?    bring up this help",
        "  f   focus on viewing note                |   s    search by tag",
        "  gh  go to center note                    |   fs   rescan and search",
        "  gt  go to tags                           |   /    search by content",
        "  gl  go to links                          |   f/   rescan and search by content",
        "  gd  got to todo                          |   <CR> open note in search result",
        "  p   cycle among backlinks                |",
        "  i   cycle among child links              |",
        "  s   show search window               |",
        "  q   close tkbook                         |   q    close search window",
        "  <CR> on tag:       highlight tags        |",
        "  <CR> on link:      show linked note      |",
        "  Ctrl-<CR> on tag:  jump to tag           |",
        "  Ctrl-<CR> on link: jump into linked note |",
        "",
        "",
        "q, <esc>, ? to close this help",
        "tkbook by @liukehong(https://www.github.com/cnshsliu)",
    })
    vim.api.nvim_buf_set_option(popup.bufnr, "modifiable", false)
end

M.init = function()
    M.state = {
        tag_scanned = false,
        file_tags_map = {},
    }
end

M.TkBookShow = function(Pinfo, Cfg, opts)
    local bufname = "TelekastenBook"
    M.Cfg = Cfg
    M.init()

    if M.state.book_bufnr then
        M.log("Buffer" .. M.state.book_bufnr .. "exist")
    end
    if
        M.state.book_bufnr
        and M.state.book_bufnr ~= -1
        and vim.fn.bufexists(M.state.book_bufnr)
    then
        M.log("Buffer" .. M.state.book_bufnr .. "exist")
        -- The buffer already exists, so delete it and its window
        local winid = vim.fn.bufwinid(M.state.book_bufnr)
        if winid ~= -1 and vim.api.nvim_win_is_valid(winid) then
            vim.api.nvim_win_close(winid, true)
        end
        pcall(vim.api.nvim_buf_delete, M.state.book_bufnr, { force = true })
    end
    local tk_book_group =
        vim.api.nvim_create_augroup("tkbook", { clear = true })
    vim.api.nvim_create_autocmd("FileType", {
        pattern = "telekasten",
        group = tk_book_group,
        callback = function(args)
            if
                M.book_tree ~= nil
                and M.state.enable_auto_move_curosr_to_note_line
            then
                -- This is only accurate when all nodes are expaned at this moment
                pcall(M.TkBookMoveCursorTo, args.file)
            end
        end,
    })
    M.state = {
        main_win = vim.api.nvim_get_current_win(),
        main_bufnr = vim.api.nvim_get_current_buf(),
        center_note = Pinfo:new({ filepath = vim.fn.expand("%:p"), M.Cfg }),
        center_note_line = -1,
        opts = opts,
        enable_auto_move_curosr_to_note_line = true,
    }
    M.state.book_split = NuiSplit({
        ns_id = vim.api.nvim_create_namespace("TelekastenBook.nvim"),
        size = 40,
        position = "right",
        relative = "editor",
        buf_options = {
            buftype = "nofile",
            modifiable = false,
            swapfile = false,
            filetype = "telekasten",
            undolevels = -1,
        },
        win_options = {
            colorcolumn = "",
            signcolumn = "no",
        },
    })
    M.state.book_split:mount()
    M.state.book_bufnr = M.state.book_split.bufnr
    vim.api.nvim_buf_set_name(M.state.book_bufnr, bufname)
    M.state.book_win = vim.api.nvim_get_current_win()

    M.book_tree = M.revisit(Pinfo, M.state)

    M.book_tree:render()
    local expand_all = function()
        local updated = false

        for _, node in pairs(M.book_tree.nodes.by_id) do
            updated = node:expand() or updated
        end

        if updated then
            M.book_tree:render()
        end
    end
    expand_all()
    vim.api.nvim_win_set_cursor(0, { M.state.center_note_line, 6 })
    local map_options = { noremap = true, nowait = true }

    Keymap.set(M.state.book_bufnr, "n", "q", function()
        pcall(vim.api.nvim_del_augroup_by_name, "tkbook")
        M.state.book_split:unmount()
        M.state.book_win = nil
        M.state.book_bufnr = nil
        M.state.book_split = nil
        if M.state.search_split ~= nil then
            vim.api.nvim_set_current_win(M.state.search_win)
            vim.cmd("bd")
        end
    end, { noremap = true })
    vim.api.nvim_create_autocmd("BufDelete", {
        buffer = M.state.book_bufnr,
        callback = function()
            vim.api.nvim_del_augroup_by_name("tkbook")
            M.log("!!!!! book_split.unmount !!!!! ")
            M.state.book_split:unmount()
        end,
    })

    local pressEnterOnBookItem = function(stayInBookWin)
        local node = M.book_tree:get_node()
        if
            (
                node.type == "link"
                or node.type == "centernote"
                or node.type == "backlink"
            ) and node.filepath
        then
            if node.fexists then
                -- vim.cmd("e " .. node.filepath)
                M.open_file(
                    M.state.main_win,
                    M.state.book_win,
                    node.filepath,
                    "edit"
                )
            else
                print("File does not exist:" .. " " .. node.filepath)
            end
        elseif node.type == "tag" then
            M.state.enable_auto_move_curosr_to_note_line = false
            if
                vim.api.nvim_buf_get_name(
                    vim.api.nvim_win_get_buf(M.state.main_win)
                ) ~= node.details[1].fn
            then
                -- M.log("Not same, open it")
                M.open_file(
                    M.state.main_win,
                    M.state.book_win,
                    node.details[1].fn,
                    "edit"
                )
                -- else
                -- M.log("Same file")
            end
            vim.api.nvim_set_current_win(M.state.main_win)
            vim.cmd("/" .. node.details[1].t)
            vim.api.nvim_win_set_cursor(
                M.state.main_win,
                { tonumber(node.details[1].l), tonumber(node.details[1].c) }
            )
            M.state.enable_auto_move_curosr_to_note_line = true
        elseif node.type == "todo" then
            M.state.enable_auto_move_curosr_to_note_line = false
            M.log(vim.inspect(node))
            if
                vim.api.nvim_buf_get_name(
                    vim.api.nvim_win_get_buf(M.state.main_win)
                ) ~= M.state.center_note.filepath
            then
                -- M.log("Not same, open it")
                M.open_file(
                    M.state.main_win,
                    M.state.book_win,
                    M.state.center_note.filepath,
                    "edit"
                )
            end
            vim.api.nvim_set_current_win(M.state.main_win)
            -- vim.cmd("/" .. escape_chars(node.text))
            vim.api.nvim_win_set_cursor(
                M.state.main_win,
                { tonumber(node.l), 7 }
            )
            M.state.enable_auto_move_curosr_to_note_line = true
        end
        if not stayInBookWin then
            vim.api.nvim_set_current_win(M.state.main_win)
        else
            vim.api.nvim_set_current_win(M.state.book_win)
        end
    end

    local pressEnterOnSearchResultItem = function(stayInSearchResultWin)
        local node = M.state.search_tree:get_node()
        if node.type == "note" and node.filepath then
            M.open_file(
                M.state.main_win,
                M.state.search_win,
                node.filepath,
                "edit"
            )
            vim.api.nvim_set_current_win(M.state.main_win)
            M.state.main_bufnr = vim.api.nvim_get_current_buf()
            M.state.center_note =
                Pinfo:new({ filepath = vim.fn.expand("%:p"), M.Cfg })
            vim.api.nvim_set_current_win(M.state.book_win)
            M.book_tree.nodes = {}
            M.book_tree = M.revisit(Pinfo)
            M.book_tree:render()
            expand_all()
            vim.api.nvim_win_set_cursor(0, { M.state.center_note_line, 6 })
        end
        if not stayInSearchResultWin then
            vim.api.nvim_set_current_win(M.state.main_win)
        else
            vim.api.nvim_set_current_win(M.state.search_win)
        end
    end

    Keymap.set(M.state.book_bufnr, "n", "<CR>", function()
        pressEnterOnBookItem(true)
    end, map_options)

    Keymap.set(M.state.book_bufnr, "n", "<C-CR>", function()
        pressEnterOnBookItem(false)
    end, map_options)

    Keymap.set(M.state.book_bufnr, "n", "gh", function()
        M.TkBookGotoCenterNote()
    end, map_options)

    Keymap.set(M.state.book_bufnr, "n", "gt", function()
        vim.api.nvim_win_set_cursor(
            M.state.book_win,
            { M.state.section_tag_line, 5 }
        )
    end, map_options)
    Keymap.set(M.state.book_bufnr, "n", "gl", function()
        vim.api.nvim_win_set_cursor(
            M.state.book_win,
            { M.state.section_link_line, 5 }
        )
    end, map_options)
    Keymap.set(M.state.book_bufnr, "n", "gd", function()
        vim.api.nvim_win_set_cursor(
            M.state.book_win,
            { M.state.section_todo_line, 5 }
        )
    end, map_options)

    Keymap.set(M.state.book_bufnr, "n", "f", function()
        vim.api.nvim_set_current_win(M.state.main_win)
        M.state.main_bufnr = vim.api.nvim_get_current_buf()
        M.state.center_note =
            Pinfo:new({ filepath = vim.fn.expand("%:p"), M.Cfg })
        vim.api.nvim_set_current_win(M.state.book_win)
        M.book_tree.nodes = {}
        M.book_tree = M.revisit(Pinfo)
        M.book_tree:render()
        expand_all()
        vim.api.nvim_win_set_cursor(0, { M.state.center_note_line, 6 })
    end, map_options)

    Keymap.set(M.state.book_bufnr, "n", "p", function()
        if M.state.parent_lines == nil then
            vim.api.nvim_win_set_cursor(0, { M.state.center_note_line, 6 })
        else
            vim.api.nvim_win_set_cursor(0, {
                M.movebetween(
                    "p",
                    vim.api.nvim_win_get_cursor(0)[1],
                    M.state.parent_lines[1],
                    M.state.parent_lines[2]
                ),
                6,
            })
        end
    end, map_options)
    Keymap.set(M.state.book_bufnr, "n", "i", function()
        if M.state.children_lines == nil then
            vim.api.nvim_win_set_cursor(0, { M.state.center_note_line, 6 })
        else
            vim.api.nvim_win_set_cursor(0, {
                M.movebetween(
                    "c",
                    vim.api.nvim_win_get_cursor(0)[1],
                    M.state.children_lines[1],
                    M.state.children_lines[2]
                ),
                6,
            })
        end
    end, map_options)

    -- collapse current node
    Keymap.set(M.state.book_bufnr, "n", "c", function()
        local node = M.book_tree:get_node()

        if node:has_children() == false then
            M.log("current node does not has children, get it's parent")
            node = M.book_tree:get_node(node:get_parent_id())
            M.log("Got " .. node.text)
        end

        if node:is_expanded() then
            if node:collapse() then
                M.book_tree:render()
            end
        end
    end, map_options)

    -- collapse all nodes
    Keymap.set(M.state.book_bufnr, "n", "C", function()
        local updated = false

        for _, node in pairs(M.book_tree.nodes.by_id) do
            updated = node:collapse() or updated
        end

        if updated then
            M.book_tree:render()
        end
    end, map_options)

    -- expand current node
    Keymap.set(M.state.book_bufnr, "n", "e", function()
        local node = M.book_tree:get_node()

        if node:expand() then
            M.book_tree:render()
        end
    end, map_options)

    -- expand all nodes
    Keymap.set(M.state.book_bufnr, "n", "E", expand_all, map_options)

    Keymap.set(M.state.book_bufnr, "n", "?", function()
        showHelp()
    end, map_options)

    Keymap.set(M.state.book_bufnr, "n", "s", function()
        -- local event = require("nui.utils.autocmd").event

        if
            M.state.search_split
            and M.state.search_bufnr
            and M.state.search_win
            and vim.api.nvim_win_is_valid(M.state.search_win)
        then
            vim.api.nvim_set_current_win(M.state.search_win)
        else
            M.state.search_split = NuiSplit({
                ns_id = "TelekastenBook.nvim",
                size = { width = "100%", height = "50%" },
                position = "bottom",
                relative = "win",
                buf_options = {
                    buftype = "nofile",
                    modifiable = true,
                    swapfile = false,
                    filetype = "text",
                },
                win_options = {
                    colorcolumn = "",
                    signcolumn = "no",
                },
            })
            M.state.search_split:mount()
            M.state.search_bufnr = M.state.search_split.bufnr
            vim.api.nvim_buf_set_name(M.state.book_bufnr, "book_search")
            M.state.search_win = vim.api.nvim_get_current_win()
            vim.api.nvim_buf_set_lines(
                M.state.search_bufnr,
                0,
                -1,
                true,
                { "Press s to search" }
            )
        end

        -- TODO: search saved search and display from line 3, most used in the front
        local loadSavedSearch = function()
            return { "abcd" }
        end
        loadSavedSearch()

        local parseSearchUserInput = function()
            local ret = {}
            local input_tags = M.split_and_trim(M.state.user_input, ", ")
            ret.B = {} -- want
            ret.C = {} -- dont' want
            ret.logic = "and"
            ret.search_name = ""
            for _, tag in ipairs(input_tags) do
                if tag == "and" or tag == "or" then
                    if tag == "or" then
                        ret.logic = "or"
                    end
                elseif string.sub(tag, 1, 1) == ":" then
                    ret.search_name = string.sub(tag, 2)
                else
                    if string.sub(tag, 1, 1) == "-" then
                        table.insert(ret.C, tag:sub(2))
                    else
                        table.insert(ret.B, tag)
                    end
                end
            end
            -- M.log(
            --     "input_tags "
            --         .. vim.inspect(input_tags)
            --         .. " B:"
            --         .. vim.inspect(ret.B)
            --         .. " C:"
            --         .. vim.inspect(ret.C)
            -- )
            return ret
        end

        local get_tag_matched_files = function()
            -- example usage
            local tmp = parseSearchUserInput()
            for fn, ftags in pairs(M.state.file_tags_map) do
                if #ftags > 0 then
                    local checkResult =
                        M.filterTags(tmp.logic, ftags, tmp.B, tmp.C)
                    -- M.log(
                    --     "filter "
                    --         .. vim.inspect(ftags)
                    --         .. " with B:"
                    --         .. vim.inspect(tmp.B)
                    --         .. " with C:"
                    --         .. vim.inspect(tmp.C)
                    --         .. " result:"
                    --         .. (checkResult and "YES" or "NO")
                    -- )
                    if checkResult then
                        M.state.search_result[#M.state.search_result + 1] = fn
                    end
                end
            end
        end

        local doTagSearch = function(value)
            M.state.user_input = value
            M.log(
                (M.state.rescan and "Rescan" or "No Rescan")
                    .. " "
                    .. (M.state.tag_scanned and "Scanned" or "not scanned")
            )
            if (not M.state.tag_scanned) or M.state.rescan then
                M.state.file_tags_map = {}
                M.generate_book_map(M.state.center_note.title)
                for fn, _ in pairs(M.state.note_list) do
                    opts.this_file = fn
                    M.state.file_tags_map[fn] = {}
                    local tag_map = tagutils.do_find_all_tags(opts)
                    -- M.log(fn .. " has " .. vim.inspect(tag_map) .. " tags")
                    local ftags = {}
                    for k, _ in pairs(tag_map) do
                        ftags[#ftags + 1] = string.sub(k, 2)
                    end
                    M.state.file_tags_map[fn] = ftags
                end
                M.state.tag_scanned = true
                M.log("map build")
            else
                M.log("passed build map")
            end
            M.state.search_result = {}
            get_tag_matched_files()

            local buildSearchResultTree = function()
                local result_nodes = {}
                -- table.insert(
                --     result_nodes,
                --     NuiTree.Node({
                --         text = "Press 's' to search, <CR> to open",
                --         ser = 0,
                --         type = "title",
                --         filepath = nil,
                --     })
                -- )
                for _, entry in ipairs(M.state.search_result) do
                    local note = Pinfo:new({ filepath = entry, M.Cfg })
                    table.insert(
                        result_nodes,
                        NuiTree.Node({
                            text = note.title,
                            ser = _,
                            type = "note",
                            filepath = note.filepath,
                        })
                    )
                end
                M.state.search_tree = NuiTree({
                    winid = M.state.search_win,
                    bufnr = M.state.search_bufnr,
                    nodes = result_nodes,
                    get_node_id = function(node)
                        if node.id then
                            return node.id
                        end
                        return "-" .. math.random()
                    end,
                    prepare_node = function(node)
                        local line = NuiLine()

                        line:append(string.rep("  ", node:get_depth() - 1))

                        if node:has_children() then
                            line:append(
                                node:is_expanded() and " " or " ",
                                "SpecialChar"
                            )
                        elseif node.type == "note" then
                            line:append("  ")
                        else
                            line:append("")
                        end

                        line:append(node.text)

                        return line
                    end,
                })
                M.state.search_tree:render()
            end
            buildSearchResultTree()

            return { "Done" }
        end

        local promptSearchInput = function()
            if M.state.lastSearchPrompt == nil then
                M.state.lastSearchPrompt = ""
            end
            local searchInput = Input({
                relative = "editor",
                position = "50%",
                enter = true,
                focusable = true,
                size = { width = 80, height = 3 },
                border = {
                    style = "rounded",
                    text = {
                        top = "[Input]",
                        top_align = "left",
                    },
                },
                win_options = {
                    winhighlight = "Normal:Normal",
                },
            }, {
                prompt = " ",
                default_value = M.state.lastSearchPrompt,
                on_close = function()
                    print("Input closed!")
                end,
                on_submit = function(value)
                    M.state.lastSearchPrompt = value
                    M.log("call doTagSearch:" .. value)
                    doTagSearch(value)
                end,
                -- on_change = function(value)
                --     if M.state.incre_search == "incre" then
                --         M.state.file_tags_map = {}
                --         M.state.lastSearchPrompt = value
                --         vim.api.nvim_set_current_win(M.state.search_win)
                --         doTagSearch(value)
                --         vim.api.nvim_set_current_win(M.state.input_win)
                --     end
                -- end,
            })
            searchInput:map("n", "<Esc>", function()
                searchInput:unmount()
            end, { noremap = true })
            searchInput:mount()
            M.state.input_bufnr = searchInput.bufnr
            M.state.input_win = vim.api.nvim_get_current_win()
        end

        -- vim.api.nvim_create_autocmd("CursorMoved", {
        --     buffer = M.state.result_bufnr,
        --     callback = function()
        --         local row, _ = unpack(vim.api.nvim_win_get_cursor(0))
        --         if row > 1 then
        --             vim.api.nvim_buf_set_option(0, "modifiable", false)
        --         else
        --             vim.api.nvim_buf_set_option(0, "modifiable", true)
        --         end
        --     end,
        -- })

        -- TODO:map in this window, to refresh book_win to focus on the left side main window note
        Keymap.set(M.state.search_bufnr, "n", "fs", function()
            M.state.rescan = true
            promptSearchInput()
        end, map_options)
        Keymap.set(M.state.search_bufnr, "n", "s", function()
            M.state.rescan = false
            promptSearchInput()
        end, map_options)
        Keymap.set(M.state.search_bufnr, "n", "?", function()
            showHelp()
        end, map_options)
        M.state.search_split:map("n", "q", function()
            M.state.search_split:unmount()
            M.state.search_win = nil
            M.state.search_bufnr = nil
            M.state.search_split = nil
        end, map_options)

        Keymap.set(M.state.search_bufnr, "n", "<CR>", function()
            pressEnterOnSearchResultItem(true)
        end, map_options)
    end, map_options)
end
return M
