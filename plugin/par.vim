"                                              ┌─ don't write:
"                                              │
"                                              │      'sil norm <plug>(my_gq)ip'
"                                              │
"                                              │  because `:nno` doesn't translate `<plug>`.
"                                              │
nno  <silent>  <space>P  mz:<c-u>exe "sil norm \<plug>(my_gq)ip"
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
nmap            gq             <plug>(my_gq)
nno   <silent>  <plug>(my_gq)  :<c-u>set opfunc=<sid>my_gq<cr>g@

xmap            gq             <plug>(my_gq)
xno   <silent>  <plug>(my_gq)  :<c-u>call <sid>my_gq('vis')<cr>

fu! s:my_gq(type) abort
    let ai_save = &l:ai
    try
        " 'ai' needs to be set so that `gw` can properly indent the formatted lines.
        setl ai

        let [ lnum1, lnum2 ] = a:type is# 'vis'
                           \ ?     [ line("'<"), line("'>") ]
                           \ :     [ line("'["), line("']") ]

        let cml = get(split(&l:cms, '%s'), 0, '')
        let cml = '\%(\V'.escape(cml, '\').'\m\)\?'
        let has_a_list_header = getline(lnum1) =~# &l:flp
        let has_diagram = getline(lnum1) =~# '^\s*'.cml.'\s*[│┌]'

        if has_a_list_header
            sil exe 'norm! '.lnum1.'Ggw'.lnum2.'G'

        elseif has_diagram

            sil exe printf('keepj keepp %d,%ds/[┌┐└┘]/\="│ ".%s[submatch(0)]/e', lnum1, lnum2,
            \ {'┌': "\<c-a>", '┐': "\<c-b>", '└': "\<c-c>", '┘': "\<c-d>"})
            " FIXME:
            " What if `&fp` has changed?
            " Read `vim-toggle-settings`. Look for `s:formatprg(`.
            " I don't understand this function anymore, nor the `coq` mapping.
            "
            " Anyway, we may need to save the  initial global value of 'fp' in a
            " global variable.
            sil exe printf('%s!%s', lnum1.','.lnum2, &fp)
            " Why?{{{
            "
            " `gq` could have increased the number of lines, or reduced it.
            " There's no  guarantee that  `lnum2` still matches  the end  of the
            " original text.
            "}}}
            let lnum2 = line("']")
            sil exe printf('keepj keepp %d,%ds/│ \([\x01\x02\x03\x04]\)/\=%s[submatch(1)]/e', lnum1, lnum2,
            \ {"\<c-a>": '┌', "\<c-b>": '┐', "\<c-c>": '└', "\<c-d>": '┘'})

        else
            sil exe 'norm! '.lnum1.'Ggq'.lnum2.'G'
        endif
    catch
        return lg#catch_error()
    finally
        let &l:ai = ai_save
        " For some reason, if we're editing a help file, and use `gq`, Vim makes
        " the buffer noreadonly back.
        " MWE:
        "     :h
        "     coH
        "     :norm! gqq
        if &ft is# 'help' && &l:ro
            setl noro
        endif
    endtry
endfu





" When we hit `gqq`  on a commented line, and `par` breaks the  line in 2 lines,
" the 2nd  line is not commented. We  want it to  be commented, and `par`  to be
" reinvoked on the 2 lines.

nmap           gqq              <plug>(my_gqq)
nno  <silent>  <plug>(my_gqq)  :<c-u>call <sid>gqq()<cr>

fu! s:gqq() abort
    norm! mz

    let was_commented = !empty(&l:cms)
    \                   ?    stridx(getline('.'), split(&l:cms, '%s')[0]) !=# -1
    \                   :    0
    let orig = line('.')

    " format current line
    exe "sil norm \<plug>(my_gq)_"

    " if the line was commented, and has been split into several new lines (i.e.
    " the current line address has changed)
    if was_commented && line('.') !=# orig
        let range = orig+1.','.line('.')
        " then comment the lines between the new lines
        exe range.'CommentToggle'
        " and format them
        exe "sil norm \<plug>(my_gq)".(line('.')-orig).'k'
    endif

    sil! norm! `z
    sil! call repeat#set("\<plug>(my_gqq)", v:count1)
endfu





nmap           <space>p                         <plug>(split-paragraph-compact)
nno  <silent>  <plug>(split-paragraph-compact)  :<c-u>call <sid>split_paragraph(1, 'n')<cr>

nmap           <space><c-p>             <plug>(split-paragraph)
nno  <silent>  <plug>(split-paragraph)  :<c-u>call <sid>split_paragraph(0, 'n')<cr>

xmap <silent>  <space>p      :<c-u>call <sid>split_paragraph(1, 'x')<cr>
xmap <silent>  <space><c-p>  :<c-u>call <sid>split_paragraph(0, 'x')<cr>

fu! s:split_paragraph(compact, mode) abort
    let [firstline, lastline] = a:mode is# 'n'
    \ ?     [line("'{"), line("'}")]
    \ :     [line("'<"), line("'>")]

    " get the address of the last line of the paragraph/selection
    if a:mode is# 'n' && getline(lastline) =~# '^\s*$'
        let lnum2 = lastline - 1
    else
        let lnum2 = lastline
    endif

    " get the address of the first line
    let lnum1 = firstline ==# 1 && getline(1) =~# '\S'
    \ ?             1
    \ :             firstline + 1

    if getline(lnum1) =~# &l:flp && a:mode is# 'n'
        return feedkeys("\<plug>(my_gq)ip", 'i')
    endif

    let pos = getcurpos()

    " The last character of the paragraph needs to be a valid punctuation ending
    " for a sentence. Otherwise, our function could wrongly delete some lines.
    if getline(lnum2) =~# '\s*[^.!?:]$'
        echo 'last char is not a valid punctuation ending for a sentence'
        return
    endif

    try
        " Replace soft hyphens which we sometimes copy from a pdf.
        " They are annoying because they mess up the display of nearby characters.
        sil exe 'keepj keepp '.lnum1.','.lnum2.'s/\%u00ad/-/ge'

        " In a markdown file, we could have a leading `>` in front of quoted lines.
        " The next `:j` won't remove them. We need to do it manually, and keep only
        " the first one.
        sil exe 'keepj '.(lnum1+(lnum1 < lnum2 ? 1 : 0)).','.lnum2.'s/^>//e'

        " Replace every hyphen used at the end of  a line to break a word on two
        " lines, with a ‘C-a’.
        " Why?{{{
        "
        " Because we don't want them. So, we mark them now, to remove them later.
        "}}}
        " Ok, but why don't you remove them right now?{{{
        "
        " Because it could alter the range (more specifically, it could reduce `lnum2`).
        " This would cause the next `:j` to join too many lines.
        "}}}
        sil exe 'keepj keepp '.lnum1.','.lnum2.'s/[\u2010-]\ze\n\s*\S\+/'."\<c-a>".'/ge'
        " join all the lines in a single one
        sil exe 'keepj '.lnum1.','.lnum2.'j'
        " Now that we've joined all the lines, remove every ‘C-a’.
        sil exe "keepj keepp s/\<c-a>\\s*//ge"

        " break the line down according to the punctuation
        let pat = '\C[.!?]\zs\%(\s\+[.a-z]\@!\|$\)\|:\zs\s*$'
        "                            ││
        "                            │└ don't break something like`i.e.`
        "                            │
        "                            └ don't break something like `...`
        " Why [.a-z]\@! instead of \u (uppercase character)?{{{
        "
        " A sentence doesn't always begin with an uppercase character.
        " For example, it may begin with a quote.
        "}}}
        let indent = matchstr(getline(lnum1), '^\s*')
        sil exe printf('keepj keepp s/%s/\=%s/ge', pat, string("\n\n".indent))

        " 2 empty lines have been added (one where we are right now, and the one above);
        " remove them
        " Why using a global command?{{{
        "
        " To be sure we're deleting empty lines.
        "}}}
        sil keepj keepp -,g/^\s*$/d_

        " format with `$ par`
        sil exe printf('keepj keepp %d,%dg/\S/norm gqq', lnum1, line('.'))

        " remove empty lines
        if a:compact
            sil exe printf('keepj keepp %d,%dg/^$/d_', lnum1, line('.'))
        endif

        sil update

        call setpos('.', pos)

        " make the mapping repeatable
        if a:mode is# 'n'
            sil! call repeat#set("\<plug>(split-paragraph".(a:compact ? '-compact)' : ')'))
        endif
    catch
        return lg#catch_error()
    endtry
endfu







nmap            gqic                       <plug>(my_format_comment)
nno   <silent>  <plug>(my_format_comment)  :<c-u>call <sid>format_comment()<cr>

fu! s:format_comment() abort
    let cur_line = line('.')
    norm! mz
    " select the current comment
    call comment#object(1, '\|[┘└┐┌│─]\|^\s*"\s*\S\+:')
    "                         │         │
    "                         │         └─ and ignore a title (vimCommentTitle)
    "                         └─ but ignore lines in a diagram
    " TODO:
    " This is an ugly hack.
    " It's not needed anymore.
    "
    " Look  at how  we dealt  with lines  containing multibyte  characters (such
    " as│), in `s:my_gq()`.
    "
    " Hint: in  the configuration  of `$  par`, we (ab)use  the notion  of quote
    " characters.
    "
    " Once you've removed this hack.
    " Simplify  the  code in  `vim-comment`,  by  removing the  second  optional
    " argument passed to `comment#object()`.

    exe "norm! \e"
    "           │
    "           └─ the '< '> marks are not set until we get back to normal mode

    " format the comment
    if line("'<") ==# line("'>") || cur_line < line("'<") || cur_line > line("'>")
        return
    else
        exe "norm gv\<plug>(my_gq)"
    endif

    sil! norm! `z
    sil! call repeat#set("\<plug>(my_format_comment)", v:count1)
endfu




nmap  Q  gq




" remove excessive spaces
nno  <silent>  gqs  :<c-u>s/\s\{2,}/ /gc<cr>



" 'fo' {{{1 
"
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
"                   │  ││││
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


" 'formatoptions' / 'fo' handles the automatic formatting of text.
"
" I  don't   use  them,  but  the   `c`  and  `t`  flags   control  whether  Vim
" auto-wrap  Comments (using  textwidth,  inserting the  current comment  leader
" automatically), and Text (using textwidth).


" if:
"     1. we're in normal mode, on a line longer than `&l:tw`
"     2. we switch to insert mode
"     3. we insert something at the end
"
" … don't break the line automatically
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




" TODO:
"
" Merge `s:my_gq()` with `s:split_paragraph()`.
" Why?
" Because `s:split_paragraph()` correctly deals with hyphens.
" Not `s:my_gq()`. Not consistent.
"
