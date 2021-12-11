# Backlog

- [ ] maybe a virtual line in the 1st line that shows number of backlinks and maybe other interesting stuff
    - or put it as an extmark at the end of the first line, meh.
- [ ] some cool buffer showing backlinks (and stuff?) [see also this comment](https://github.com/renerocksai/telekasten.nvim/discussions/23#discussioncomment-1754511)
    - maybe another one where we dot-render a graph of linked notes and 
      display it via vimg from telescope_media_files or sth similar
    - these buffers / this buffer should keep its size even when resizing other
      splits (like the calendar)
- [ ] really good support for special links: inserting, yanking, ...
- [ ] lsp support, lsp completion of everything: notes, headings, paragraphs, tags, ...

- [ ] yt video

## Dones
- [x] better support for #tags [see also this comment](https://github.com/renerocksai/telekasten.nvim/discussions/23#discussioncomment-1754511)
    - at least we have a tag picker now
- [x] follow external URLs
- [x] telekasten filetype
- [x] Telekasten command with completion, command palette
- [x] follow #tags
- [x] syntax for tags, incl. plenary filetype
    - for proper display, needed to define 'telekasten' syntax
- [x] browse_media()
- [x] action mappings for notes: yanking and link inserting
- [x] document and suggest colors for Calendar nav buttons, they look weird in gruvbox
- [x] initial support for special links
  - links to headings
  - links to paragraphs
- [x] preview images
- [x] insert link to image, with preview
- [x] sorting file picker: devicons, ...
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

Everything behind a # is a search!

- [[#some heading]] -- will search for the heading 'some heading' 

- [[some note#some heading]] -- will search for 'some note' in filns and within it the heading 'some heading' 

- [[#^some-para-id]] -- will search for the ^para-id
- [[some note#^some-para-id]] -- will search for the ^para-id in the note whose filn matches some note

If note is specified and cannot be found, it will be ignored and a global search triggered instead

## Supportive features

- Yank link to heading
- Yank link to paragraph

### Insert links...?
Maybe as an extra action: link with heading -> telescope popup for headings
Maybe as an extra action: link with paragraph -> telescope popup for paragraphs

Global: link to heading: search through all headings
Global: link to paragraphs: search all paragraphs: maybe overkill
Global: link to already postfixed paragraphs
Global: Place paragraph id

