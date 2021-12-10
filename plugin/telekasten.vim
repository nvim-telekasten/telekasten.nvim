if exists('g:loaded_telekasten')
    finish
endif
let g:loaded_telekasten = 1

function! s:telekasten_complete(arg,line,pos)
    let l:candidates = luaeval('require("telekasten").Command.complete()')
  return join(l:candidates, "\n")
endfunction

command! -nargs=? -complete=custom,s:telekasten_complete Telekasten lua require('telekasten').panel(<f-args>)
