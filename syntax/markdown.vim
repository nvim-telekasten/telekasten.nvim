syntax region tkLink matchgroup=tkBrackets start=/\[\[/ end=/\]\]/ display oneline 
syntax region tkHighlight matchgroup=tkBrackets start=/==/ end=/==/ display oneline 

" just blue
"     hi tklink ctermfg=Blue cterm=bold,underline
"     hi tkBrackets ctermfg=gray


" for gruvbox
"     hi tklink ctermfg=72 cterm=bold,underline
"     hi tkBrackets ctermfg=gray

" Highlight ==highlighted== text 
"     hi tkHighlight ctermbg=yellow ctermfg=darkred cterm=bold
