if exists('g:loaded_par')
    finish
endif
let g:loaded_par = 1

" FIXME:
" When we press `SPC p` on a  commented paragraph, the lines after the first one
" are not commented anymore.

" TODO:
"
" Merge `par#gq()` with `par#split_paragraph()`.
" Why?
" Because `par#split_paragraph()` correctly deals with hyphens.
" Not `par#gq()`. Not consistent.

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

"                                                      ┌─ don't write:
"                                                      │
"                                                      │      'sil norm <plug>(my_gq)ip'
"                                                      │
"                                                      │  because `:nno` doesn't translate `<plug>`.
"                                                      │
nno  <silent><unique>  <space>P  mz:<c-u>exe "sil norm \<plug>(my_gq)ip"
                                 \ <bar> sil update
                                 \ <bar> sil! norm! `z<cr>

" The default `gq` invokes `par` which doesn't recognize bullet lists.
" OTOH, `gw` recognizes them thanks to 'flp'.
" We create a wrapper around `gq`, which checks whether the 1st line of the text
" object  has a  list  header. If  it does,  the  wrapper  should execute  `gw`,
" otherwise `gq`.

" Why do we create `<plug>` mappings?{{{
"
" We have 3 mappings which currently invoke the default `gq`:
"
"         • gqic
"         • gqq
"         • <space>p
"
" We want them to invoke our custom wrapper, and `<plug>` mappings are easier to use.
"}}}
nmap  <unique>  gq             <plug>(my_gq)
nno   <silent>  <plug>(my_gq)  :<c-u>set opfunc=par#gq<cr>g@

xmap  <unique>  gq             <plug>(my_gq)
xno   <silent>  <plug>(my_gq)  :<c-u>call par#gq('vis')<cr>

" When we hit `gqq`  on a commented line, and `par` breaks the  line in 2 lines,
" the 2nd  line is not commented. We  want it to  be commented, and `par`  to be
" reinvoked on the 2 lines.

nmap <unique>  gqq              <plug>(my_gqq)
nno  <silent>  <plug>(my_gqq)  :<c-u>call par#gqq()<cr>

nmap <unique>  <space>p                         <plug>(split-paragraph-compact)
nno  <silent>  <plug>(split-paragraph-compact)  :<c-u>call par#split_paragraph(1, 'n')<cr>

nmap <unique>  <space><c-p>             <plug>(split-paragraph)
nno  <silent>  <plug>(split-paragraph)  :<c-u>call par#split_paragraph(0, 'n')<cr>

xmap <silent><unique>  <space>p      :<c-u>call par#split_paragraph(1, 'x')<cr>
xmap <silent><unique>  <space><c-p>  :<c-u>call par#split_paragraph(0, 'x')<cr>

" remove excessive spaces
nno  <silent><unique>  gqs  :<c-u>s/\s\{2,}/ /gc<cr>

" Options {{{1

" `par` is an external formatting program, more powerful than Vim's internal
" formatting function. The latter has several drawbacks:
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

set formatprg=par\ -w80rjeq
"                   │  ││││{{{
"                   │  │││└── handle nested quotations, often found in the
"                   │  │││    plain text version of an email
"                   │  │││
"                   │  ││└── delete (expel) superfluous lines from the output
"                   │  ││
"                   │  │└── justify the output so that all lines (except the last)
"                   │  │    have the same length, by inserting spaces between words
"                   │  │
"                   │  └── fill empty comment lines with spaces (e.g.: /*    */)
"                   │
"                   └── no line bigger than 80 characters in the output paragraph
"}}}

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

