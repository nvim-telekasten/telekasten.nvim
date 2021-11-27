# Backlog

- [ ] yt video

## Dones
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

