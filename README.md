# telekasten.nvim

A Neovim (lua) plugin for working with a markdown zettelkasten, based on telescope.nvim

Find notes by name, daily notes by date, search within all notes, place and follow links to your notes.  Also, creates today's daily note if not present when searching for notes. At the moment, the daily note template is hardcoded though 😁.

## Search-based navigation

Every navigation action, like following a link, is centered around a Telescope search: a Telescope search popup is opened, and in the case of following a link, the search-text is pre-filled with the target.  So, instead of opening the linked note, you get a preview in Telescope and can decide if you actually want to go there. Since the search is often likely to show up more than one result, you can preview related notes immediately. 

### The preview is a powerful feature
Leaving the opening of the note to Telescope, you can decide with one keypress whether you want to open the note in a split or in the current window - or if you've seen enough.

I find that pressing the enter key to confirm the search does not interrupt my flow, and I really enjoy being able to check the preview.  I often get enough information from the preview so I don't actually have to "visit" every note in terms of being able to edit it.

## Install and setup

**MS Windows note:** At the moment, telekasten.nvim is unlikely to be able to run on Windows, because it relies on a bash script.  Just sayin.  Since telekasten.nvim is a project that scratches my own itch, I am not sure if I will add Windows support any time soon.  Should anyone read this: Pull requests are welcome 😄!  Replacing the daily finder by a proper lua version should do the trick.

### 1. Install the plugin
Install with your plugin manager of choice.  Mine is [Vundle](https://github.com/VundleVim/Vundle.vim).

```vimscript
Plugin 'renerocksai/telekasten.nvim'
```

### 2. Configure telekasten.nvim
Somewhere in your vim config, put a snippet like this:

```vimscript
lua << END
require('telekasten').setup({
     home         = vim.fn.expand("~/zettelkasten"),
     dailies      = vim.fn.expand("~/zettelkasten/daily"),
     weeklies     = vim.fn.expand("~/zettelkasten/weekly"),
     extension    = ".md",
     daily_finder = "daily_finder.sh",
     
     -- where to install the daily_finder, 
     -- (must be a dir in your PATH)
     my_bin       = vim.fn.expand('~/bin'),   

     -- download tool for daily_finder installation: curl or wget
     downloader = 'curl',
     -- downloader = 'wget',  -- wget is supported, too

     -- following a link to a non-existing note will create it
     follow_creates_nonexisting = true,
     dailies_create_nonexisting = true,
     weeklies_create_nonexisting = true,

     -- template for new notes (new_note, follow_link)
     template_new_note = ZkCfg.home .. '/' .. 'templates/new_note.md',

     -- template for newly created daily notes (goto_today)
     template_new_daily = ZkCfg.home .. '/' .. 'templates/daily.md',

     -- template for newly created weekly notes (goto_thisweek)
     template_new_weekly= ZkCfg.home .. '/' .. 'templates/weekly.md',
})
END
```

### 3. Install the daily finder
Before using telekasten.nvim, a shell script needs to be installed.  It finds and sorts notes the way we want.  As long as I don't have a lua version for this functionality (this is literally the first time I use lua), we will have to stick with `daily_finder.sh`.

Luckily, the plugin can install the daily finder for you, directly from [GitHub](https://raw.githubusercontent.com/renerocksai/telekasten.nvim/main/ext_commands/daily_finder.sh):

```
:lua require('telekasten.nvim').install_daily_finder()
```

This will download the daily finder into the `bin/` folder of your home directory - or the directory you specified as `my_bin` in the step above.

## Use it

The plugin defines the following functions.

- `new_note` : prompts for title and creates new note by template, then shows it in Telescope
- `find_notes()` : find notes by file name (title), via Telescope
- `find_daily_notes()` : find daily notes by date (file names, sorted, most recent first), via Telescope.  If today's daily note is not present, it can be created optionally, honoring the configured template
- `goto_today()` : pops up a Telescope window with today's daily note pre-selected. Today's note can optionally be created if not present, using the configured template
- `find_weekly_notes()` : find weekly notes by week (file names, sorted, most recent first), via Telescope.  If this week's weekly note is not present, it can be created optionally, honoring the configured template
- `goto_thisweek()` : pops up a Telescope window with this week's weekly note pre-selected. This week's note can optionally be created if not present, using the configured template
- `search_notes()`: live grep for word under cursor in all notes (search in notes), via Telescope
- `insert_link()` : select a note by name, via Telescope, and place a `[[link]]` at the current cursor position
- `follow_link()`: take text between brackets (linked note) and open a Telescope file finder with it: selects note to open (incl. preview) - with optional note creation for non-existing notes, honoring the configured template
- `install_daily_finder()` : installs the daily finder tool used by the plugin
- `setup(opts)`: used for configuring paths, file extension, etc.

To use one of the functions above, just run them with the `:lua ...` command.  

```vimscript
:lua require("telekasten").find_daily_notes()
```

### Note templates

The functions `goto_today`, `goto_thisweek`, `find_daily_notes`, `find_weekly_notes`, and `follow_link` can create non-existing notes. This allows you to 'go to today' without having to create today's note beforehand. When you just type `[[some link]]` and then call `follow_link`, the 'some link' note can be generated.

The following table shows which command relies on what config option:

| telekasten function | config option | creates what |
| --- | --- | --- |
| `goto_today` | `dailies_create_nonexisting` | today's daily note |
| `find_daily_notes` | `dailies_create_nonexisting` | today's daily note |
| `goto_thisweek` | `weeklies_create_nonexisting` | this week's weekly note |
| `find_weekly_notes` | `weeklies_create_nonexisting` | this week's weekly note |
| `follow_link` | `follow_creates_nonexisting` | new note |
| `new_note` | always true | new note |

If the associated option is `true`, non-existing notes will be created.

#### Template files

The options `template_new_note`, `template_new_daily`, and `template_new_weekly` are used to specify the paths to template text files that are used for creating new notes.

Currently, the following substitutions will be made during new note creation:

| specifier in template | expands to | example |
| --- | --- | --- |
| `{{title}}` | the title of the note | My new note |
| `{{date}}` | date in iso format | 2021-11-21 |
| `{{hdate}}` | date in long format | Sunday, November 21st, 2021 |
| `{{week}}` | week of the year | 46 |
| `{{year}}` | year | 2021 |

As an example, this is my template for new notes:

```markdown
---
title: {{title}}
date:  {{date}}
---
```

And I use this one for daily notes:

```markdown
---
title: {{hdate}}
---
```

And finally, the weekly notes (that I don't use a lot):

```markdown
---
title: {{year}}-W{{week}}
date:  {{hdate}}
---

# Review Week {{week}} / {{year}}

---

## Highlights
- **this**!
- that!

## Monday link
## Tuesday link
## Wednesday link
## Thursday link
## Friday link
## Saturday link
## Sunday link
```

## Bind it 
Usually, you would set up some key bindings, though:

```vimscript
nnoremap <leader>zf :lua require('telekasten').find_notes()<CR>
nnoremap <leader>zd :lua require('telekasten').find_daily_notes()<CR>
nnoremap <leader>zg :lua require('telekasten').search_notes()<CR>
nnoremap <leader>zz :lua require('telekasten').follow_link()<CR>
nnoremap <leader>zt :lua require('telekasten').goto_today()<CR>
nnoremap <leader>zw :lua require('telekasten').find_weekly_notes()<CR>
nnoremap <leader>zn :lua require('telekasten').new_note()<CR>

" note: we define [[ in **insert mode** to call insert link
inoremap [[ <ESC>:lua require('telekasten').insert_link()<CR>
```

## The hardcoded stuff

Currently, the following things are hardcoded: 
- the file format of the daily notes: YYYY-MM-DD.md


Finding and sorting notes is contained in the `daily_finder.sh` script - which you can edit to your liking. I recommend making a copy, though. Otherwise your changes get lost with every plugin update. Don't forget to set `daily_finder = "my_edited_daily_finder.sh"` in the `setup()`, provided you named your  copy `my_edited_daily_finder.sh`.






