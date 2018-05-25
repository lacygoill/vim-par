if exists('g:loaded_par')
    finish
endif
let g:loaded_par = 1

" TODO:
" Try to merge `par#gq()` and `par#split_paragraph()`.
" Also, shouldn't we rename the plugin `vim-format`?

" TODO:
" I'm not sure our mappings handle comments with 2 parts (html, c) that well.

" TODO:
" Make `SPC p` smarter.
" When we press it while on some comment, it should:
"
"     • select the right comment
"       stop when it finds an empty commented line, or a fold
"
"     • ignore the code above/below
"
"     • handle correctly diagrams

" Mappings {{{1
" SPC p {{{2

nmap <unique>  <space>p                 <plug>(split-paragraph)
nno  <silent>  <plug>(split-paragraph)  :<c-u>call par#split_paragraph('n')<cr>

xno <silent><unique>  <space>p  :<c-u>call par#split_paragraph('x')<cr>

" SPC C-p {{{2

nmap <unique>  <space><c-p>                              <plug>(split-paragraph-with-empty-lines)
nno  <silent>  <plug>(split-paragraph-with-empty-lines)  :<c-u>call par#split_paragraph('n', 'with-empty-lines')<cr>

xno <silent><unique>  <space><c-p>  :<c-u>call par#split_paragraph('x', 'with-empty-lines')<cr>

" SPC P {{{2

nmap <unique>  <space>P  gqip

" gq {{{2

nno  <silent><unique>  gq  :<c-u>set opfunc=par#gq<cr>g@
xno  <silent><unique>  gq  :<c-u>call par#gq('x')<cr>

" gqq {{{2

nmap <silent><unique>  gqq  gq_

" gqs {{{2

" remove excessive spaces
nno  <silent><unique>  gqs  :<c-u>s/\s\{2,}/ /gc <bar> sil! call repeat#set('gqs')<cr>

" Options {{{1
" formatprg {{{2

" `$ par` is more powerful than Vim's internal formatting function.
" The latter has several drawbacks:
"
"     • it uses a greedy algorithm, which makes it fill a line as much as it
"       can, without caring about the discrepancies between the lengths of
"       several lines in a paragraph
"
"     • it doesn't handle well multi-line comments, (like /* */)
"
" So, when hitting `gq`, we want `par` to be invoked.

" By default, `par` reads the environment  variable `PARINIT` to set some of its
" options.  Its current value is set in `~/.shrc` like this:
"
"         rTbgqR B=.,?_A_a Q=_s>|

"            ┌ no line bigger than 80 characters in the output paragraph{{{
"            │
"            │  ┌ fill empty comment lines with spaces (e.g.: /*    */)
"            │  │
"            │  │┌ justify the output so that all lines (except the last)
"            │  ││ have the same length, by inserting spaces between words
"            │  ││
"            │  ││┌ delete (expel) superfluous lines from the output
"            │  │││
"            │  │││┌ handle nested quotations, often found in the
"            │  ││││ plain text version of an email}}}
set fp=par\ -w80rjeq

" formatoptions {{{2

" 'formatoptions' / 'fo' handles the automatic formatting of text.
"
" I  don't   use  them,  but  the   `c`  and  `t`  flags   control  whether  Vim
" auto-wrap  Comments (using  textwidth,  inserting the  current comment  leader
" automatically), and Text (using textwidth).

" If:
"     1. we're in normal mode, on a line longer than `&l:tw`
"     2. we switch to insert mode
"     3. we insert something at the end
"
" ... don't break the line automatically
set fo=l

"       ┌─ insert comment leader after hitting o O in normal mode, from a commented line
"       │┌─ same thing when we hit Enter in insert mode
"       ││
set fo+=or

"       ┌─ don't break a line after a one-letter word
"       │┌─ where it makes sense, remove a comment leader when joining lines
"       ││
set fo+=1jnq
"         ││
"         │└─ allow formatting of comments with "gq"
"         └─ when formatting text, use 'flp' to recognize numbered lists

augroup my_default_local_formatoptions
    au!
    " We've configured the global value of 'fo'.
    " Do the same for its local value in ANY filetype.
    au FileType * let &l:fo = &g:fo
augroup END

