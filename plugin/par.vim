if exists('g:loaded_par')
    finish
endif
let g:loaded_par = 1

" FIXME:
" When we press `SPC p` on a commented paragraph, sometimes, the lines after the
" first one are not commented anymore.

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

" TODO:
" I'm not sure our mappings handle diagrams that well.
" In particular when there're several diagram characters on a single line.

" Mappings {{{1
" SPC p {{{2

nmap <unique>  <space>p                         <plug>(split-paragraph-compact)
nno  <silent>  <plug>(split-paragraph-compact)  :<c-u>call par#split_paragraph(1, 'n')<cr>

xmap <silent><unique>  <space>p  :<c-u>call par#split_paragraph(1, 'x')<cr>

" SPC C-p {{{2

nmap <unique>  <space><c-p>             <plug>(split-paragraph)
nno  <silent>  <plug>(split-paragraph)  :<c-u>call par#split_paragraph(0, 'n')<cr>

xmap <silent><unique>  <space><c-p>  :<c-u>call par#split_paragraph(0, 'x')<cr>

" SPC P {{{2

"                                                      ┌─ don't write:
"                                                      │
"                                                      │      'sil norm <plug>(my_gq)ip'
"                                                      │
"                                                      │  because `:norm` needs `\<plug>`
"                                                      │
nno  <silent><unique>  <space>P  mz:<c-u>exe "sil norm \<plug>(my_gq)ip"
                                 \ <bar> sil update
                                 \ <bar> sil! norm! `z<cr>

" gq {{{2

" Purpose:{{{
"
" The default `gq` invokes `par` which doesn't recognize bullet lists.
" OTOH, `gw` recognizes them thanks to 'flp'.
" We create a wrapper around `gq`, which checks whether the 1st line of the text
" object has a list header.
" If it does, the wrapper should execute `gw`, otherwise `gq`.
"}}}
" Why do you create `<plug>` mappings?{{{
"
" We have 2 mappings which currently invoke the default `gq`:
"
"         • gqq
"         • <space>p
"
" We want them to invoke our custom wrapper, and `<plug>` mappings are easier to use.
"}}}
nmap  <unique>  gq             <plug>(my_gq)
nno   <silent>  <plug>(my_gq)  :<c-u>set opfunc=par#gq<cr>g@

xmap  <unique>  gq             <plug>(my_gq)
xno   <silent>  <plug>(my_gq)  :<c-u>call par#gq('vis')<cr>

" gqq {{{2

" Purpose:{{{
"
" When we hit `gqq`  on a commented line, and `par` breaks the  line in 2 lines,
" the 2nd line is not commented.
" We want it to be commented, and `par` to be reinvoked on the 2 lines.
"}}}
nmap <unique>  gqq              <plug>(my_gqq)
nno  <silent>  <plug>(my_gqq)  :<c-u>call par#gqq()<cr>

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

