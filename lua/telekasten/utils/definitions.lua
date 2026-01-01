--luacheck: ignore 211
---@meta

---@alias MediaExtensions
---| '".png"'
---| '".jpg"'
---| '".bmp"'
---| '".gif"'
---| '".pdf"'
---| '".mp4"'
---| '".webm"'
---| '".webp"'

---@alias PeriodicKind
---| '"daily"'
---| '"weekly"'
---| '"monthly"'
---| '"quarterly"'
---| '"yearly"'

---@class PeriodicKindConfig
---@field enabled boolean
---@field root string|nil
---@field folder_path string
---@field filename string
---@field template_file string|nil
---@field create_if_missing boolean

---@class PeriodicConfig
---@field root string
---@field kinds table<PeriodicKind, PeriodicKindConfig>
---
---@class PickerKeybinds
---@field yank_link string
---@field paste_link string
---@field i_yank_link string
---@field i_paste_link string
---@field close string

---@class Keybinds
---@field picker PickerKeybinds

---@class VaultConfig
---@field home string
---@field take_over_my_home boolean
---@field auto_set_filetype boolean
---@field auto_set_syntax boolean
---@field periodic PeriodicConfig
---@field templates string
---@field image_subdir string|nil Should be deprecated gracefully and replaced by "images"
---@field extension "md" | string
---@field new_note_filename "title" | "uuid" | "uuid-title"
---@field uuid_type "%Y%m%d%H%M" | string
---@field uuid_sep "-" | string
---@field filename_space_subst string|nil
---@field follow_creates_nonexisting boolean
---@field external_link_follow boolean
---@field journal_auto_open boolean
---@field image_link_style "wiki" | "markdown"
---@field sort "filename" | "modified"
---@field subdirs_in_links boolean
---@field plug_into_calendar boolean
---@field calendar_opts CalendarOpts
---@field close_after_yanking boolean
---@field insert_after_inserting boolean
---@field tag_notation "#tag" | "@tag" | ":tag:" | "yaml-bare"
---@field command_palette_theme "dropdown" | "ivy"
---@field show_tags_theme string
---@field template_handling "smart" | "prefer_new_note" | "always_ask"
---@field new_note_location "smart" |"prefer_home" |  "same_as_current"
---@field rename_update_links boolean
---@field media_previewer "telescope-media-files" | "catimg-previewer" | "viu-previewer"
---@field media_extensions MediaExtensions[]
---@field follow_url_fallback string|nil
---@field enable_create_new boolean
---@field clipboard_program string
---@field filter_extensions string[]
---@field template_new_note string|nil
---@field keybinds Keybinds
---@field find_command string[]
---@field rg_pcre boolean
---
---For defaults,
---@see Config.get_defaults
local VaultConfig = {}

---@alias WeekNumberFormat
---| 1 # WK01
---| 2 # WK 1
---| 3 # KW01
---| 4 # KW 1
---| 5 # 1

---@alias CalendarStartDay
---| 0 # weeks start on Sundays
---| 1 # weeks start on Mondays

---@alias CalendarMarkPosition
---| 'left'     # ugly
---| 'right'    # right to the day
---| 'left-fit' # left of the day

---@class CalendarOpts
---@field weeknm WeekNumberFormat
---@field calendar_monday CalendarStartDay
---@field calendar_mark CalendarMarkPosition
local CalendarOpts = {}

---@class MultiVaultConfig
---@field vaults table<string, VaultConfig>
---@field default_vault? string
local MultiVaultConfig = {}
