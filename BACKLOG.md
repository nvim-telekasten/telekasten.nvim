# Backlog

- [ ] really good support for special links
  - links to headings
  - links to paragraphs
- can  we add image pre-viewing capabilities from `telescope-media-files` to the standard previewer or a self-written
  pre-viewer (config)?

- [ ] yt video

## Dones
- [x] dailies and weeklies: don't display whole paths: fix entries: display values
- [x] added option parameter `i` to `toggle_todo(opts)` and `insert_link(opts)` to enter insert mode.
- [x] find_friends()
- [x] show_backlinks() : issue #3
- [x] replaced `vim.ui.input` by `vim.fn.input`, as the former was causing problems on nvim 0.5.x
  - might not report on all closed issues here in the future as they are available in the issue tracker anyway
- [x] bugfixed and PRed calendar-vim: passing proper `week`(day) param from :CalendarT
- [x] toggle todo
- [x]: (silly idea) check if we can paste imgs into nvim
  - not so silly: with xclip, it's possible!
- [x] implement sorting of the file list that works as well as the `daily_finder.sh` we abandoned
    - `plenary.scan_dir()` to the rescue!
- [x] vimhelp
- [x] Honor day, month, year etc when creating a note via calendar!
- [x] awesome calendar support
- [x] maybe choose template in create note:
    - `new_templated_note()` first asks for title, then brings up a telescope picker of all template files in new `ZkCfg.template_dir`.
- [x] highlights oneline
- [x] highlight for highlighted text : ==asdfasdfasasdf==
- [x] yank notelink
- [x] extend markdown syntax highlights for [[links]]
- [x] avoid creating new note in home dir when following link to daily or weekly
- [x] get rid of `daily_finder.sh`
- [x] find weekly note
- [x] goto week
- [x] create note, use default template
- [x] follow links: create non-existing ones 
- [x] ,[ to insert link --> we can escape out and type double brackets
- [x] shortcuts for todo and done in init.vim
- [x] Readme search based navigation


## Special links

- like this
   - [[2021-11-27#Make it]]
   - [[2021-11-27# it]]
   - [[2021-11-27#^4ba88c]]
     - block references only need to be local to the file
     - for grepping, it makes sense for them to rather not collide
     - we could use hex format of current time when creating them
     - or some hash of the block - plus some time info

- also provide highlighting 
- yank link to this heading
- yank link to this paragraph
  - warning: appends ^xxxxxx to the paragraph, if not present

- can we jump to a specific line (col) from telescope?
- how can we jump to the heading / para in the preview?
- can we use live_grep or file_finder?
  - con for live_grep: will find any file with the same heading
    - --> pressing enter might jump to a wrong default
  - con for file finder:
    - maybe not possible to move preview to correct line
      - better previewer?
- or shall everything be custom?
  - only 1 file or a list of files containing the same heading, with the one under the link as default
  - and a pre-viewer at correct line (cat new or so)

`require('telescope.previewers').vim_buffer_vimgrep()`:
A previewer that is used to display a file and jump to the provided line.
It uses the `buffer_previewer` interface. To integrate this one into your
own picker make sure that the field `path` or `filename` and `lnum` is set
in each entry. If the latter is not present, it will default to the first
line. The preferred way of using this previewer is like this
`require('telescope.config').values.grep_previewer` This will respect user
configuration and will use `termopen_previewer` in case it's configured
that way.

Also interesting: termopen_previewer!
`vim.fn.search` to jump to a specific line

> Start typing a link like you would normally. When the note you want is highlighted, press # instead of Enter and you'll see a list of headings in that file. Continue typing or navigate with arrow keys as before, press # again at each subheading you want to add, and Enter to complete the link.

