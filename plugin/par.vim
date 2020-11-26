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
"    - select the right comment:
"      stop when it finds an empty commented line, or a fold
"
"    - ignore the code above/below

" Mappings {{{1
" SPC p {{{2

nno <expr><unique> <space>p par#split_paragraph_setup()
xno <expr><unique> <space>p par#split_paragraph_setup()

" SPC C-p {{{2

nno <expr><unique> <space><c-p> par#split_paragraph_setup(v:true)
xno <expr><unique> <space><c-p> par#split_paragraph_setup(v:true)

" SPC P {{{2

nmap <unique> <space>P gqip

" gq {{{2

nno <expr><unique> gq par#gq()
xno <expr><unique> gq par#gq()

" What do you need this command for?{{{
"
" In `par#split_paragraph()`, we need to format some lines with our custom `gq`.
" We could do it with:
"
"     norm gq_
"
" However, this would have the side effect of resetting 'opfunc'.
" We would need to restore the option right after.
"
" And even then, if some day  we changed the name of `par#split_paragraph()`, we
" would need to remember to change it when we restore 'opfunc' too.
"}}}
" Do NOT give this attribute `-range=%`?{{{
"
" We need to execute `:ParGq` on some lines, each one at a time.
"
"     sil exe printf('keepj keepp %d,%dg/\S/ParGq', lnum1, line('.'))
"                                           ^
"                                           no range = current line
"}}}
com -bar -range ParGq call par#gq(<line1>, <line2>)

" gqq {{{2

nmap <unique> gqq gq_

" gqs {{{2

nno <expr><unique> gqs par#remove_duplicate_spaces() .. '_'
" }}}1
" Options {{{1
" formatprg {{{2

" `par(1)` is more powerful than Vim's internal formatting function.
" The latter has several drawbacks:
"
"    - it uses a greedy algorithm, which makes it fill a line as much as it
"      can, without caring about the discrepancies between the lengths of
"      several lines in a paragraph
"
"    - it doesn't handle well multi-line comments, (like /* */)
"
" So, when hitting `gq`, we want `par` to be invoked.

" By default, `par` reads the environment  variable `PARINIT` to set some of its
" options.  Its current value is set in `~/.shrc` like this:
"
"     rTbgqR B=.,?_A_a Q=_s>|

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
"    1. we're in normal mode, on a line longer than `&l:tw`
"    2. we switch to insert mode
"    3. we insert something at the end
"
" ... don't break the line automatically
set fo=l

"       ┌ insert comment leader after hitting o O in normal mode, from a commented line
"       │┌ same thing when we hit Enter in insert mode
"       ││
set fo+=or

"       ┌ don't break a line after a one-letter word
"       │┌ where it makes sense, remove a comment leader when joining lines
"       ││
set fo+=1jnq
"         ││
"         │└ allow formatting of comments with "gq"
"         └ when formatting text, use 'flp' to recognize numbered lists

augroup my_default_local_formatoptions | au!
    " We've configured the global value of 'fo'.
    " Do the same for its local value in ANY filetype.
    au FileType * let &l:fo = &g:fo
augroup END

