<div align="center">

# ![](img/telekasten-logo-gray-270x87.png).nvim

[![Lua](https://img.shields.io/badge/Lua-blue.svg?style=plastic&logo=lua)](http://www.lua.org)
[![Neovim](https://img.shields.io/badge/Neovim%200.6+-green.svg?style=plastic&logo=neovim)](https://neovim.io)

</div>

A Neovim (lua) plugin for working with a text-based, markdown
[zettelkasten](https://takesmartnotes.com/) / wiki and mixing it with a journal,
based on [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim).

#### Highlights

- Find notes by name, #tag or by searching within note text
- Find daily, weekly notes by date
- **Vaults**: Support for multiple separate note collections
- Place and follow links to your notes or create new ones, with templates
- Find notes that link back to your notes
- Find other notes that link to the same note as the link under the cursor
- Support for links to headings or specific paragraphs within specific notes or
  globally
- Alias link names to keep everything clean and tidy
- Toggle [ ] todo status
- Paste images from clipboard
- Insert links to images
- Image previews, via `catimg`, `viu`, or extension
- Calendar support

---

## Search-based navigation

Every navigation action, like following a link, is centered around a Telescope
picker. You can then decide to actually open the note or just read the content
from the picker itself. Thanks to [Telescope actions](#picker-actions) you can
also just insert a link to the note or yank a link instead of opening the note.

<!-- FIXME: Make a GIF instead of lots of images-->

![image](https://user-images.githubusercontent.com/30892199/145457184-758ae6cd-f1d2-48b4-b09b-4fa7e45c493f.png)

---

![](img/2021-12-03_13-21.png)

---
![image](https://user-images.githubusercontent.com/30892199/145457923-d3e3a20b-9a33-42d1-aa21-3de6b2295737.png)

---

![](img/tags-linkcounts.png)


## Contents

<!-- FIXME -->
- [Requirements](#requirements)
- [Getting started](#getting-started)
  - [Installation](#installation)
  - [Base setup](#base-setup)
  - [Suggested dependencies](#suggested-dependencies)
- [Usage](#usage)
  - [Commands](#commands)
  - [Command palette](#command-palette)
- [Customization](#customization)
  - [Highlights](#highlights)
  - [Mappings](#mappings)
- [Features](#features)
  - [Link notation](#link-notation)
  - [Tag notation](#tag-notation)
  - [Templates](#templates)
  - [Picker actions](#picker-actions)
  - [Calendar](#calendar)
- [Hard-coded stuff](#hard-coded-stuff)

## Requirements
Telekasten requires Neovim v0.6.0 or higher. Besides that, its only mandatory
dependency of is
[telescope.nvim](https://github.com/nvim-telescope/telescope.nvim), which acts
as the backbone of this plugin.

Some features require external tools. For example, image pasting from the
clipboard require a compatible clipboard manager such as `xclip` or
`wl-clipboard`. Users are encouraged to read the requirements section of the
documentation for a complete list of optional dependencies (`:h
telekasten.requirements`).

## Getting started

### Installation

<details>
<summary>Packer.nvim</summary>

```lua
  use {
    'renerocksai/telekasten.nvim',
    requires = {'nvim-telescope/telescope.nvim'}
  }
```

</details>

<details>
<summary>Lazy.nvim</summary>

```lua
  {
    'renerocksai/telekasten.nvim',
    dependencies = {'nvim-telescope/telescope.nvim'}
  },
```

</details>


<details>
<summary>Vim-plug</summary>

```vim
  Plug 'nvim-telescope/telescope.nvim'
  Plug 'renerocksai/telekasten.nvim'
```

</details>

<details>
<summary>Vundle</summary>

```vim
  Plugin 'nvim-telescope/telescope.nvim'
  Plugin 'renerocksai/telekasten.nvim'
```

</details>


### Base setup
In order to use Telekasten, you need to first require its setup function
somewhere in your `init.lua`. Take this opportunity to indicate the path for
your notes directory. If you do not specify anything, the plugin will ask you to
create the defaults directories before first use.

```lua
require('telekasten').setup({
  home = vim.fn.expand("~/zettelkasten"), -- Put the name of your notes directory here
})
```
**NOTE:** For Windows users, please indicate the path as
`C:/Users/username/zettelkasten/`. See `:h telekasten.windows` for more details
about the specificities for Windows.

### Suggested dependencies

#### Calendar
Telekasten interacts very nicely with
[calendar-vim](https://github.com/renerocksai/calendar-vim). Installing this
plugin will allow you to create journal entries for the selected dates and
highlight dates with attached entries.

#### Image preview
Various plugins or external tools can be used as image previewers to help you
pick the correct illustrations for your note.
- [telescope-media-files.nvim](https://github.com/nvim-telescope/telescope-media-files.nvim)
- [catimg](https://github.com/posva/catimg)
- [viu](https://github.com/atanunq/viu)

#### Image pasting
- [xclip](https://github.com/astrand/xclip)
- [wl-clipboard](https://github.com/bugaevc/wl-clipboard)

_Image pasting is supported by default on MacOS, it is not necessary to install
any other tool._


#### Other useful resources/plugins

While they do not interact directly with Telekasten, the following plugins
greatly improve the note-taking experience.

- [telescope-bibtex.nvim](https://github.com/nvim-telescope/telescope-bibtex.nvim):
  manage citations using bibtex
- [telescope-symbols.nvim](https://github.com/nvim-telescope/telescope-symbols.nvim):
  telescope picker for symbols and emojis
- [peek.nvim](https://github.com/toppair/peek.nvim) or
  [markdown-preview.nvim](https://github.com/iamcco/markdown-preview.nvim):
  markdown previewer
- [vim-markdown-toc](https://github.com/mzlogin/vim-markdown-toc):
  generate a table of contents for your markdown documents
- [synctodo](https://github.com/cnshsliu/synctodo): bash script to sync todos
  among Telekasten, Mac and iPhone reminders.


## Usage

The simplest way to use the plugin is to call directly the related Telekasten
command:
```vim
:Telekasten <sub-command>
```
<details>
<summary>Advanced use</summary>
Each sub-command is implemented by a specific lua function. While high-level
Telekasten commands can not accept arguments, you can also call directly the lua
function with additional arguments. This is especially useful to craft some
custom mappings.

```vim
:lua require('telekasten').search_notes()
```

See the [wiki](https://github.com/renerocksai/telekasten.nvim/wiki/Mappings#advanced-key-mappings) for more details regarding advanced usage.
</details>

### Commands

The following sub-commands are defined:

- `panel` : brings up the [command palette](command-palette)
- `find_notes` : Find notes by title (filename)
- `show_tags` : brings up the tag list. From there you can select a tag to search for tagged notes - or yank or insert the tag
- `find_daily_notes` : Find daily notes by title (date)
- `search_notes` : Search (grep) in all notes
- `insert_link` : Insert a link to a note
- `follow_link` : Follow the link under the cursor
- `goto_today` : Open today's daily note
- `new_note` : Create a new note, prompts for title
- `goto_thisweek` : Open this week's weekly note
- `find_weekly_notes` : Find weekly notes by title (calendar week)
- `yank_notelink` : Yank a link to the currently open note
- `new_templated_note` : create a new note by template, prompts for title and template
- `show_calendar` : Show the calendar
- `paste_img_and_link` : Paste an image from the clipboard into a file and inserts a link to it
- `toggle_todo` : Toggle `- [ ]` todo status of a line
- `show_backlinks` : Show all notes linking to the current one
- `find_friends` : Show all notes linking to the link under the cursor
- `insert_img_link` : Browse images / media files and insert a link to the selected one
- `preview_img` : preview image under the cursor
- `browse_media` : Browse images / media files
- `rename_note` : Rename current note and update the links pointing to it
- `switch_vault` : switch the vault. Brings up a picker. See the `vaults` config
  option for more.


###  Command palette

Telekasten comes with a small helper command palette that let the user browse
the different commands available. This feature is quite similar to the excellent
[which-key.nvim](https://github.com/folke/which-key.nvim) plugin, although
limited to Telekasten.

You can call this panel using
```vim
:Telekasten panel
```
This can be especially useful if all your Telekasten mappings start with the
same prefix. In that case, bind the command panel to the prefix only and it will
pop-up when you hesitate to complete the mapping.


## Customization

### Highlights

Telekasten.nvim allows you to color your `[[links]]` and `#tags` by providing
the following syntax groups:

- `tkLink` : the link title inside the brackets
- `tkBrackets` : the brackets surrounding the link title
- `tkHighlight` : ==highlighted== text (non-standard markdown)
- `tkTag` :  well, tags

An additional `CalNavi` group is defined to tweak the appearance of the calendar
navigation button.


```vim
" Example
hi tkLink ctermfg=Blue cterm=bold,underline guifg=blue gui=bold,underline
hi tkBrackets ctermfg=gray guifg=gray
```

### Mappings

The real power of Telekasten lays in defining sensible mappings to make your
workflow even smoother. A good idea is to take advantage of the [command
palette][#command-palette] and start all your mappings with the same prefix
(`<leader>z`, for `Z`ettelkasten for instance).


```lua
-- Launch panel if nothing is typed after <leader>z
vim.keymap.set("n", "<leader>z", "<cmd>Telekasten panel<CR>")

-- Most used functions
vim.keymap.set("n", "<leader>zf", "<cmd>Telekasten find_notes<CR>")
vim.keymap.set("n", "<leader>zg", "<cmd>Telekasten search_notes<CR>")
vim.keymap.set("n", "<leader>zd", "<cmd>Telekasten goto_today<CR>")
vim.keymap.set("n", "<leader>zz", "<cmd>Telekasten follow_link<CR>")
vim.keymap.set("n", "<leader>zn", "<cmd>Telekasten new_note<CR>")
vim.keymap.set("n", "<leader>zc", "<cmd>Telekasten show_calendar<CR>")
vim.keymap.set("n", "<leader>zb", "<cmd>Telekasten show_backlinks<CR>")
vim.keymap.set("n", "<leader>zI", "<cmd>Telekasten insert_img_link<CR>")

-- Call insert link automatically when we start typing a link
vim.keymap.set("i", "[[", "<cmd>Telekasten insert_link<CR>")

```


#### Advanced mappings
Each Telekasten command is bound to a specific lua function. As lua functions
can accept arguments, it is possible to craft special mappings to tailor the
execution of a function to your specific need.

See the [wiki](https://github.com/renerocksai/telekasten.nvim/wiki/Mappings#advanced-key-mappings) for more details regarding advanced key mappings.


## Features

### Vaults
Telekasten allows the user to have completely separated note collections and
switch between them easily. Simply add data to the `vaults` table in the
    configuration and configure each vault as you wish.

### Link notation

The following links are supported:

```markdown
# Note links
- [[A cool title]]  ................. links to the note named 'A cool title'
- [[A cool title#Heading 27]]  ...... links to the heading 'Heading 27' within the note
                                      named 'A cool title'
- [[A cool title#^xxxxxxxx]]  ....... links to the paragraph with id ^xxxxxxxx within the note
                                      named 'A cool title'
- [[201705061300|A cool title]] ..... links to the note named `201705061300` but shows the link as
                                      `A cool title` if `conceallevel=2`
- [[#Heading 27]]  .................. links to the heading 'Heading 27' within all notes
- [[#^xxxxxxxx]]  ................... links to the paragraph with id ^xxxxxxxx within all notes

## Optionally, notes can live in specific sub-directories
- [[some/subdirectory/A cool title]]
- [[some/subdirectory/A cool title#Heading 27]]
- [[some/subdirectory/A cool title#^xxxxxxxx]]


# Media links
Use these for images, PDF files, videos. If telescope-media-files is installed,
these can be previewed.
- ![optional title](path/to/file) ... links to the file `path/to/file`
```

See the documentation for more details regarding the different types of links
(`:h telekasten.link_notation`).


### Tag notation

Telekasten supports the following tag notations:

1. `#tag`
2. `@tag`
3. `:tag:`
4. `yaml-bare`: bare tags in a tag collection in the yaml metadata:


See the documentation for more details regarding the tag syntax (`:h
telekasten.tag_notation`).

### Templates

To streamline your workflow, it is possible to create various note templates and
call them upon note creation. These templates will substitute various terms
(date, times, file names, UUID, etc).

A simple template can be:

```markdown
---
uuid: {{uuid}}
date:  {{date}}
---

# {{shorttitle}}

```

A complete list of substitutions can be found in the documentation (`:h
telekasten.template_files`).

### Picker actions

When you are prompted with a telescope picker to select a note or media file,
the following mappings apply:

- <kbd>CTRL</kbd> + <kbd>i</kbd> : inserts a link to the selected note / image
  - the option `insert_after_inserting` defines if insert mode will be entered
    after the link is pasted into your current buffer
- <kbd>CTRL</kbd> + <kbd>y</kbd> : yanks a link to the selected note / image,
  ready for <kbd>p</kbd>asting
  - the option `close_after_yanking` defines whether the telescope window should
    be closed when the link has been yanked
- <kbd>RETURN / ENTER</kbd> : usually opens the selected note or performs the
  action defined by the called function
  - e.g. `insert_img_link()`'s action is to insert a link to the selected image.

### Calendar

When invoking `show_calendar()`, a calendar showing the previous, current, and
next month is shown at the right side of vim.

- days that have a daily note associated with them are marked with a + sign and
  a different color
- pressing enter on a day will open up a telescope finder with the associated
  daily note selected and previewed. The daily note will be created if it
  doesn't exist. If you choose to not open the note, you will return to the
  calender so you can preview other notes.

If you want to see a big calendar showing the current month that fills your
entire window, you can issue the following command in vim:

```vim
:CalendarT
```

## Hard-coded stuff

Some (minor) stuff are currently still hard-coded. We will eventually change
this to allow more flexibility at one point.

Currently, the following things are hardcoded:

- the file naming format for daily note files: `YYYY-MM-DD.ext` (e.g.
  `2021-11-21.md`)
- the file naming format for weekly note files: `YYYY-Www.ext` (e.g.
  `2021-W46.md`)
- the file naming format for pasted images: `pasted_img_YYYYMMDDhhmmss.png`
  (e.g. `pasted_img_20211126041108.png`)

---
_The Telekasten logo is based on the neovim logo attributed to Jason Long, neovim,
[CC-BY-3.0](https://commons.wikimedia.org/wiki/Category:CC-BY-3.0)._
