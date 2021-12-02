# Backlog

- [ ] awesome split: some cool buffer showing backlinks (and stuff?)
    - maybe another one where we dot-render a graph of linked notes and 
      display it via vimg from telescope_media_files or sth similar
    - these buffers / this buffer should keep its size even when resizing other
      splits (like the calendar)
- [ ] really good support for special links: inserting, yanking, ...

- [ ] maybe generate bibliography inline, citekey and bibfile support
- [ ] yt video

## Dones
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

# Awesome Split

`toggle_awesome_split()`

Maybe even some commands, like:
- <i> note info       -- silly highlights:</i>
- <t> list tags
- <T> find tags
- <f> find citekeys
- <f> list citekeys
- <f> find notes containing

Telescope action that pastes results to awesome split?

Reason for find tags and citekeys is that a bunch of results can come back which we want to have available for
copy/pasting. Maybe the same is useful for notes: all notes containing "rene":

Saved Searches: show recent notes blah

Demo: (set nowrap)

```markdown
# Title
The title

# Tags
 #asdfsadf

# Links 
 [[asfdasdfsdf]]
 [[asfdasdfsdf]]
 [[asfdasdfsdf]]
 [[asfdasdfsdf]]

# Back-links 
 [[asfdasdfsdf]]
 [[asfdasdfsdf]]

# citekeys

# also citing (back-cites)

```


```vim
  "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  "+++ build window
  "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  " make window
  let vwinnum = bufnr('__Calendar')
  if getbufvar(vwinnum, 'Calendar') == 'Calendar'
    let vwinnum = bufwinnr(vwinnum)
  else
    let vwinnum = -1
  endif

  if vwinnum >= 0
    " if already exist
    if vwinnum != bufwinnr('%')
      exe vwinnum . 'wincmd w'
    endif
    setlocal modifiable
    " delete everything
    silent %d _
  else
    " make title
    if g:calendar_datetime == "title" && (!exists('s:bufautocommandsset'))
      auto BufEnter *Calendar let b:sav_titlestring = &titlestring | let &titlestring = '%{strftime("%c")}'
      auto BufLeave *Calendar if exists('b:sav_titlestring') | let &titlestring = b:sav_titlestring | endif
      let s:bufautocommandsset = 1
    endif

    if exists('g:calendar_navi') && dir
      if g:calendar_navi == 'both'
        let vheight = vheight + 4
      else
        let vheight = vheight + 2
      endif
    endif

    " or not
    if dir == 1
      " window at bottom
      silent execute 'bo '.vheight.'split __Calendar'
      setlocal winfixheight
    elseif dir == 0
      " window at top
      silent execute 'to '.vcolumn.'vsplit __Calendar'
      setlocal winfixwidth
    elseif dir == 3
      silent execute 'bo '.vcolumn.'vsplit __Calendar'
      setlocal winfixwidth
    elseif bufname('%') == '' && &l:modified == 0
      silent execute 'edit __Calendar'
    else
      silent execute 'tabnew __Calendar'
    endif
    call s:CalendarBuildKeymap(dir, vyear, vmnth)
    setlocal noswapfile
    setlocal buftype=nofile
    setlocal bufhidden=delete
    silent! exe "setlocal " . g:calendar_options
    let nontext_columns = &foldcolumn + &nu * &numberwidth
    if has("+relativenumber")
      let nontext_columns += &rnu * &numberwidth
    endif
    " Without this, the 'sidescrolloff' setting may cause the left side of the
    " calendar to disappear if the last inserted element is near the right
    " window border.
    setlocal nowrap
    setlocal norightleft
    setlocal modifiable
    setlocal nolist
    let b:Calendar = 'Calendar'
    setlocal filetype=calendar
    " is this a vertical (0) or a horizontal (1) split?
    if dir != 2
      exe vcolumn + nontext_columns . "wincmd |"
    endif
  endif
  if g:calendar_datetime == "statusline"
    setlocal statusline=%{strftime('%c')}
  endif
  let b:CalendarDir = dir
  let b:CalendarYear = vyear_org
  let b:CalendarMonth = vmnth_org

  " navi
  if exists('g:calendar_navi')
    let navi_label = '<'
        \.get(split(g:calendar_navi_label, ','), 0, '').' '
        \.get(split(g:calendar_navi_label, ','), 1, '').' '
        \.get(split(g:calendar_navi_label, ','), 2, '').'>'
    if dir == 1
      let navcol = vcolumn + (vcolumn-strlen(navi_label)+2)/2
    elseif (dir == 0 ||dir == 3)
      let navcol = (vcolumn-strlen(navi_label)+2)/2
    else
      let navcol = (width - strlen(navi_label)) / 2
    endif
    if navcol < 3
      let navcol = 3
    endif

    if g:calendar_navi == 'top'
      execute "normal gg".navcol."i "
      silent exec "normal! a".navi_label."\<cr>\<cr>"
      silent put! =vdisplay1
    endif
    if g:calendar_navi == 'bottom'
      silent put! =vdisplay1
      silent exec "normal! Gi\<cr>"
      execute "normal ".navcol."i "
      silent exec "normal! a".navi_label
    endif
    if g:calendar_navi == 'both'
      execute "normal gg".navcol."i "
      silent exec "normal! a".navi_label."\<cr>\<cr>"
      silent put! =vdisplay1
      silent exec "normal! Gi\<cr>"
      execute "normal ".navcol."i "
      silent exec "normal! a".navi_label
    endif
  else
    silent put! =vdisplay1
  endif

  setlocal nomodifiable
  " In case we've gotten here from insert mode (via <C-O>:Calendar<CR>)...
  stopinsert
```
