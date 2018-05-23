fu! par#format_comment() abort "{{{1
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
    " as│), in `par#gq()`.
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


fu! par#gq(type) abort "{{{1
    let ai_save = &l:ai
    try
        " 'ai' needs to be set so that `gw` can properly indent the formatted lines.
        setl ai

        let [lnum1, lnum2] = a:type is# 'vis'
                         \ ?     [line("'<"), line("'>")]
                         \ :     [line("'["), line("']")]

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
        " Why?{{{
        "
        " For some reason, if we're editing a help file, and use `gq`, Vim makes
        " the buffer noreadonly back.
        " MWE:
        "     :h
        "     coH
        "     :norm! gqq
        "}}}
        if &ft is# 'help' && &l:ro
            setl noro
        endif
    endtry
endfu

fu! par#gqq() abort "{{{1
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

fu! par#split_paragraph(compact, mode) abort "{{{1
    let [firstline, lastline] = a:mode is# 'n'
    \ ?     [line("'{"), line("'}")]
    \ :     [line("'<"), line("'>")]

    " get the address of the first line
    let lnum1 = firstline ==# 1 && getline(1) =~# '\S'
    \ ?             1
    \ :             firstline + 1

    " get the address of the last line of the paragraph/selection
    let lnum2 = a:mode is# 'n' && getline(lastline) =~# '^\s*$'
    \ ?             lastline - 1
    \ :             lastline

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

