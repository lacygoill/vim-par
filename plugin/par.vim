if exists('g:loaded_par')
    finish
endif
let g:loaded_par = 1

" TODO:
" Should we try to merge `par#gq()` and `par#split_paragraph()`?
" Also, shouldn't we rename the plugin `vim-format`?

" TODO:
" Make `SPC p` smarter.
" When we press it while on some comment, it should:
"
"     • select the right comment:
"       stop when it finds an empty commented line, or a fold
"
"     • ignore the code above/below

" Mappings {{{1
" SPC p {{{2

nno <silent><unique>  <space>p  :<c-u>call par#split_paragraph_save_param('n', 0)<bar>set opfunc=par#split_paragraph<cr>g@_
xno <silent><unique>  <space>p  :<c-u>call par#split_paragraph_save_param('x', 0)<bar>set opfunc=par#split_paragraph<cr>g@_
" SPC C-p {{{2

nno <silent><unique>  <space><c-p>  :<c-u>call par#split_paragraph_save_param('n', 1)<bar>set opfunc=par#split_paragraph<cr>g@_
xno <silent><unique>  <space><c-p>  :<c-u>call par#split_paragraph_save_param('x', 1)<bar>set opfunc=par#split_paragraph<cr>g@_

" SPC P {{{2

nmap <unique>  <space>P  gqip

" gq {{{2

nno  <silent><unique>  gq  :<c-u>set opfunc=par#gq<cr>g@
xno  <silent><unique>  gq  :<c-u>call par#gq('x')<cr>

" gqq {{{2

nmap <silent><unique>  gqq  gq_

" gqs {{{2

nno  <silent><unique>  gqs  :<c-u>set opfunc=par#remove_duplicate_spaces<cr>g@_

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

