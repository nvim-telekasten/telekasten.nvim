-- The configuration setup is inspire from akinsho/bufferline.nvim
--
local vim = vim

local M = {}

---The local class instance of the merged user's configuration this includes all
---default values and highlights filled out
local config = {}

---The class definition for the user configuration
local Config = {}

function Config:new(opts)
    local o = { options = opts }
    assert(o, "User options must be passed in")
    self.__index = self
    -- save a copy of the user's preferences so we can reference exactly what they
    -- wanted after the config and defaults have been merged. Do this using a copy
    -- so that reference isn't unintentionally mutated
    self.user = vim.deepcopy(o)
    setmetatable(o, self)
    return o
end

---Combine user preferences with defaults preferring the user's own settings
function Config:merge(defaults)
    assert(
        defaults and type(defaults) == "table",
        "A valid config table must be passed to merge"
    )
    self.options =
        vim.tbl_deep_extend("force", defaults.options, self.options or {})
    return self
end

--
-- Default setup. Ideally anyone should be able to start using Telekasten
-- directly without fiddling too much with the options. The only one of real
-- interest should be the path for the few relevant directories.
local function get_defaults(home)
    local _home = home or vim.fn.expand("~/zettelkasten") -- Default home directory
    local opts = {
        home = _home,
        take_over_my_home = true,
        auto_set_filetype = true,
        auto_set_syntax = true,
        dailies = _home,
        weeklies = _home,
        templates = _home,
        image_subdir = nil, -- Should be deprecated gracefully and replaced by "images"
        extension = ".md",
        new_note_filename = "title",
        uuid_type = "%Y%m%d%H%M",
        uuid_sep = "-",
        filename_space_subst = nil,
        follow_creates_nonexisting = true,
        dailies_create_nonexisting = true,
        weeklies_create_nonexisting = true,
        journal_auto_open = false,
        image_link_style = "markdown",
        sort = "filename",
        subdirs_in_links = true,
        plug_into_calendar = true,
        calendar_opts = {
            weeknm = 4,
            calendar_monday = 1,
            calendar_mark = "left-fit",
        },
        close_after_yanking = false,
        insert_after_inserting = true,
        tag_notation = "#tag",
        command_palette_theme = "ivy",
        show_tags_theme = "ivy",
        template_handling = "smart",
        new_note_location = "smart",
        rename_update_links = true,
        media_previewer = "telescope-media-files",
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
    }
    return { options = opts }
end

--- Merge user config with defaults
function M.apply()
    local defaults = get_defaults(config.options.home)
    config:merge(defaults)
    return config
end

---Keep track of a users config for use throughout the plugin as well as
---ensuring defaults are set.
function M.setup(c)
    config = Config:new(c or {})
    M.apply()
end

---Get the user's configuration or a key from it
function M.get()
    if config then
        return config
    end
end

---Print the user config
function M.debug()
    print("User config in its current state:")
    print("---------------------------------")
    print(vim.inspect(config.options))
end

if _G.__TEST then
    function M.__reset()
        config = nil
    end
end

return setmetatable(M, {
    __index = function(_, k)
        return config[k]
    end,
})
