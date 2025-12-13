-- declare locals for the nvim api stuff to avoid more lsp warnings
local vim = vim
local _home = vim.fn.expand("~/zettelkasten")
local M = {}

-- ----------------------------------------------------------------------------
-- DEFAULT CONFIG
-- ----------------------------------------------------------------------------
function M.defaultConfig(home)
    if home == nil then
        home = _home
    end

    local cfg = {
        home = home,
        -- if true, telekasten will be enabled when opening a note within the configured home
        take_over_my_home = true,
        -- auto-set telekasten filetype: if false, the telekasten filetype will not be used
        --                               and thus the telekasten syntax will not be loaded either
        auto_set_filetype = true,
        -- auto-set telekasten syntax: if false, the telekasten syntax will not be set
        -- this syntax setting is independent from auto-set filetype
        auto_set_syntax = true,
        -- dir names for special notes (absolute path or subdir name)
        dailies = home,
        weeklies = home,
        monthlies = home,
        quarterlies = home,
        yearlies = home,
        templates = home,
        -- image (sub)dir for pasting
        -- dir name (absolute path or subdir name)
        -- or nil if pasted images shouldn't go into a special subdir
        image_subdir = nil,
        -- markdown file extension
        extension = ".md",
        -- Generate note filenames. One of:
        -- "title" (default) - Use title if supplied, uuid otherwise
        -- "uuid" - Use uuid
        -- "uuid-title" - Prefix title by uuid
        -- "title-uuid" - Suffix title with uuid
        new_note_filename = "title",
        --[[ file UUID type
           - "rand"
           - string input for os.date()
           - or custom lua function that returns a string
        --]]
        uuid_type = "%Y%m%d%H%M",
        -- UUID separator
        uuid_sep = "-",
        -- if not nil, replaces any spaces in the title when it is used in filename generation
        filename_space_subst = nil,
        -- if true, make the filename lowercase
        filename_small_case = false,
        -- following a link to a non-existing note will create it
        follow_creates_nonexisting = true,
        dailies_create_nonexisting = true,
        weeklies_create_nonexisting = true,
        monthlies_create_nonexisting = true,
        quarterlies_create_nonexisting = true,
        yearlies_create_nonexisting = true,
        -- allow following links to files outside the current vault (absolute paths)
        external_link_follow = true,
        -- skip telescope prompt for goto_today and goto_thisweek
        journal_auto_open = false,
        -- templates for new notes
        -- template_new_note = home .. "/" .. "templates/new_note.md",
        -- template_new_daily = home .. "/" .. "templates/daily_tk.md",
        -- template_new_weekly = home .. "/" .. "templates/weekly_tk.md",
        -- template_new_monthly = home .. "/" .. "templates/monthly_tk.md",
        -- template_new_quarterly = home .. "/" .. "templates/quarterly_tk.md"
        -- template_new_yearly = home .. "/" .. "templates/yearly_tk.md"

        -- image link style
        -- wiki:     ![[image name]]
        -- markdown: ![](image_subdir/xxxxx.png)
        image_link_style = "markdown",
        -- default sort option: 'filename', 'modified'
        sort = "filename",
        -- when linking to a note in subdir/, create a [[subdir/title]] link
        -- instead of a [[title only]] link
        subdirs_in_links = true,
        -- integrate with calendar-vim
        plug_into_calendar = true,
        calendar_opts = {
            -- calendar week display mode: 1 .. 'WK01', 2 .. 'WK 1', 3 .. 'KW01', 4 .. 'KW 1', 5 .. '1'
            weeknm = 4,
            -- use monday as first day of week: 1 .. true, 0 .. false
            calendar_monday = 1,
            -- calendar mark: where to put mark for marked days: 'left', 'right', 'left-fit'
            calendar_mark = "left-fit",
        },
        close_after_yanking = false,
        insert_after_inserting = true,
        -- tag notation: '#tag', ':tag:', 'yaml-bare'
        tag_notation = "#tag",
        -- command palette theme: dropdown (window) or ivy (bottom panel)
        command_palette_theme = "ivy",
        -- tag list theme:
        -- get_cursor: small tag list at cursor; ivy and dropdown like above
        show_tags_theme = "ivy",
        -- template_handling
        -- What to do when creating a new note via `new_note()` or `follow_link()`
        -- to a non-existing note
        -- - prefer_new_note: use `new_note` template
        -- - smart: if day or week is detected in title, use daily / weekly templates (default)
        -- - always_ask: always ask before creating a note
        template_handling = "smart",
        -- path handling:
        --   this applies to:
        --     - new_note()
        --     - new_templated_note()
        --     - follow_link() to non-existing note
        --
        --   it does NOT apply to:
        --     - goto_today()
        --     - goto_thisweek()
        --
        --   Valid options:
        --     - smart: put daily-looking notes in daily, weekly-looking ones in weekly,
        --              all other ones in home, except for notes/with/subdirs/in/title.
        --              (default)
        --
        --     - prefer_home: put all notes in home except for goto_today(), goto_thisweek()
        --                    except for notes/with/subdirs/in/title.
        --
        --     - same_as_current: put all new notes in the dir of the current note if
        --                        present or else in home
        --                        except for notes/with/subdirs/in/title.
        new_note_location = "smart",
        -- should all links be updated when a file is renamed
        rename_update_links = true,
        -- how to preview media files
        -- "telescope-media-files" if you have telescope-media-files.nvim installed
        -- "catimg-previewer" if you have catimg installed
        -- "viu-previewer" if you have viu installed
        media_previewer = "telescope-media-files",
        -- files which will be available in insert and preview images list
        media_extensions = {
            ".png",
            ".jpg",
            ".bmp",
            ".gif",
            ".pdf",
            ".mp4",
            ".webm",
            ".webp",
        },
        -- A customizable fallback handler for urls.
        follow_url_fallback = nil,
        -- Enable creation new notes with Ctrl-n when finding notes
        enable_create_new = true,

        -- Specify a clipboard program to use
        clipboard_program = "", -- xsel, xclip, wl-paste, osascript
        -- Keybinds for inside the picker
        keybinds = {
            picker = {
                yank_link    = "<c-y>",
                paste_link   = "<c-i>",
                i_yank_link  = "<c-y>",
                i_paste_link = "<c-i>",
                close        = { "<ESC>", "<C-c>" },
            },
        }
    }

    return cfg
end
return M
