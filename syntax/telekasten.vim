" not sure if we really want this:
if exists("b:current_syntax")
  finish
endif

runtime! syntax/markdown.vim
unlet b:current_syntax

syn region Comment matchgroup=Comment start="<!--" end="-->"  contains=tkTag keepend

syntax region tkLink matchgroup=tkBrackets start=/\[\[/ end=/\]\]/ keepend display oneline contains=tkAliasedLink
syntax match tkAliasedLink "[^\[\]]\+|" contained conceal

syntax region tkHighlight matchgroup=tkBrackets start=/==/ end=/==/ display oneline contains=tkHighlightedAliasedLink

syntax match tkTag "\v#[a-zA-ZÀ-ÿ]+[a-zA-ZÀ-ÿ0-9/\-_]*"
syntax match tkTag "\v:[a-zA-ZÀ-ÿ]+[a-zA-ZÀ-ÿ0-9/\-_]*:"

syntax match tkTagSep "\v\s*,\s*" contained
syntax region tkTag matchgroup=tkBrackets start=/^tags\s*:\s*\[\s*/ end=/\s*\]\s*$/ contains=tkTagSep display oneline


let b:current_syntax = 'telekasten'

" " just blue
"     hi tkLink ctermfg=Blue cterm=bold,underline
"     hi tkBrackets ctermfg=gray

" " for gruvbox
"     hi tkLink ctermfg=72 cterm=bold,underline
"     hi tkBrackets ctermfg=gray

" " Highlight ==highlighted== text
"     hi tkHighlight ctermbg=yellow ctermfg=darkred cterm=bold

"
" " Tags
"     hi tkTagSep ctermfg=gray
"     hi tkTag ctermfg=magenta