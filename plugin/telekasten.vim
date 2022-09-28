if exists('g:loaded_telekasten')
    finish
endif
let g:loaded_telekasten = 1

function! s:telekasten_complete(arg,line,pos)
    let l:candidates = luaeval('require("telekasten").Command.complete()')
  return join(l:candidates, "\n")
endfunction

command! -nargs=? -range -complete=custom,s:telekasten_complete Telekasten lua require('telekasten').panel(<f-args>)

" overriding does not work -- so this is done by the plugin now in post_open()
" au BufNewFile,BufRead *.markdown,*.mdown,*.mkd,*.mkdn,*.mdwn,*.md  setf telekasten
" autocmd filetype markdown set syntax=telekasten
