local builtin = require("telescope.builtin")
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local utils = require("telescope.utils")
local make_entry = require("telescope.make_entry")
local entry_display = require("telescope.pickers.entry_display")
local sorters = require("telescope.sorters")
local themes = require("telescope.themes")
local filetype = require("plenary.filetype")
local taglinks = require("telekasten.utils.taglinks")
local tagutils = require("telekasten.utils.tags")
local linkutils = require("telekasten.utils.links")
local dateutils = require("telekasten.utils.dates")
local fileutils = require("telekasten.utils.files")
local Path = require("plenary.path")
local tkpickers = require("telekasten.pickers")
local tkutils = require("telekasten.utils")
local config = require("telekasten.config")
local periodic = require("telekasten.periodic")

-- declare locals for the nvim api stuff to avoid more lsp warnings
local vim = vim

local M = {}

--- imgFromClipboard()
-- Copies png image from clipboard to a new file in the vault and inserts link according to configured format
local function imgFromClipboard()
    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        -- Define default paste commands in case of availability
        local paste_command = {}
        paste_command["xsel"] = function(dir, filename)
            local _image_path = vim.fn.system("xsel --clipboard --output")
            local image_path = _image_path:gsub("file://", "")
            if
                vim.fn
                    .system("file --mime-type -b " .. image_path)
                    :gsub("%s+", "") == "image/png"
            then
                return "cp " .. image_path .. " " .. dir .. "/" .. filename
            else
                return ""
            end
        end
        paste_command["xclip"] = function(dir, filename)
            return "xclip -selection clipboard -t image/png -o > "
                .. dir
                .. "/"
                .. filename
        end
        paste_command["osascript"] = function(dir, filename)
            return string.format(
                'osascript -e "tell application \\"System Events\\" to write (the clipboard as «class PNGf») to '
                    .. '(make new file at folder \\"%s\\" with properties {name:\\"%s\\"})"',
                dir,
                filename
            )
        end
        paste_command["wl-paste"] = function(dir, filename)
            return "wl-paste -n -t image/png > " .. dir .. "/" .. filename
        end

        -- Choose a command to use
        -- First, try to set to configured command if available
        -- Otherwise, set to first default command available on user's machine
        local get_paste_command
        if paste_command[config.options.clipboard_program] ~= nil then
            if vim.fn.executable(config.options.clipboard_program) ~= 1 then
                vim.api.nvim_err_write(
                    "The clipboard program specified [`"
                        .. config.options.clipboard_program
                        .. "`] is not executable or not in your $PATH\n"
                )
            end
            get_paste_command = paste_command[config.options.clipboard_program]
        elseif vim.fn.executable("xsel") == 1 then
            get_paste_command = paste_command["xsel"]
        elseif vim.fn.executable("xclip") == 1 then
            get_paste_command = paste_command["xclip"]
        elseif vim.fn.executable("wl-paste") == 1 then
            get_paste_command = paste_command["wl-paste"]
        elseif vim.fn.executable("osascript") == 1 then
            get_paste_command = paste_command["osascript"]
        else
            vim.api.nvim_err_write(
                "No clipboard programs found!\nChecked executables: xsel, xclip, wl-paste, osascript\n"
            )
        end

        -- TODO: check `xclip -selection clipboard -t TARGETS -o` for the occurence of `image/png`

        -- using plenary.job::new():sync() with on_stdout(_, data) unfortunately did some weird ASCII translation on the
        -- data, so the PNGs were invalid. It seems like 0d 0a and single 0a bytes were stripped by the plenary job:
        --
        -- plenary job version:
        -- $ hexdump -C /tmp/x.png|head
        -- 00000000  89 50 4e 47 1a 00 00 00  49 48 44 52 00 00 03 19  |.PNG....IHDR....|
        -- 00000010  00 00 01 c1 08 02 00 00  00 8a 73 e1 c3 00 00 00  |..........s.....|
        -- 00000020  09 70 48 59 73 00 00 0e  c4 00 00 0e c4 01 95 2b  |.pHYs..........+|
        -- 00000030  0e 1b 00 00 20 00 49 44  41 54 78 9c ec dd 77 58  |.... .IDATx...wX|
        -- 00000040  14 d7 fa 07 f0 33 bb b3  4b af 0b 2c 08 22 1d 04  |.....3..K..,."..|
        -- 00000050  05 11 10 1b a2 54 c5 1e  bb b1 c6 98 c4 68 72 4d  |.....T.......hrM|
        -- 00000060  e2 cd 35 37 26 b9 49 6e  6e 7e f7 a6 98 98 a8 29  |..57&.Inn~.....)|
        -- 00000070  26 6a 8c 51 63 8b bd 00  8a 58 40 b0 81 08 2a 45  |&j.Qc....X@...*E|
        -- 00000080  69 52 17 58 ca ee b2 f5  f7 c7 ea 4a 10 66 d7 01  |iR.X.......J.f..|
        -- 00000090  b1 e4 fb 79 7c f2 2c e7  cc 39 e7 3d 67 66 b3 2f  |...y|.,..9.=gf./|
        --
        -- OK version
        -- $ hexdump -C /tmp/x2.png|head
        -- 00000000  89 50 4e 47 0d 0a 1a 0a  00 00 00 0d 49 48 44 52  |.PNG........IHDR|
        -- 00000010  00 00 03 19 00 00 01 c1  08 02 00 00 00 8a 73 e1  |..............s.|
        -- 00000020  c3 00 00 00 09 70 48 59  73 00 00 0e c4 00 00 0e  |.....pHYs.......|
        -- 00000030  c4 01 95 2b 0e 1b 00 00  20 00 49 44 41 54 78 9c  |...+.... .IDATx.|
        -- 00000040  ec dd 77 58 14 d7 fa 07  f0 33 bb b3 4b af 0b 2c  |..wX.....3..K..,|
        -- 00000050  08 22 1d 04 05 11 10 1b  a2 54 c5 1e bb b1 c6 98  |.".......T......|
        -- 00000060  c4 68 72 4d e2 cd 35 37  26 b9 49 6e 6e 7e f7 a6  |.hrM..57&.Inn~..|
        -- 00000070  98 98 a8 29 26 6a 8c 51  63 8b bd 00 8a 58 40 b0  |...)&j.Qc....X@.|
        -- 00000080  81 08 2a 45 69 52 17 58  ca ee b2 f5 f7 c7 ea 4a  |..*EiR.X.......J|
        -- 00000090  10 66 d7 01 b1 e4 fb 79  7c f2 2c e7 cc 39 e7 3d  |.f.....y|.,..9.=|

        -- Get a destination to store the image in
        local pngname = "pasted_img_" .. os.date("%Y%m%d%H%M%S") .. ".png"
        local pngdir = config.options.image_subdir
                and config.options.image_subdir
            or config.options.home
        local png = Path:new(pngdir, pngname).filename
        local relpath =
            linkutils.make_relative_path(vim.fn.expand("%:p"), png, "/")

        -- Try to paste the image to a file and check output to verify success
        local output = vim.fn.system(get_paste_command(pngdir, pngname))
        if output ~= "" then
            -- Remove empty file created by previous command if failed
            vim.fn.system("rm " .. png)
            vim.api.nvim_err_writeln(
                string.format(
                    "Unable to write image %s.\n"
                        .. "Is there an image on the clipboard?\n"
                        .. "Have you set clipboard_program to your preferred paste command? "
                        .. "(see :help telekasten.configuration)\n"
                        .. "See also issue 131",
                    png
                )
            )
        end

        -- Either insert the proper link according to config or report the error
        if fileutils.file_exists(png) then
            if config.options.image_link_style == "markdown" then
                vim.api.nvim_put({ "![](" .. relpath .. ")" }, "", true, true)
            else
                vim.api.nvim_put({ "![[" .. pngname .. "]]" }, "", true, true)
            end
        else
            vim.api.nvim_err_writeln("Unable to write image " .. png)
        end
    end)
end

--- FindDailyNotes(opts)
--- Opens a picker looking for daily notes, creating new from template if needed
--- @param opts table Options if they should differ from user's configuration
local function FindDailyNotes(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking
    local picker_actions = tkpickers.picker_actions

    -- If global dir check passes, defines a picker for daily files
    -- If today's daily doesn't exist, create one from template
    -- Either way, then open the picker
    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        local dinfo = dateutils.calculate_dates(
            nil,
            config.options.calendar_opts.calendar_monday
        )

        local pcfg = config.options.periodic
        local fname, title, root_dir, _ =
            periodic.build_path(pcfg, "daily", dinfo, config.options.extension)
        if not fname or not root_dir then
            return
        end

        local kcfg = pcfg.kinds.daily
        local fexists = fileutils.file_exists(fname)

        local search_root = periodic.search_root(pcfg, "daily") or pcfg.root
        local search_pattern =
            periodic.filename_pattern(pcfg, "daily", config.options.extension)

        local function picker()
            fileutils.find_files_sorted({
                prompt_title = "Find daily note",
                cwd = search_root,
                find_command = config.options.find_command,
                search_pattern = search_pattern,
                attach_mappings = function(_, map)
                    actions.select_default:replace(
                        picker_actions.select_default
                    )
                    map("i", "<c-y>", picker_actions.yank_link(opts))
                    map("i", "<c-i>", picker_actions.paste_link(opts))
                    map("n", "<c-y>", picker_actions.yank_link(opts))
                    map("n", "<c-i>", picker_actions.paste_link(opts))
                    map("n", "<c-c>", picker_actions.close(opts))
                    map("n", "<esc>", picker_actions.close(opts))
                    return true
                end,
                sort = config.options.sort,
            })
        end

        if (not fexists) and kcfg.create_if_missing then
            fileutils.create_note_from_template(
                title,
                nil,
                fname,
                kcfg.template_file,
                dinfo,
                function()
                    opts.erase = true
                    opts.erase_file = fname
                    picker()
                end
            )
            return
        end
        picker()
    end)
end

--- FindWeeklyNotes(opts)
-- Defines and uses a picker looking for weekly notes, creating a new one from template if needed
-- @param opts table Options if they should differ from user's configuration
local function FindWeeklyNotes(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking

    -- If global dir check passes, set up a picker for weekly notes
    -- If this week's note does not exist, create from template
    -- Either way, then call the picker
    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        local dinfo = dateutils.calculate_dates(
            nil,
            config.options.calendar_opts.calendar_monday
        )

        local pcfg = config.options.periodic
        local fname, title, root_dir, _ =
            periodic.build_path(pcfg, "weekly", dinfo, config.options.extension)
        if not fname or not root_dir then
            return
        end

        local kcfg = pcfg.kinds.weekly
        local fexists = fileutils.file_exists(fname)
        local search_root = periodic.search_root(pcfg, "weekly") or pcfg.root
        local search_pattern =
            periodic.filename_pattern(pcfg, "weekly", config.options.extension)

        local picker_actions = tkpickers.picker_actions
        local function picker()
            fileutils.find_files_sorted({
                prompt_title = "Find weekly note",
                cwd = search_root,
                find_command = config.options.find_command,
                search_pattern = search_pattern,
                attach_mappings = function(_, map)
                    actions.select_default:replace(
                        picker_actions.select_default
                    )
                    map("i", "<c-y>", picker_actions.yank_link(opts))
                    map("i", "<c-i>", picker_actions.paste_link(opts))
                    map("n", "<c-y>", picker_actions.yank_link(opts))
                    map("n", "<c-i>", picker_actions.paste_link(opts))
                    map("n", "<c-c>", picker_actions.close(opts))
                    map("n", "<esc>", picker_actions.close(opts))
                    return true
                end,
                sort = config.options.sort,
            })
        end

        if (not fexists) and kcfg.create_if_missing then
            fileutils.create_note_from_template(
                title,
                nil,
                fname,
                kcfg.template_file,
                dinfo,
                function()
                    opts.erase = true
                    opts.erase_file = fname
                    picker()
                end
            )
            return
        end
        picker()
    end)
end

--- FindMonthlyNotes(opts)
-- Defines and uses a picker looking for monthly notes, creating a new one from template if needed
-- @param opts table Options if they should differ from user's configuration
local function FindMonthlyNotes(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking

    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        local dinfo = dateutils.calculate_dates(
            nil,
            config.options.calendar_opts.calendar_monday
        )

        local pcfg = config.options.periodic
        local fname, title, root_dir, _ = periodic.build_path(
            pcfg,
            "monthly",
            dinfo,
            config.options.extension
        )
        if not fname or not root_dir then
            return
        end

        local kcfg = pcfg.kinds.monthly
        local fexists = fileutils.file_exists(fname)
        local search_root = periodic.search_root(pcfg, "monthly") or pcfg.root
        local search_pattern =
            periodic.filename_pattern(pcfg, "monthly", config.options.extension)

        local picker_actions = tkpickers.picker_actions

        local function picker()
            fileutils.find_files_sorted({
                prompt_title = "Find monthly note",
                cwd = search_root,
                find_command = config.options.find_command,
                search_pattern = search_pattern,
                attach_mappings = function(_, map)
                    actions.select_default:replace(
                        picker_actions.select_default
                    )
                    map("i", "<c-y>", picker_actions.yank_link(opts))
                    map("i", "<c-i>", picker_actions.paste_link(opts))
                    map("n", "<c-y>", picker_actions.yank_link(opts))
                    map("n", "<c-i>", picker_actions.paste_link(opts))
                    map("n", "<c-c>", picker_actions.close(opts))
                    map("n", "<esc>", picker_actions.close(opts))
                    return true
                end,
                sort = config.options.sort,
            })
        end

        if (not fexists) and kcfg.create_if_missing then
            fileutils.create_note_from_template(
                title,
                nil,
                fname,
                kcfg.template_file,
                dinfo,
                function()
                    opts.erase = true
                    opts.erase_file = fname
                    picker()
                end
            )
            return
        end
        picker()
    end)
end

--- FindQuarterlyNotes(opts)
-- Defines and uses a picker looking for quarterly notes, creating a new one from template if needed
-- @param opts table Options if they should differ from user's configuration
local function FindQuarterlyNotes(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking

    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        local dinfo = dateutils.calculate_dates(
            nil,
            config.options.calendar_opts.calendar_monday
        )

        local pcfg = config.options.periodic
        local fname, title, root_dir, _ = periodic.build_path(
            pcfg,
            "quarterly",
            dinfo,
            config.options.extension
        )
        if not fname or not root_dir then
            return
        end

        local kcfg = pcfg.kinds.quarterly
        local fexists = fileutils.file_exists(fname)
        local search_root = periodic.search_root(pcfg, "quarterly") or pcfg.root
        local search_pattern = periodic.filename_pattern(
            pcfg,
            "quarterly",
            config.options.extension
        )

        local picker_actions = tkpickers.picker_actions

        local function picker()
            fileutils.find_files_sorted({
                prompt_title = "Find quarterly note",
                cwd = search_root,
                find_command = config.options.find_command,
                search_pattern = search_pattern,
                attach_mappings = function(_, map)
                    actions.select_default:replace(
                        picker_actions.select_default
                    )
                    map("i", "<c-y>", picker_actions.yank_link(opts))
                    map("i", "<c-i>", picker_actions.paste_link(opts))
                    map("n", "<c-y>", picker_actions.yank_link(opts))
                    map("n", "<c-i>", picker_actions.paste_link(opts))
                    map("n", "<c-c>", picker_actions.close(opts))
                    map("n", "<esc>", picker_actions.close(opts))
                    return true
                end,
                sort = config.options.sort,
            })
        end

        if (not fexists) and kcfg.create_if_missing then
            fileutils.create_note_from_template(
                title,
                nil,
                fname,
                kcfg.template_file,
                dinfo,
                function()
                    opts.erase = true
                    opts.erase_file = fname
                    picker()
                end
            )
            return
        end
        picker()
    end)
end

--- FindYearlyNotes(opts)
-- Defines and uses a picker looking for yearly notes, creating a new one from template if needed
-- @param opts table Options if they should differ from user's configuration
local function FindYearlyNotes(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking

    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        local dinfo = dateutils.calculate_dates(
            nil,
            config.options.calendar_opts.calendar_monday
        )

        local pcfg = config.options.periodic
        local fname, title, root_dir, _ =
            periodic.build_path(pcfg, "yearly", dinfo, config.options.extension)
        if not fname or not root_dir then
            return
        end

        local kcfg = pcfg.kinds.yearly
        local fexists = fileutils.file_exists(fname)
        local search_root = periodic.search_root(pcfg, "yearly") or pcfg.root
        local search_pattern =
            periodic.filename_pattern(pcfg, "yearly", config.options.extension)

        local picker_actions = tkpickers.picker_actions

        local function picker()
            fileutils.find_files_sorted({
                prompt_title = "Find yearly note",
                cwd = search_root,
                find_command = config.options.find_command,
                search_pattern = search_pattern,
                attach_mappings = function(_, map)
                    actions.select_default:replace(
                        picker_actions.select_default
                    )
                    map("i", "<c-y>", picker_actions.yank_link(opts))
                    map("i", "<c-i>", picker_actions.paste_link(opts))
                    map("n", "<c-y>", picker_actions.yank_link(opts))
                    map("n", "<c-i>", picker_actions.paste_link(opts))
                    map("n", "<c-c>", picker_actions.close(opts))
                    map("n", "<esc>", picker_actions.close(opts))
                    return true
                end,
                sort = config.options.sort,
            })
        end

        if (not fexists) and kcfg.create_if_missing then
            fileutils.create_note_from_template(
                title,
                nil,
                fname,
                kcfg.template_file,
                dinfo,
                function()
                    opts.erase = true
                    opts.erase_file = fname
                    picker()
                end
            )
            return
        end
        picker()
    end)
end

--- InsertLink(opts)
-- Sets up and uses a picker from which users can pick a note to insert a link to
-- @param opts table Options if they should differ from user's configuration
local function InsertLink(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking
    opts.subdirs_in_links = opts.subdirs_in_links
        or config.options.subdirs_in_links

    -- If global dir check passes, set up a picker for picking a note
    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        local cwd = config.options.home
        local find_command = config.options.find_command
        local sort = config.options.sort
        local picker_actions = tkpickers.picker_actions
        local attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                if selection == nil then
                    selection = { filename = action_state.get_current_line() }
                end
                local pinfo = fileutils.Pinfo:new({
                    filepath = selection.filename or selection.value,
                    opts,
                })
                vim.api.nvim_put(
                    { "[[" .. pinfo.title .. "]]" },
                    "",
                    false,
                    true
                )
                if opts.i then
                    vim.api.nvim_feedkeys("a", "m", false)
                end
            end)
            map("i", "<c-y>", picker_actions.yank_link(opts))
            map("i", "<c-i>", picker_actions.paste_link(opts))
            map("n", "<c-y>", picker_actions.yank_link(opts))
            map("n", "<c-i>", picker_actions.paste_link(opts))
            map("i", "<c-cr>", picker_actions.paste_link(opts))
            map("n", "<c-cr>", picker_actions.paste_link(opts))
            return true
        end

        -- Open picker for users to chose note, preferring live grep
        if opts.with_live_grep then
            builtin.live_grep({
                prompt_title = "Insert link to note with live grep",
                cwd = cwd,
                attach_mappings = attach_mappings,
                find_command = find_command,
                sort = sort,
            })
        else
            fileutils.find_files_sorted({
                prompt_title = "Insert link to note",
                cwd = cwd,
                attach_mappings = attach_mappings,
                find_command = find_command,
                sort = sort,
            })
        end
    end)
end

--- PreviewImg(opts)
-- Takes text under cursor by normal yi, and if this is an image path, show it in a picker
-- @param opts table Options if they should differ from user's configuration
local function PreviewImg(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking

    -- If global dir check passes, then back up the current register "0 and yank what's under the cursor
    -- If the yanked text is a file name for a local image, present the preview in a picker
    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        local saved_reg = vim.fn.getreg('"0')
        vim.cmd("normal yi)")
        local fname = vim.fn.getreg('"0'):gsub("^img/", "")
        vim.fn.setreg('"0', saved_reg)

        -- check if fname exists anywhere
        local imageDir = config.options.image_subdir or config.options.home
        local fexists = fileutils.file_exists(imageDir .. "/" .. fname)
        local picker_actions = tkpickers.picker_actions

        if fexists == true then
            fileutils.find_files_sorted({
                prompt_title = "Preview image/media",
                cwd = imageDir,
                default_text = fname,
                find_command = config.options.find_command,
                filter_extensions = config.options.media_extensions,
                preview_type = "media",
                attach_mappings = function(prompt_bufnr, map)
                    actions.select_default:replace(function()
                        actions.close(prompt_bufnr)
                    end)
                    map("i", "<c-y>", picker_actions.yank_img_link(opts))
                    map("i", "<c-i>", picker_actions.paste_img_link(opts))
                    map("n", "<c-y>", picker_actions.yank_img_link(opts))
                    map("n", "<c-i>", picker_actions.paste_img_link(opts))
                    map("i", "<c-cr>", picker_actions.paste_img_link(opts))
                    map("n", "<c-cr>", picker_actions.paste_img_link(opts))
                    return true
                end,
                sort = config.options.sort,
            })
        else
            print("File not found: " .. config.options.home .. "/" .. fname)
        end
    end)
end

--- BrowseImg(opts)
-- Opens a picker filtering to only media for users to browse
-- @param opts table Options if they should differ from user's configuration
local function BrowseImg(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking

    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        local picker_actions = tkpickers.picker_actions
        fileutils.find_files_sorted({
            prompt_title = "Preview image/media",
            cwd = config.options.home,
            find_command = config.options.find_command,
            filter_extensions = config.options.media_extensions,
            preview_type = "media",
            attach_mappings = function(prompt_bufnr, map)
                actions.select_default:replace(function()
                    actions.close(prompt_bufnr)
                end)
                map("i", "<c-y>", picker_actions.yank_img_link(opts))
                map("i", "<c-i>", picker_actions.paste_img_link(opts))
                map("n", "<c-y>", picker_actions.yank_img_link(opts))
                map("n", "<c-i>", picker_actions.paste_img_link(opts))
                map("i", "<c-cr>", picker_actions.paste_img_link(opts))
                map("n", "<c-cr>", picker_actions.paste_img_link(opts))
                return true
            end,
            sort = config.options.sort,
        })
    end)
end

--- FindFriends(opts)
-- Opens a picker filtering to only notes linking to the note linked under the cursor
-- @param opts table Options if they should differ from user's configuration
local function FindFriends(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking

    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        -- Back up register "0, yank and save link under cursor, and restore "0
        local saved_reg = vim.fn.getreg('"0')
        vim.cmd("normal yi]")
        local title = vim.fn.getreg('"0')
        vim.fn.setreg('"0', saved_reg)

        title = linkutils.remove_alias(title)
        title = title:gsub("^(%[)(.+)(%])$", "%2")

        local picker_actions = tkpickers.picker_actions
        builtin.live_grep({
            prompt_title = "Notes referencing `" .. title .. "`",
            cwd = config.options.home,
            default_text = "\\[\\[" .. title .. "([#|].+)?\\]\\]",
            find_command = config.options.find_command,
            attach_mappings = function(_, map)
                actions.select_default:replace(picker_actions.select_default)
                map("i", "<c-y>", picker_actions.yank_link(opts))
                map("i", "<c-i>", picker_actions.paste_link(opts))
                map("n", "<c-y>", picker_actions.yank_link(opts))
                map("n", "<c-i>", picker_actions.paste_link(opts))
                map("i", "<c-cr>", picker_actions.paste_link(opts))
                map("n", "<c-cr>", picker_actions.paste_link(opts))
                return true
            end,
        })
    end)
end

--- YankLink()
-- Create and yank a [[link]] from the current note to unnamed register ""
local function YankLink()
    local title = "[["
        .. fileutils.Pinfo:new({
            filepath = vim.fn.expand("%:p"),
            config.options,
        }).title
        .. "]]"
    vim.fn.setreg('"', title)

    print("yanked " .. title)
end

--- RenameNote()
--- Prompt for new note title, rename the note and update all links.
local function RenameNote()
    local oldfile =
        fileutils.Pinfo:new({ filepath = vim.fn.expand("%:p"), config.options })

    fileutils.prompt_title(
        config.options.extension,
        oldfile.title,
        function(newname)
            local newpath = newname:match("(.*/)") or ""
            newpath = config.options.home .. "/" .. newpath

            -- If no subdir specified, place the new note in the same place as old note
            if
                config.options.subdirs_in_links == true
                and newpath == config.options.home .. "/"
                and oldfile.sub_dir ~= ""
            then
                newname = oldfile.sub_dir .. "/" .. newname
            end

            local fname = config.options.home
                .. "/"
                .. newname
                .. config.options.extension
            local fexists = fileutils.file_exists(fname)
            if fexists then
                tkutils.print_error("File alreay exists. Renaming abandoned")
                return
            end

            -- Savas newfile, delete buffer of old one and remove old file
            if newname ~= "" and newname ~= oldfile.title then
                fileutils.check_dir_and_ask(
                    newpath,
                    "Renamed file",
                    function(success)
                        if not success then
                            return
                        end

                        local oldTitle = oldfile.title:gsub(" ", "\\ ")
                        vim.cmd(
                            "saveas "
                                .. config.options.home
                                .. "/"
                                .. newname
                                .. config.options.extension
                        )
                        vim.cmd(
                            "bdelete " .. oldTitle .. config.options.extension
                        )
                        os.execute(
                            "rm "
                                .. config.options.home
                                .. "/"
                                .. oldTitle
                                .. config.options.extension
                        )
                        linkutils.rename_update_links(oldfile, newname)
                    end
                )
            else
                linkutils.rename_update_links(oldfile, newname)
            end
        end
    )
end

--- GoToDate(opts)
-- find note for date and create it if necessary.
-- @param opts table Options if they should differ from user's configuration
-- Move to utils/files.lua? Technically not user facing...
local function GotoDate(opts)
    opts = opts or {}

    opts.dates = dateutils.calculate_dates(
        opts.date_table,
        config.options.calendar_opts.calendar_monday
    )
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking
    opts.journal_auto_open = opts.journal_auto_open
        or config.options.journal_auto_open

    local pcfg = config.options.periodic
    if not pcfg or not pcfg.kinds or not pcfg.kinds.daily then
        tkutils.print_error("periodic.daily is not configured")
        return
    end

    local kcfg = pcfg.kinds.daily
    if not kcfg.enabled then
        tkutils.print_error("daily periodic notes are disabled")
        return
    end

    local dinfo = opts.dates or os.date(dateutils.dateformats.date)
    local fname, title, root_dir, _ =
        periodic.build_path(pcfg, "daily", dinfo, config.options.extension)

    local fexists = fileutils.file_exists(fname)
    local picker_actions = tkpickers.picker_actions
    local function picker()
        if opts.journal_auto_open then
            if opts.calendar == true then
                -- ensure that the calendar window is not improperly overwritten
                vim.cmd("wincmd w")
            end
            vim.cmd("e " .. fname)
        else
            fileutils.find_files_sorted({
                prompt_title = "Goto day",
                cwd = periodic.search_root(pcfg, "daily") or root_dir,
                default_text = title,
                find_command = config.options.find_command,
                attach_mappings = function(prompt_bufnr, map)
                    actions.select_default:replace(function()
                        actions.close(prompt_bufnr)

                        -- open the new note
                        if opts.calendar == true then
                            vim.cmd("wincmd w")
                        end
                        vim.cmd("e " .. fname)
                        picker_actions.post_open()
                    end)
                    map("i", "<c-y>", picker_actions.yank_link(opts))
                    map("i", "<c-i>", picker_actions.paste_link(opts))
                    map("n", "<c-y>", picker_actions.yank_link(opts))
                    map("n", "<c-i>", picker_actions.paste_link(opts))
                    map("n", "<c-c>", picker_actions.close(opts))
                    map("n", "<esc>", picker_actions.close(opts))
                    return true
                end,
            })
        end
    end

    if (not fexists) and kcfg.create_if_missing then
        fileutils.create_note_from_template(
            title,
            nil,
            fname,
            kcfg.template_file,
            dinfo,
            function()
                opts.erase = true
                opts.erase_file = fname
                picker()
            end
        )
        return
    end

    picker()
end

--- GotoToday(opts)
-- Find today's daily note and create it if necessary.
-- @param opts table Options if they should differ from user's configuration
local function GotoToday(opts)
    opts = opts or {}

    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        local today = os.date(dateutils.dateformats.date)
        opts.date_table = os.date("*t")
        opts.date = today
        local pcfg = opts.periodic or config.options.periodic
        local kcfg = pcfg.kinds.daily
        kcfg.create_if_missing = true -- Always use template for GotoToday

        GotoDate(opts)
    end)
end

--- FindNotes(opts)
-- Select from notes
-- @param opts table Options if they should differ from user's configuration
local function FindNotes(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking

    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        local cwd = config.options.home
        local find_command = config.options.find_command
        local sort = config.options.sort
        local picker_actions = tkpickers.picker_actions
        local attach_mappings = function(_, map)
            actions.select_default:replace(picker_actions.select_default)
            map("i", "<c-y>", picker_actions.yank_link(opts))
            map("i", "<c-i>", picker_actions.paste_link(opts))
            map("n", "<c-y>", picker_actions.yank_link(opts))
            map("n", "<c-i>", picker_actions.paste_link(opts))
            map("i", "<c-cr>", picker_actions.paste_link(opts))
            map("n", "<c-cr>", picker_actions.paste_link(opts))
            if config.options.enable_create_new then
                map("i", "<c-n>", picker_actions.create_new(opts))
                map("n", "<c-n>", picker_actions.create_new(opts))
            end
            return true
        end

        if opts.with_live_grep then
            builtin.live_grep({
                prompt_title = "Find notes by live grep",
                cwd = cwd,
                find_command = find_command,
                attach_mappings = attach_mappings,
                sort = sort,
            })
        else
            fileutils.find_files_sorted({
                prompt_title = "Find notes by name",
                cwd = cwd,
                find_command = find_command,
                attach_mappings = attach_mappings,
                sort = sort,
            })
        end
    end)
end

--- InsertImgLink(opts)
-- Insert link to image / media, with optional preview
-- @param opts table Options if they should differ from user's configuration
local function InsertImgLink(opts)
    opts = opts or {}

    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        local picker_actions = tkpickers.picker_actions
        fileutils.find_files_sorted({
            prompt_title = "Find image/media",
            cwd = config.options.home,
            find_command = config.options.find_command,
            filter_extensions = config.options.media_extensions,
            preview_type = "media",
            attach_mappings = function(prompt_bufnr, map)
                actions.select_default:replace(function()
                    actions.close(prompt_bufnr)
                    local selection = action_state.get_selected_entry()
                    local fn = selection.value
                    fn = linkutils.make_relative_path(
                        vim.fn.expand("%:p"),
                        fn,
                        "/"
                    )
                    vim.api.nvim_put({ "![](" .. fn .. ")" }, "", true, true)
                    if opts.i then
                        vim.api.nvim_feedkeys("A", "m", false)
                    end
                end)
                map("i", "<c-y>", picker_actions.yank_img_link(opts))
                map("i", "<c-i>", picker_actions.paste_img_link(opts))
                map("n", "<c-y>", picker_actions.yank_img_link(opts))
                map("n", "<c-i>", picker_actions.paste_img_link(opts))
                map("i", "<c-cr>", picker_actions.paste_img_link(opts))
                map("n", "<c-cr>", picker_actions.paste_img_link(opts))
                return true
            end,
            sort = config.options.sort,
        })
    end)
end

--- SearchNotes(opts)
-- Find the file linked to by the word under the cursor
-- @param opts table Options if they should differ from user's configuration
local function SearchNotes(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking

    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        local picker_actions = tkpickers.picker_actions
        builtin.live_grep({
            prompt_title = "Search in notes",
            cwd = config.options.home,
            search_dirs = { config.options.home },
            default_text = opts.default_text or vim.fn.expand("<cword>"),
            find_command = config.options.find_command,
            attach_mappings = function(_, map)
                actions.select_default:replace(picker_actions.select_default)
                map("i", "<c-y>", picker_actions.yank_link(opts))
                map("i", "<c-i>", picker_actions.paste_link(opts))
                map("n", "<c-y>", picker_actions.yank_link(opts))
                map("n", "<c-i>", picker_actions.paste_link(opts))
                map("i", "<c-cr>", picker_actions.paste_link(opts))
                map("n", "<c-cr>", picker_actions.paste_link(opts))
                return true
            end,
        })
    end)
end

--- ShowBacklinks(opts)
-- Find all notes linking to this one
-- @param opts table Options if they should differ from user's configuration
local function ShowBacklinks(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking

    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        local title = fileutils.Pinfo:new({
            filepath = vim.fn.expand("%:p"),
            config.options,
        }).title
        -- or vim.api.nvim_buf_get_name(0)

        local escaped_title = string.gsub(title, "%(", "\\(")
        escaped_title = string.gsub(escaped_title, "%)", "\\)")

        local picker_actions = tkpickers.picker_actions
        builtin.live_grep({
            results_title = "Backlinks to " .. title,
            prompt_title = "Search",
            cwd = config.options.home,
            search_dirs = { config.options.home },
            default_text = "\\[\\[" .. escaped_title .. "([#|].+)?\\]\\]",
            find_command = config.options.find_command,
            attach_mappings = function(_, map)
                actions.select_default:replace(picker_actions.select_default)
                map("i", "<c-y>", picker_actions.yank_link(opts))
                map("i", "<c-i>", picker_actions.paste_link(opts))
                map("n", "<c-y>", picker_actions.yank_link(opts))
                map("n", "<c-i>", picker_actions.paste_link(opts))
                map("i", "<c-cr>", picker_actions.paste_link(opts))
                map("n", "<c-cr>", picker_actions.paste_link(opts))
                return true
            end,
        })
    end)
end

--- CreateNoteSelectTemplate(opts, title)
-- Prompts for title, then pops up telescope for template selection, creates the new note by template and opens it
-- @param opts table Options if they should differ from user's configuration
-- Move? Used by CreateNoteSelectTemplate and FollowLink. Maybe good case for utils/init.lua to share it?
local function on_create_with_template(opts, title)
    if title == nil then
        return
    end

    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking
    opts.new_note_location = opts.new_note_location
        or config.options.new_note_location
    opts.template_handling = opts.template_handling
        or config.options.template_handling
    local uuid_type = opts.uuid_type or config.options.uuid_type
    local picker_actions = tkpickers.picker_actions

    local uuid = fileutils.new_uuid(uuid_type)
    local pinfo = fileutils.Pinfo:new({
        title = fileutils.generate_note_filename(uuid, title),
        opts,
    })
    local fname = pinfo.filepath
    if pinfo.fexists == true then
        -- open the new note
        vim.cmd("e " .. fname)
        picker_actions.post_open()
        return
    end

    fileutils.find_files_sorted({
        prompt_title = "Select template...",
        cwd = config.options.templates,
        find_command = config.options.find_command,
        attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                -- local template = config.options.templates .. "/" .. action_state.get_selected_entry().value
                local template = action_state.get_selected_entry().value
                -- TODO: pass in the calendar_info returned from the pinfo
                fileutils.create_note_from_template(
                    title,
                    uuid,
                    fname,
                    template,
                    pinfo.calendar_info,
                    function()
                        -- open the new note
                        vim.cmd("e " .. fname)
                        picker_actions.post_open()
                    end
                )
            end)
            map("i", "<c-y>", picker_actions.yank_link(opts))
            map("i", "<c-i>", picker_actions.paste_link(opts))
            map("n", "<c-y>", picker_actions.yank_link(opts))
            map("n", "<c-i>", picker_actions.paste_link(opts))
            return true
        end,
    })
end

--- CreateNoteSelectTemplate(opts)
-- Select a template and create a new note
-- @param opts table Options if they should differ from user's configuration
local function CreateNoteSelectTemplate(opts)
    opts = opts or {}

    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        -- change the cwd to the configured home directory, so tab completion
        -- works for the folders in that directory
        vim.fn.chdir(config.options.home)
        fileutils.prompt_title(config.options.extension, nil, function(title)
            on_create_with_template(opts, title)
        end, config.options.home)
    end)
end

--- CreateNote(opts)
-- Prompts for title and creates note with default template
-- @param opts table Options if they should differ from user's configuration
local function CreateNote(opts)
    opts = opts or {}

    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        if config.options.template_handling == "always_ask" then
            return CreateNoteSelectTemplate(opts)
        end

        -- get the current working directory
        local current_dir = vim.fn.getcwd()
        -- change the cwd to the configured home directory, so tab completion
        -- works for the folders in that directory
        vim.fn.chdir(config.options.home)
        fileutils.prompt_title(config.options.extension, nil, function(title)
            tkpickers.on_create(opts, title)
        end)
        -- change back to the original directory
        vim.fn.chdir(current_dir)
    end)
end

--- FollowLink(opts)
-- Find the file linked to by the word under the cursor
-- @param opts table Options if they should differ from user's configuration
local function FollowLink(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking

    opts.template_handling = opts.template_handling
        or config.options.template_handling
    opts.new_note_location = opts.new_note_location
        or config.options.new_note_location
    local uuid_type = opts.uuid_type or config.options.uuid_type

    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        local search_mode = "files"
        local title
        local filename_part = ""
        local picker_actions = tkpickers.picker_actions

        -- first: check if we're in a tag or a link
        local kind
        local globArg = ""

        if opts.follow_tag ~= nil then
            kind = "tag"
            title = opts.follow_tag
            if opts.templateDir ~= nil then
                globArg = "--glob=!" .. "**/" .. opts.templateDir .. "/*.md"
            end
        else
            kind, _ = taglinks.check_for_link_or_tag()
        end

        if kind == "tag" then
            search_mode = "tag"
            if title == nil then
                local saved_reg = vim.fn.getreg('"0')
                vim.cmd("normal yiw")
                title = vim.fn.getreg('"0')
                vim.fn.setreg('"0', saved_reg)
            end
        else
            local saved_reg = vim.fn.getreg('"0')
            if kind == "link" then
                -- we are in a link
                vim.cmd("normal yi]")
                title = vim.fn.getreg('"0')
                title = title:gsub("^(%[)(.+)(%])$", "%2")
                title = title:gsub("%s*\n", " ")
                title = linkutils.remove_alias(title)

                -- Check if this is an absolute path link (external file)
                if
                    config.options.external_link_follow
                    and (
                        title:match("^~/")
                        or title:match("^/")
                        or title:match("^%a:")
                    )
                then
                    -- This is an absolute path link to an external file
                    vim.fn.setreg('"0', saved_reg)

                    -- Handle absolute path immediately
                    local external_opts = vim.tbl_extend("force", opts, {
                        is_absolute_path = true,
                        absolute_path_title = title,
                        title = title,
                    })
                    local pinfo = fileutils.Pinfo:new(external_opts)

                    if pinfo.fexists then
                        -- File exists, open it
                        vim.cmd("e " .. vim.fn.fnameescape(pinfo.filepath))
                    else
                        -- File doesn't exist (read-only mode for external files)
                        print("External file not found: " .. pinfo.filepath)
                    end
                    return
                end
            else
                -- we are in an external [link]
                vim.cmd("normal yi)")
                local url = vim.fn.getreg('"0')
                vim.fn.setreg('"0', saved_reg)
                return linkutils.follow_url(url)
            end
            vim.fn.setreg('"0', saved_reg)

            local parts = vim.split(title, "#")

            -- if there is a #
            if #parts ~= 1 then
                search_mode = "heading"
                title = parts[2]
                filename_part = parts[1]
                parts = vim.split(title, "%^")
                if #parts ~= 1 then
                    search_mode = "para"
                    title = parts[2]
                end
            end

            -- this applies to heading and para search_mode
            -- if we cannot find the file, revert to global heading search by
            -- setting filename to empty string
            if #filename_part > 0 then
                local pinfo = fileutils.Pinfo:new({ title = filename_part })
                filename_part = pinfo.filepath
                if pinfo.fexists == false then
                    -- print("error")
                    filename_part = ""
                end
            end
        end

        if search_mode == "files" then
            -- check if subdir exists
            local filepath = title:match("(.*/)") or ""
            filepath = config.options.home .. "/" .. filepath
            fileutils.check_dir_and_ask(filepath, "", function()
                -- check if fname exists anywhere
                local pinfo = fileutils.Pinfo:new({ title = title })
                local function picker()
                    fileutils.find_files_sorted({
                        prompt_title = "Follow link to note...",
                        cwd = pinfo.root_dir,
                        default_text = title,
                        find_command = config.options.find_command,
                        attach_mappings = function(_, map)
                            actions.select_default:replace(
                                picker_actions.select_default
                            )
                            map("i", "<c-y>", picker_actions.yank_link(opts))
                            map("i", "<c-i>", picker_actions.paste_link(opts))
                            map("n", "<c-y>", picker_actions.yank_link(opts))
                            map("n", "<c-i>", picker_actions.paste_link(opts))
                            map("n", "<c-c>", picker_actions.close(opts))
                            map("n", "<esc>", picker_actions.close(opts))
                            return true
                        end,
                        sort = config.options.sort,
                    })
                end

                if
                    (pinfo.fexists ~= true)
                    and (
                        (opts.follow_creates_nonexisting == true)
                        or config.options.follow_creates_nonexisting == true
                    )
                then
                    if opts.template_handling == "always_ask" then
                        return on_create_with_template(opts, title)
                    end

                    if #pinfo.filepath > 0 then
                        local uuid = fileutils.new_uuid(uuid_type)
                        fileutils.create_note_from_template(
                            title,
                            uuid,
                            pinfo.filepath,
                            pinfo.template,
                            pinfo.calendar_info,
                            function()
                                opts.erase = true
                                opts.erase_file = pinfo.filepath
                                picker()
                            end
                        )
                        return
                    end
                end

                picker()
            end)
        end

        if search_mode ~= "files" then
            local search_pattern = title
            local cwd = config.options.home

            opts.cwd = cwd
            local counts = nil
            if opts.show_link_counts then
                counts = linkutils.generate_backlink_map(config.options)
            end

            -- display with devicons
            local function iconic_display(display_entry)
                local display_opts = {
                    path_display = function(_, e)
                        return e:gsub(tkutils.escape(opts.cwd .. "/"), "")
                    end,
                }

                local hl_group
                local display =
                    utils.transform_path(display_opts, display_entry.value)

                display_entry.filn = display_entry.filn
                    or display:gsub(":.*", "")
                display, hl_group =
                    utils.transform_devicons(display_entry.filn, display, false)

                if hl_group then
                    return display, { { { 1, 3 }, hl_group } }
                else
                    return display
                end
            end

            -- for media_files
            local popup_opts = {}
            opts.get_preview_window = function()
                return popup_opts.preview
            end

            -- local width = config.width
            --     or config.layout_config.width
            --     or config.layout_config[config.layout_strategy].width
            --     or vim.o.columns
            -- local telescope_win_width
            -- if width > 1 then
            --     telescope_win_width = width
            -- else
            --     telescope_win_width = math.floor(vim.o.columns * width)
            -- end
            local displayer = entry_display.create({
                separator = "",
                items = {
                    { width = 4 },
                    { width = 4 },
                    { remaining = true },
                },
            })

            local function make_display(entry)
                local fn = entry.filename
                local nlinks = counts.link_counts[fn] or 0
                local nbacks = counts.backlink_counts[fn] or 0

                if opts.show_link_counts then
                    local display, hl = iconic_display(entry)

                    return displayer({
                        {
                            "L" .. tostring(nlinks),
                            function()
                                return {
                                    { { 0, 1 }, "tkTagSep" },
                                    { { 1, 3 }, "tkTag" },
                                }
                            end,
                        },
                        {
                            "B" .. tostring(nbacks),
                            function()
                                return {
                                    { { 0, 1 }, "tkTagSep" },
                                    { { 1, 3 }, "DevIconMd" },
                                }
                            end,
                        },
                        {
                            display,
                            function()
                                return hl
                            end,
                        },
                    })
                else
                    return iconic_display(entry)
                end
            end

            local lookup_keys = {
                value = 1,
                ordinal = 1,
            }

            local find = (function()
                if Path.path.sep == "\\" then
                    return function(t)
                        local start, _, filn, lnum, col, text =
                            string.find(t, [[([^:]+):(%d+):(%d+):(.*)]])

                        -- Handle Windows drive letter (e.g. "C:") at the beginning (if present)
                        if start == 3 then
                            filn = string.sub(t.value, 1, 3) .. filn
                        end

                        return filn, lnum, col, text
                    end
                else
                    return function(t)
                        local _, _, filn, lnum, col, text =
                            string.find(t, [[([^:]+):(%d+):(%d+):(.*)]])
                        return filn, lnum, col, text
                    end
                end
            end)()

            local parse = function(t)
                -- print("t: ", vim.inspect(t))
                local filn, lnum, col, text = find(t.value)

                local ok
                ok, lnum = pcall(tonumber, lnum)
                if not ok then
                    lnum = nil
                end

                ok, col = pcall(tonumber, col)
                if not ok then
                    col = nil
                end

                t.filn = filn
                t.lnum = lnum
                t.col = col
                t.text = text

                return { filn, lnum, col, text }
            end

            local function entry_maker(_)
                local mt_vimgrep_entry

                opts = opts or {}

                -- local disable_devicons = opts.disable_devicons
                -- local disable_coordinates = opts.disable_coordinates or true
                local only_sort_text = opts.only_sort_text

                local execute_keys = {
                    path = function(t)
                        if Path:new(t.filename):is_absolute() then
                            return t.filename, false
                        else
                            return Path:new({ t.cwd, t.filename }):absolute(),
                                false
                        end
                    end,
                    filename = function(t)
                        return parse(t)[1], true
                    end,
                    lnum = function(t)
                        return parse(t)[2], true
                    end,
                    col = function(t)
                        return parse(t)[3], true
                    end,
                    text = function(t)
                        return parse(t)[4], true
                    end,
                }

                -- For text search only, the ordinal value is actually the text.
                if only_sort_text then
                    execute_keys.ordinal = function(t)
                        return t.text
                    end
                end

                mt_vimgrep_entry = {
                    cwd = vim.fn.expand(opts.cwd or vim.loop.cwd()),
                    __index = function(t, k)
                        local raw = rawget(mt_vimgrep_entry, k)
                        if raw then
                            return raw
                        end

                        local executor = rawget(execute_keys, k)
                        if executor then
                            local val, save = executor(t)
                            if save then
                                rawset(t, k, val)
                            end
                            return val
                        end

                        return rawget(t, rawget(lookup_keys, k))
                    end,
                }

                --
                if opts.show_link_counts then
                    mt_vimgrep_entry.display = make_display
                else
                    mt_vimgrep_entry.display = iconic_display
                end

                return function(line)
                    return setmetatable({ line }, mt_vimgrep_entry)
                end
            end

            opts.entry_maker = entry_maker(opts)

            local live_grepper = finders.new_job(
                function(prompt)
                    if not prompt or prompt == "" then
                        return nil
                    end

                    local search_command = {
                        "rg",
                        "--vimgrep",
                        "-e",
                        "^#+\\s" .. prompt,
                        "--",
                    }
                    if search_mode == "para" then
                        search_command = {
                            "rg",
                            "--vimgrep",
                            "-e",
                            "\\^" .. prompt,
                            "--",
                        }
                    end

                    if search_mode == "tag" then
                        search_command = {
                            "rg",
                            "--vimgrep",
                            globArg,
                            "-e",
                            prompt,
                            "--",
                        }
                    end

                    if #filename_part > 0 then
                        table.insert(search_command, filename_part)
                    else
                        table.insert(search_command, cwd)
                    end

                    local ret = vim.tbl_flatten({ search_command })
                    return ret
                end,
                opts.entry_maker or make_entry.gen_from_vimgrep(opts),
                opts.max_results,
                opts.cwd
            )

            -- builtin.live_grep({
            local picker = pickers.new(opts, {
                cwd = cwd,
                prompt_title = "Notes referencing `" .. title .. "`",
                default_text = search_pattern,
                initial_mode = "insert",
                -- link to specific file (a daily file): [[2021-02-22]]
                -- link to heading in specific file (a daily file): [[2021-02-22#Touchpoint]]
                -- link to heading globally [[#Touchpoint]]
                -- link to heading in specific file (a daily file): [[The cool note#^xAcSh-xxr]]
                -- link to paragraph globally [[#^xAcSh-xxr]]
                finder = live_grepper,
                previewer = conf.grep_previewer(opts),
                sorter = sorters.highlighter_only(opts),
                attach_mappings = function(_, map)
                    actions.select_default:replace(
                        picker_actions.select_default
                    )
                    map("i", "<c-y>", picker_actions.yank_link(opts))
                    map("i", "<c-i>", picker_actions.paste_link(opts))
                    map("n", "<c-y>", picker_actions.yank_link(opts))
                    map("n", "<c-i>", picker_actions.paste_link(opts))
                    map("i", "<c-cr>", picker_actions.paste_link(opts))
                    map("n", "<c-cr>", picker_actions.paste_link(opts))
                    return true
                end,
            })
            picker:find()
        end
    end)
end

--- GotoThisWeek(opts)
-- Find this week's weekly note and create it if necessary.
-- @param opts table Options if they should differ from user's configuration
local function GotoThisWeek(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking
    opts.journal_auto_open = opts.journal_auto_open
        or config.options.journal_auto_open

    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        local dinfo = dateutils.calculate_dates(
            nil,
            config.options.calendar_opts.calendar_monday
        )

        local pcfg = config.options.periodic
        local fname, title, root_dir, _ =
            periodic.build_path(pcfg, "weekly", dinfo, config.options.extension)
        if not fname or not root_dir then
            return
        end

        local kcfg = pcfg.kinds.weekly
        local fexists = fileutils.file_exists(fname)
        local search_root = periodic.search_root(pcfg, "weekly")

        local picker_actions = tkpickers.picker_actions
        local function picker()
            if opts.journal_auto_open then
                if opts.calendar == true then
                    -- ensure that the calendar window is not improperly overwritten
                    vim.cmd("wincmd w")
                end
                vim.cmd("e " .. fname)
            else
                fileutils.find_files_sorted({
                    prompt_title = "Goto this week:",
                    cwd = search_root,
                    default_text = title,
                    find_command = config.options.find_command,
                    attach_mappings = function(_, map)
                        actions.select_default:replace(
                            picker_actions.select_default
                        )
                        map("i", "<c-y>", picker_actions.yank_link(opts))
                        map("i", "<c-i>", picker_actions.paste_link(opts))
                        map("n", "<c-y>", picker_actions.yank_link(opts))
                        map("n", "<c-i>", picker_actions.paste_link(opts))
                        map("n", "<c-c>", picker_actions.close(opts))
                        map("n", "<esc>", picker_actions.close(opts))
                        return true
                    end,
                })
            end
        end

        if (not fexists) and kcfg.create_if_missing then
            local template = kcfg.template_file or M.note_type_templates.weekly
            fileutils.create_note_from_template(
                title,
                nil,
                fname,
                template,
                nil,
                function()
                    opts.erase = true
                    opts.erase_file = fname
                    picker()
                end
            )
            return
        end

        picker()
    end)
end

--- GotoThisMonth(opts)
-- Find this month's monthly note and create it if necessary.
-- @param opts table Options if they should differ from user's configuration
local function GotoThisMonth(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking
    opts.journal_auto_open = opts.journal_auto_open
        or config.options.journal_auto_open

    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        local dinfo = dateutils.calculate_dates(
            nil,
            config.options.calendar_opts.calendar_monday
        )

        local pcfg = config.options.periodic
        local fname, title, root_dir, _ = periodic.build_path(
            pcfg,
            "monthly",
            dinfo,
            config.options.extension
        )
        if not fname or not root_dir then
            return
        end

        local kcfg = pcfg.kinds.monthly
        local fexists = fileutils.file_exists(fname)
        local search_root = periodic.search_root(pcfg, "monthly")
        local search_pattern =
            periodic.filename_pattern(pcfg, "monthly", config.options.extension)

        local picker_actions = tkpickers.picker_actions

        local function picker()
            if opts.journal_auto_open then
                if opts.calendar == true then
                    -- ensure that the calendar window is not improperly overwritten
                    vim.cmd("wincmd w")
                end
                vim.cmd("e " .. fname)
            else
                fileutils.find_files_sorted({
                    prompt_title = "Goto this month:",
                    cwd = search_root,
                    default_text = title,
                    -- Include search pattern so we only find monthlies and not dailies
                    search_pattern = search_pattern,
                    find_command = config.options.find_command,
                    attach_mappings = function(_, map)
                        actions.select_default:replace(
                            picker_actions.select_default
                        )
                        map("i", "<c-y>", picker_actions.yank_link(opts))
                        map("i", "<c-i>", picker_actions.paste_link(opts))
                        map("n", "<c-y>", picker_actions.yank_link(opts))
                        map("n", "<c-i>", picker_actions.paste_link(opts))
                        map("n", "<c-c>", picker_actions.close(opts))
                        map("n", "<esc>", picker_actions.close(opts))
                        return true
                    end,
                })
            end
        end

        if (not fexists) and kcfg.create_if_missing then
            fileutils.create_note_from_template(
                title,
                nil,
                fname,
                kcfg.template_file,
                nil,
                function()
                    opts.erase = true
                    opts.erase_file = fname
                    picker()
                end
            )
            return
        end

        picker()
    end)
end

--- GotoThisQuarter(opts)
-- Find this quarter's quarterly note and create it if necessary.
-- @param opts table Options if they should differ from user's configuration
local function GotoThisQuarter(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking
    opts.journal_auto_open = opts.journal_auto_open
        or config.options.journal_auto_open

    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        -- Use direct value instead of dateformat.quarter_yq, because os.date doesn't properly expand to a date
        local dinfo = dateutils.calculate_dates(
            nil,
            config.options.calendar_opts.calendar_monday
        )

        local pcfg = config.options.periodic
        local fname, title, root_dir, _ = periodic.build_path(
            pcfg,
            "quarterly",
            dinfo,
            config.options.extension
        )
        if not fname or not root_dir then
            return
        end

        local kcfg = pcfg.kinds.quarterly
        local fexists = fileutils.file_exists(fname)
        local search_root = periodic.search_root(pcfg, "quarterly")

        local picker_actions = tkpickers.picker_actions

        local function picker()
            if opts.journal_auto_open then
                if opts.calendar == true then
                    -- ensure that the calendar window is not improperly overwritten
                    vim.cmd("wincmd w")
                end
                vim.cmd("e " .. fname)
            else
                fileutils.find_files_sorted({
                    prompt_title = "Goto this quarter:",
                    cwd = search_root,
                    default_text = title,
                    find_command = config.options.find_command,
                    attach_mappings = function(_, map)
                        actions.select_default:replace(
                            picker_actions.select_default
                        )
                        map("i", "<c-y>", picker_actions.yank_link(opts))
                        map("i", "<c-i>", picker_actions.paste_link(opts))
                        map("n", "<c-y>", picker_actions.yank_link(opts))
                        map("n", "<c-i>", picker_actions.paste_link(opts))
                        map("n", "<c-c>", picker_actions.close(opts))
                        map("n", "<esc>", picker_actions.close(opts))
                        return true
                    end,
                })
            end
        end

        if (not fexists) and kcfg.create_if_missing then
            fileutils.create_note_from_template(
                title,
                nil,
                fname,
                kcfg.template_file,
                nil,
                function()
                    opts.erase = true
                    opts.erase_file = fname
                    picker()
                end
            )
            return
        end

        picker()
    end)
end

--- GotoThisYear(opts)
-- Find this year's yearly note and create it if necessary.
-- @param opts table Options if they should differ from user's configuration
local function GotoThisYear(opts)
    opts = opts or {}
    opts.insert_after_inserting = opts.insert_after_inserting
        or config.options.insert_after_inserting
    opts.close_after_yanking = opts.close_after_yanking
        or config.options.close_after_yanking
    opts.journal_auto_open = opts.journal_auto_open
        or config.options.journal_auto_open

    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        local dinfo = dateutils.calculate_dates(
            nil,
            config.options.calendar_opts.calendar_monday
        )

        local pcfg = config.options.periodic
        local fname, title, root_dir, _ =
            periodic.build_path(pcfg, "yearly", dinfo, config.options.extension)
        if not fname or not root_dir then
            return
        end

        local kcfg = pcfg.kinds.yearly
        local fexists = fileutils.file_exists(fname)
        local search_root = periodic.search_root(pcfg, "yearly")

        local picker_actions = tkpickers.picker_actions

        local function picker()
            if opts.journal_auto_open then
                if opts.calendar == true then
                    -- ensure that the calendar window is not improperly overwritten
                    vim.cmd("wincmd w")
                end
                vim.cmd("e " .. fname)
            else
                fileutils.find_files_sorted({
                    prompt_title = "Goto this year:",
                    cwd = search_root,
                    default_text = title,
                    find_command = config.options.find_command,
                    attach_mappings = function(_, map)
                        actions.select_default:replace(
                            picker_actions.select_default
                        )
                        map("i", "<c-y>", picker_actions.yank_link(opts))
                        map("i", "<c-i>", picker_actions.paste_link(opts))
                        map("n", "<c-y>", picker_actions.yank_link(opts))
                        map("n", "<c-i>", picker_actions.paste_link(opts))
                        map("n", "<c-c>", picker_actions.close(opts))
                        map("n", "<esc>", picker_actions.close(opts))
                        return true
                    end,
                })
            end
        end

        if (not fexists) and kcfg.create_if_missing then
            fileutils.create_note_from_template(
                title,
                nil,
                fname,
                kcfg.template_file,
                nil,
                function()
                    opts.erase = true
                    opts.erase_file = fname
                    picker()
                end
            )
            return
        end

        picker()
    end)
end

--- CalendarSignDay(day, month, year)
-- Return if a daily 'note exists' indicator (sign) should be displayed for a particular day
-- @param day number Day of the month
-- @param month number Month of the year
-- @param year number Year of the Gregorian calendar
-- @return number Representing a boolean, 0 for false and 1 for true
local function CalendarSignDay(day, month, year)
    local daily_path = config.options.periodic.kinds.daily.folder_path
    local fn = daily_path
        .. "/"
        .. string.format("%04d-%02d-%02d", year, month, day)
        .. config.options.extension
    if fileutils.file_exists(fn) then
        return 1
    end
    return 0
end

--- CalendarAction(day, month, year, _, _)
-- Action on enter on a specific day:
-- Preview in telescope, stay in calendar on cancel, open note in other window on accept
-- @param day number Day of the month
-- @param month number Month of the year
-- @param year number Year of the Gregorian calendar
-- @param _ any Unused
-- @param _ any Unused
-- TODO: Ensure it's safe to remove the extra paramters
local function CalendarAction(day, month, year, _, _)
    local opts = {}
    opts.date = string.format("%04d-%02d-%02d", year, month, day)
    opts.date_table = { year = year, month = month, day = day }
    opts.calendar = true
    GotoDate(opts)
end

--- ShowCalendar(opts)
-- Display the calendar
-- @param opts table Options if they should differ from user's configuration
-- TODO: No attempt made to backup load from config as in other functions taking opts. See if one can be added
local function ShowCalendar(opts)
    local defaults = {}
    defaults.cmd = "CalendarVR"
    defaults.vertical_resize = 1

    opts = opts or defaults
    vim.cmd(opts.cmd)
    if opts.vertical_resize then
        vim.cmd("vertical resize +" .. opts.vertical_resize)
    end
    vim.cmd([[
      set signcolumn=no
      set nonumber
      set norelativenumber
    ]])
end

--- SetupCalendar(opts)
-- Set up calendar integration with vim commands, forward to our lua functions
-- @param opts table Options if they should differ from user's configuration
-- Move to config.lua? More related to initial setup, though. Maybe telekasten/init.lua?
local function SetupCalendar(opts)
    local defaults = config.options.calendar_opts
    opts = opts or defaults

    local cmd = [[
        function! MyCalSign(day, month, year)
            return luaeval('require("telekasten").CalendarSignDay(_A[1], _A[2], _A[3])', [a:day, a:month, a:year])
        endfunction

        function! MyCalAction(day, month, year, weekday, dir)
            " day : day
            " month : month
            " year year
            " weekday : day of week (monday=1)
            " dir : direction of calendar
            return luaeval('require("telekasten").CalendarAction(_A[1], _A[2], _A[3], _A[4], _A[5])',
                                                                 \ [a:day, a:month, a:year, a:weekday, a:dir])
        endfunction

        function! MyCalBegin()
            " too early, windown doesn't exist yet
            " cannot resize
        endfunction

        let g:calendar_sign = 'MyCalSign'
        let g:calendar_action = 'MyCalAction'
        " let g:calendar_begin = 'MyCalBegin'

        let g:calendar_mark = '{{calendar_mark}}'
        let g:calendar_weeknm = {{weeknm}}
    ]]

    for k, v in pairs(opts) do
        cmd = cmd:gsub("{{" .. k .. "}}", v)
    end
    vim.cmd(cmd)
    if opts.calendar_monday == 1 then
        vim.cmd("let g:calendar_monday = 1")
    end
end

--- ToggleTodo(opts)
-- Toggles todo status under the cursor
-- @param opts table Options if they should differ from user's configuration
local function ToggleTodo(opts)
    -- replace
    --       by -
    -- -     by - [ ]
    -- - [ ] by - [x]
    -- - [x] by -
    -- enter insert mode if opts.i == true
    -- if opts.v = true, then look for marks to toggle
    opts = opts or {}
    local startline = vim.api.nvim_buf_get_mark(0, "<")[1]
    local endline = vim.api.nvim_buf_get_mark(0, ">")[1]
    local cursorlinenr = vim.api.nvim_win_get_cursor(0)[1]
    -- to avoid the visual range marks not being reset when calling
    -- command from normal mode
    vim.api.nvim_buf_set_mark(0, "<", 0, 0, {})
    vim.api.nvim_buf_set_mark(0, ">", 0, 0, {})
    if startline <= 0 or endline <= 0 or opts.v ~= true then
        startline = cursorlinenr
        endline = cursorlinenr
    end
    for curlinenr = startline, endline do
        local curline =
            vim.api.nvim_buf_get_lines(0, curlinenr - 1, curlinenr, false)[1]
        local stripped = vim.trim(curline)
        local repline
        if
            vim.startswith(stripped, "- ")
            and not vim.startswith(stripped, "- [")
        then
            repline = curline:gsub("%- ", "- [ ] ", 1)
        else
            if vim.startswith(stripped, "- [ ]") then
                repline = curline:gsub("%- %[ %]", "- [x]", 1)
            else
                if vim.startswith(stripped, "- [x]") then
                    if opts.onlyTodo then
                        repline = curline:gsub("%- %[x%]", "- [ ]", 1)
                    else
                        repline = curline:gsub("%- %[x%]", "-", 1)
                    end
                else
                    repline = curline:gsub("(%S)", "- [ ] %1", 1)
                end
            end
        end
        vim.api.nvim_buf_set_lines(
            0,
            curlinenr - 1,
            curlinenr,
            false,
            { repline }
        )
        if opts.i then
            vim.api.nvim_feedkeys("A", "m", false)
        end
    end
end

--- FindAllTags(opts)
-- Needs description
-- @param opts table Options if they should differ from user's configuration
-- TODO: Add a quality description for this function
local function FindAllTags(opts)
    opts = opts or {}
    local i = opts.i
    opts.cwd = config.options.home
    opts.tag_notation = config.options.tag_notation
    local templateDir = Path:new(config.options.templates)
        :make_relative(config.options.home)
    opts.templateDir = templateDir
    opts.rg_pcre = config.options.rg_pcre

    fileutils.global_dir_check(function(dir_check)
        if not dir_check then
            return
        end

        local tag_map = tagutils.do_find_all_tags(opts)
        local taglist = {}
        local picker_actions = tkpickers.picker_actions

        local max_tag_len = 0
        for k, v in pairs(tag_map) do
            taglist[#taglist + 1] = { tag = k, details = v }
            if #k > max_tag_len then
                max_tag_len = #k
            end
        end

        if config.options.show_tags_theme == "get_cursor" then
            opts = themes.get_cursor({
                layout_config = {
                    height = math.min(math.floor(vim.o.lines * 0.8), #taglist),
                },
            })
        elseif config.options.show_tags_theme == "ivy" then
            opts = themes.get_ivy({
                layout_config = {
                    prompt_position = "top",
                    height = math.min(math.floor(vim.o.lines * 0.8), #taglist),
                },
            })
        else
            opts = themes.get_dropdown({
                layout_config = {
                    prompt_position = "top",
                    height = math.min(math.floor(vim.o.lines * 0.8), #taglist),
                },
            })
        end
        -- re-apply
        opts.cwd = config.options.home
        opts.tag_notation = config.options.tag_notation
        opts.i = i
        pickers
            .new(opts, {
                prompt_title = "Tags",
                finder = finders.new_table({
                    results = taglist,
                    entry_maker = function(entry)
                        return {
                            value = entry,
                            -- display = entry.tag .. ' \t (' .. #entry.details .. ' matches)',
                            display = string.format(
                                "%" .. max_tag_len .. "s ... (%3d matches)",
                                entry.tag,
                                #entry.details
                            ),
                            ordinal = entry.tag,
                        }
                    end,
                }),
                sorter = conf.generic_sorter(opts),
                attach_mappings = function(prompt_bufnr, map)
                    actions.select_default:replace(function()
                        -- actions for insert tag, default action: search for tag
                        local selection =
                            action_state.get_selected_entry().value.tag
                        local follow_opts = {
                            follow_tag = selection,
                            show_link_counts = false,
                            templateDir = templateDir,
                        }
                        actions._close(prompt_bufnr, false)
                        vim.schedule(function()
                            FollowLink(follow_opts)
                        end)
                    end)
                    map("i", "<c-y>", picker_actions.yank_tag(opts))
                    map("i", "<c-i>", picker_actions.paste_tag(opts))
                    map("n", "<c-y>", picker_actions.yank_tag(opts))
                    map("n", "<c-i>", picker_actions.paste_tag(opts))
                    map("n", "<c-c>", picker_actions.close(opts))
                    map("n", "<esc>", picker_actions.close(opts))
                    return true
                end,
            })
            :find()
    end)
end

--- Setup(cfg)
--- Overrides config with elements from cfg. See lua/telekasten/config.lua for defaults.
--- Maybe fold into _setup? Also used in chdir, though...
---@param cfg VaultConfig table of configuration values to override defaults
local function Setup(cfg)
    cfg = cfg or {}

    -- Setup base user configuration and apply it, use default automatically for
    -- the rest
    config.setup(cfg)

    -- Temporary shortcut to remove
    M.note_type_templates = {
        normal = config.options.template_new_note,
    }

    -- TODO: this is obsolete:
    -- But still used somehow. Maybe we could use Plenary.scan_dir?
    if vim.fn.executable("rg") == 1 then
        config.options.find_command = { "rg", "--files", "--sortr", "created" }
    else
        config.options.find_command = nil
    end

    -- this looks a little messy
    if config.options.plug_into_calendar then
        cfg.calendar_opts = cfg.calendar_opts or {}
        config.options.calendar_opts = config.options.calendar_opts or {}
        config.options.calendar_opts.weeknm = cfg.calendar_opts.weeknm
            or config.options.calendar_opts.weeknm
            or 1
        config.options.calendar_opts.calendar_monday = cfg.calendar_opts.calendar_monday
            or config.options.calendar_opts.calendar_monday
            or 1
        config.options.calendar_opts.calendar_mark = cfg.calendar_opts.calendar_mark
            or config.options.calendar_opts.calendar_mark
            or "left-fit"
        SetupCalendar(config.options.calendar_opts)
    end

    -- setup extensions to filter for
    config.options.filter_extensions = cfg.filter_extensions
        or { config.options.extension }

    -- provide fake filenames for template loading to fail silently if template is configured off
    config.options.template_new_note = config.options.template_new_note
        or "none"

    -- refresh templates
    M.note_type_templates = {
        normal = config.options.template_new_note,
    }

    -- for previewers to pick up our syntax, we need to tell plenary to override `.md` with our syntax
    if config.options.auto_set_filetype or config.options.auto_set_syntax then
        filetype.add_file("telekasten")
    end
    -- setting the syntax moved into plugin/telekasten.vim
    -- and does not work

    if config.options.take_over_my_home == true then
        if config.options.auto_set_filetype then
            vim.cmd(
                "au BufEnter "
                    .. config.options.home
                    .. "/*"
                    .. config.options.extension
                    .. " set ft=telekasten"
            )
        end
    end

    -- Convert all directories in full path
    config.options.image_subdir =
        fileutils.make_config_path_absolute(config.options.image_subdir)
    config.options.templates =
        fileutils.make_config_path_absolute(config.options.templates)

    local pcfg = config.options.periodic
    if pcfg and pcfg.kinds then
        if pcfg.root == nil or pcfg.root == "" then
            pcfg.root = config.options.home
        else
            pcfg.root = fileutils.make_config_path_absolute(pcfg.root)
        end

        for _, kcfg in pairs(pcfg.kinds) do
            if kcfg.root == nil or kcfg.root == "" then
                kcfg.root = pcfg.root
            else
                kcfg.root = fileutils.make_config_path_absolute(kcfg.root)
            end
        end
    end
    -- Check if ripgrep is compiled with --pcre
    -- ! This will need to be fixed when neovim moves to lua >=5.2 by the following:
    -- config.options.rg_pcre = os.execute("echo 'hello' | rg --pcr2 hello &> /dev/null") or false

    config.options.rg_pcre = false
    local has_pcre =
        os.execute("echo 'hello' | rg --pcre2 hello > /dev/null 2>&1")
    if has_pcre == 0 then
        config.options.rg_pcre = true
    end
    config.options.media_previewer = config.options.media_previewer
    config.options.media_extensions = config.options.media_extensions
end

--- _setup(cfg)
-- Sets the available vaults and passes further configuration options to Setup
---@param cfg MultiVaultConfig | VaultConfig table of configuration values
local function _setup(cfg)
    if cfg.vaults ~= nil and cfg.default_vault ~= nil then
        M.vaults = cfg.vaults
        cfg.vaults = nil
        Setup(M.vaults[cfg.default_vault])
    elseif cfg.vaults ~= nil and cfg.vaults["default"] ~= nil then
        M.vaults = cfg.vaults
        cfg.vaults = nil
        Setup(M.vaults["default"])
    elseif cfg.home ~= nil then
        M.vaults = cfg.vaults or {}
        cfg.vaults = nil
        ---@cast cfg VaultConfig
        M.vaults["default"] = cfg
        Setup(cfg)
    end
end

--- ChangeVault(opts)
-- Sets the vault to be used
-- @param opts table Options if they should differ from user's configuration
local function ChangeVault(opts)
    tkpickers.vaults(M, opts)
end

--- chdir(cfg)
-- Passes cfg to Setup
-- @param cfg table Table of configuration values
-- TODO: Maybe remove this function? Seems useless, just call Setup
local function chdir(cfg)
    Setup(cfg)
end

-- Telekasten command, completion
local TelekastenCmd = {
    commands = function()
        return {
            { "find notes", "find_notes", M.find_notes },
            { "find daily notes", "find_daily_notes", M.find_daily_notes },
            { "search in notes", "search_notes", M.search_notes },
            { "insert link", "insert_link", M.insert_link },
            { "follow link", "follow_link", M.follow_link },
            { "goto today", "goto_today", M.goto_today },
            { "new note", "new_note", M.new_note },
            { "goto thisweek", "goto_thisweek", M.goto_thisweek },
            { "find weekly notes", "find_weekly_notes", M.find_weekly_notes },
            { "goto thismonth", "goto_thismonth", M.goto_thismonth },
            {
                "find monthly notes",
                "find_monthly_notes",
                M.find_monthly_notes,
            },
            { "goto thisquarter", "goto_thisquarter", M.goto_thisquarter },
            {
                "find quarterly notes",
                "find_quarterly_notes",
                M.find_quarterly_notes,
            },
            { "goto thisyear", "goto_thisyear", M.goto_thisyear },
            {
                "find yearly notes",
                "find_yearly_notes",
                M.find_yearly_notes,
            },
            { "yank link to note", "yank_notelink", M.yank_notelink },
            { "rename note", "rename_note", M.rename_note },
            {
                "new templated note",
                "new_templated_note",
                M.new_templated_note,
            },
            { "show calendar", "show_calendar", M.show_calendar },
            {
                "paste image from clipboard",
                "paste_img_and_link",
                M.paste_img_and_link,
            },
            { "toggle todo", "toggle_todo", M.toggle_todo },
            { "show backlinks", "show_backlinks", M.show_backlinks },
            { "find friend notes", "find_friends", M.find_friends },
            {
                "browse images, insert link",
                "insert_img_link",
                M.insert_img_link,
            },
            { "preview image under cursor", "preview_img", M.preview_img },
            { "browse media", "browse_media", M.browse_media },
            { "panel", "panel", M.panel },
            { "show tags", "show_tags", M.show_tags },
            { "switch vault", "switch_vault", M.switch_vault },
        }
    end,
}

--- TelekastenCmd.command(subcommand)
-- Parses and runs the provided subcommand, e.g., find_notes in ':Telekasten find_notes'
-- @param subcommand string Subcommand to be run
TelekastenCmd.command = function(subcommand)
    local show = function(opts)
        opts = opts or {}
        pickers
            .new(opts, {
                prompt_title = "Command palette",
                finder = finders.new_table({
                    results = TelekastenCmd.commands(),
                    entry_maker = function(entry)
                        return {
                            value = entry,
                            display = entry[1],
                            ordinal = entry[2],
                        }
                    end,
                }),
                sorter = conf.generic_sorter(opts),
                attach_mappings = function(prompt_bufnr, _)
                    actions.select_default:replace(function()
                        -- important: actions.close(bufnr) is not enough
                        -- it resulted in: preview_img NOT receiving the prompt as default text
                        -- apparently it has sth to do with keeping insert mode
                        actions._close(prompt_bufnr, true)

                        local selection =
                            action_state.get_selected_entry().value[3]
                        selection()
                    end)
                    return true
                end,
            })
            :find()
    end
    if subcommand then
        local trimmed_subcommand = string.gsub(subcommand, "^%s*(.-)%s*$", "%1")
        for _, entry in pairs(TelekastenCmd.commands()) do
            if entry[2] == trimmed_subcommand then
                local selection = entry[3]
                selection()
                return
            end
        end
        print("No such subcommand: `" .. trimmed_subcommand .. "`")
    else
        local theme

        if config.options.command_palette_theme == "ivy" then
            theme = themes.get_ivy()
        else
            theme = themes.get_dropdown({
                layout_config = { prompt_position = "top" },
            })
        end
        show(theme)
    end
end

--- TelekastenCmd.complete()
-- nvim completion function for completing :Telekasten sub-commands
-- @return [string] List of potential completions for the subcommand
TelekastenCmd.complete = function()
    local candidates = {}
    for k, v in pairs(TelekastenCmd.commands()) do
        candidates[k] = v[2]
    end
    return candidates
end

-- Define all user facing functions
M.find_notes = FindNotes
M.find_daily_notes = FindDailyNotes
M.search_notes = SearchNotes
M.insert_link = InsertLink
M.follow_link = FollowLink
M.setup = _setup
M.goto_today = GotoToday
M.new_note = CreateNote
M.goto_thisweek = GotoThisWeek
M.find_weekly_notes = FindWeeklyNotes
M.goto_thismonth = GotoThisMonth
M.find_monthly_notes = FindMonthlyNotes
M.goto_thisquarter = GotoThisQuarter
M.find_quarterly_notes = FindQuarterlyNotes
M.goto_thisyear = GotoThisYear
M.find_yearly_notes = FindYearlyNotes
M.yank_notelink = YankLink
M.rename_note = RenameNote
M.new_templated_note = CreateNoteSelectTemplate
M.show_calendar = ShowCalendar
M.CalendarSignDay = CalendarSignDay
M.CalendarAction = CalendarAction
M.paste_img_and_link = imgFromClipboard
M.toggle_todo = ToggleTodo
M.show_backlinks = ShowBacklinks
M.find_friends = FindFriends
M.insert_img_link = InsertImgLink
M.preview_img = PreviewImg
M.browse_media = BrowseImg
M.taglinks = taglinks
M.show_tags = FindAllTags
M.switch_vault = ChangeVault
M.chdir = chdir
M.panel = TelekastenCmd.command
M.Command = TelekastenCmd

return M
