@{task_master}
let's add another task for snacks validation, and a couple human validation sub tasks based on our current state, currently telekasten panel opens but displays nothing, that should be a task, telekasten new note creates a new note in our dir, but gives the following error when trying to open the picker 
`Error executing vim.schedule lua callback: ...a/Local/nvim-data/lazy/snacks.nvim/lua/snacks/layout.lua:111: no root box found
stack traceback:
        [C]: in function 'assert'
        ...a/Local/nvim-data/lazy/snacks.nvim/lua/snacks/layout.lua:111: in function 'new'
        ...-data/lazy/snacks.nvim/lua/snacks/picker/core/picker.lua:234: in function 'init_layout'
        ...-data/lazy/snacks.nvim/lua/snacks/picker/core/picker.lua:130: in function 'find_and_open'
        ...mcraf/Github-Projects/telekasten.nvim/lua/telekasten.lua:1853: in function 'open_picker'
        ...mcraf/Github-Projects/telekasten.nvim/lua/telekasten.lua:1893: in function 'on_create'
        ...mcraf/Github-Projects/telekasten.nvim/lua/telekasten.lua:1909: in function 'callback'
        ...-Projects/telekasten.nvim/lua/telekasten/utils/files.lua:61: in function 'on_confirm'
        ...ta/Local/nvim-data/lazy/snacks.nvim/lua/snacks/input.lua:134: in function <...ta/Local/nvim-data/lazy/snacks.nvim/lua/snacks/input.lua:127>
Press ENTER or type command to continue`

I believe this has something to do with setting the layout/themes in the snacks.lua file, and overwriting the config set by the picker on setup in the snacks.nvim plugin. the advised fix is to pass the actual opts that make up the layout, seen below.
```
9. Layouts                                        *snacks.nvim-picker-layouts*


BOTTOM                                     *snacks.nvim-picker-layouts-bottom*

>lua
    { preset = "ivy", layout = { position = "bottom" } }
<


DEFAULT                                   *snacks.nvim-picker-layouts-default*

>lua
    {
      layout = {
        box = "horizontal",
        width = 0.8,
        min_width = 120,
        height = 0.8,
        {
          box = "vertical",
          border = true,
          title = "{title} {live} {flags}",
          { win = "input", height = 1, border = "bottom" },
          { win = "list", border = "none" },
        },
        { win = "preview", title = "{preview}", border = true, width = 0.5 },
      },
    }
<


DROPDOWN                                 *snacks.nvim-picker-layouts-dropdown*

>lua
    {
      layout = {
        backdrop = false,
        row = 1,
        width = 0.4,
        min_width = 80,
        height = 0.8,
        border = "none",
        box = "vertical",
        { win = "preview", title = "{preview}", height = 0.4, border = true },
        {
          box = "vertical",
          border = true,
          title = "{title} {live} {flags}",
          title_pos = "center",
          { win = "input", height = 1, border = "bottom" },
          { win = "list", border = "none" },
        },
      },
    }
<


IVY                                           *snacks.nvim-picker-layouts-ivy*

>lua
    {
      layout = {
        box = "vertical",
        backdrop = false,
        row = -1,
        width = 0,
        height = 0.4,
        border = "top",
        title = " {title} {live} {flags}",
        title_pos = "left",
        { win = "input", height = 1, border = "bottom" },
        {
          box = "horizontal",
          { win = "list", border = "none" },
          { win = "preview", title = "{preview}", width = 0.6, border = "left" },
        },
      },
    }
<


IVY_SPLIT                               *snacks.nvim-picker-layouts-ivy_split*

>lua
    {
      preview = "main",
      layout = {
        box = "vertical",
        backdrop = false,
        width = 0,
        height = 0.4,
        position = "bottom",
        border = "top",
        title = " {title} {live} {flags}",
        title_pos = "left",
        { win = "input", height = 1, border = "bottom" },
        {
          box = "horizontal",
          { win = "list", border = "none" },
          { win = "preview", title = "{preview}", width = 0.6, border = "left" },
        },
      },
    }
<


LEFT                                         *snacks.nvim-picker-layouts-left*

>lua
    M.sidebar
<


RIGHT                                       *snacks.nvim-picker-layouts-right*

>lua
    { preset = "sidebar", layout = { position = "right" } }
<


SELECT                                     *snacks.nvim-picker-layouts-select*

>lua
    {
      hidden = { "preview" },
      layout = {
        backdrop = false,
        width = 0.5,
        min_width = 80,
        height = 0.4,
        min_height = 3,
        box = "vertical",
        border = true,
        title = "{title}",
        title_pos = "center",
        { win = "input", height = 1, border = "bottom" },
        { win = "list", border = "none" },
        { win = "preview", title = "{preview}", height = 0.4, border = "top" },
      },
    }
<


SIDEBAR                                   *snacks.nvim-picker-layouts-sidebar*

>lua
    {
      preview = "main",
      layout = {
        backdrop = false,
        width = 40,
        min_width = 40,
        height = 0,
        position = "left",
        border = "none",
        box = "vertical",
        {
          win = "input",
          height = 1,
          border = true,
          title = "{title} {live} {flags}",
          title_pos = "center",
        },
        { win = "list", border = "none" },
        { win = "preview", title = "{preview}", height = 0.4, border = "top" },
      },
    }
<


TELESCOPE                               *snacks.nvim-picker-layouts-telescope*

>lua
    {
      reverse = true,
      layout = {
        box = "horizontal",
        backdrop = false,
        width = 0.8,
        height = 0.9,
        border = "none",
        {
          box = "vertical",
          { win = "list", title = " Results ", title_pos = "center", border = true },
          { win = "input", height = 1, border = true, title = "{title} {live} {flags}", title_pos = "center" },
        },
        {
          win = "preview",
          title = "{preview:Preview}",
          width = 0.45,
          border = true,
          title_pos = "center",
        },
      },
    }
<


TOP                                           *snacks.nvim-picker-layouts-top*

>lua
    { preset = "ivy", layout = { position = "top" } }
<


VERTICAL                                 *snacks.nvim-picker-layouts-vertical*

>lua
    {
      layout = {
        backdrop = false,
        width = 0.5,
        min_width = 80,
        height = 0.8,
        min_height = 30,
        box = "vertical",
        border = true,
        title = "{title} {live} {flags}",
        title_pos = "center",
        { win = "input", height = 1, border = "bottom" },
        { win = "list", border = "none" },
        { win = "preview", title = "{preview}", height = 0.4, border = "top" },
      },
    }
<


VSCODE                                     *snacks.nvim-picker-layouts-vscode*

>lua
    {
      hidden = { "preview" },
      layout = {
        backdrop = false,
        row = 1,
        width = 0.4,
        min_width = 80,
        height = 0.4,
        border = "none",
        box = "vertical",
        { win = "input", height = 1, border = true, title = "{title} {live} {flags}", title_pos = "center" },
        { win = "list", border = "hpad" },
        { win = "preview", title = "{preview}", border = true },
      },
    }
<
```
