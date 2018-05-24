" Interface {{{1
fu! par#gq(type) abort "{{{2
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

        " If 'fp' doesn't invoke `$ par`, but something else like `$ js-beautify`,
        " we should let the external program do its job without interfering.
        if &l:fp !~# '^par\s'
            sil exe 'norm! '.lnum1.'Ggq'.lnum2.'G'

        elseif has_a_list_header
            sil exe 'norm! '.lnum1.'Ggw'.lnum2.'G'

        elseif has_diagram
            " temporarily replace diagram characters with control characters
            sil exe printf('keepj keepp %d,%ds/[┌┐└┘]/\="│ ".%s[submatch(0)]/e', lnum1, lnum2,
            \ {'┌': "\x01", '┐': "\x02", '└': "\x03", '┘': "\x04"})

            " format the lines
            sil exe 'norm! '.lnum1.'Ggq'.lnum2.'G'

            " Why?{{{
            "
            " `gq` could have increased the number of lines, or reduced it.
            " There's no  guarantee that  `lnum2` still matches  the end  of the
            " original text.
            "}}}
            let lnum2 = line("']")
            " restore diagram characters
            sil exe printf('keepj keepp %d,%ds/│ \([\x01\x02\x03\x04]\)/\=%s[submatch(1)]/e', lnum1, lnum2,
            \ {"\x01": '┌', "\x02": '┐', "\x03": '└', "\x04": '┘'})

        else
            " remove undesired hyphens
            call s:prepare(lnum1, lnum2, 'gq')

            " format the text-object
            sil exe 'norm! '.lnum1.'Ggq'.lnum2.'G'
            let lnum2 = line("']")

            " `s:prepare()` may have left some ‘C-a’s
            sil exe lnum1.','.lnum2.'s/\%x01\s*//ge'

            " Why?{{{
            "
            " Since we may have altered the  text after removing some ‘C-a’s, we
            " need  to re-format  it, to  be  sure that  `gq` has  done its  job
            " correctly, and that the operation is omnipotent.
            "
            " Had we removed the hyphens before invoking `gq`, we would not need
            " to re-format.
            " But  removing them,  and the  newlines which  follow, BEFORE  `gq`
            " would alter the range.
            " I don't want to recompute the range.
            " It's easier to remove them AFTER `gq`, and re-format a second time.
            "}}}
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

fu! par#gqq() abort "{{{2
    norm! mz

    let was_commented = s:is_commented()
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

fu! par#split_paragraph(mode, ...) abort "{{{2
    let [lnum1, lnum2] = s:get_range(a:mode)

    " Format sth like this:
    "     • the quick brown fox jumps over the lazy dog the quick brown fox jumps over the lazy dog
    "     • the quick brown fox jumps over the lazy dog the quick brown fox jumps over the lazy dog
    if getline(lnum1) =~# &l:flp && &l:fp =~# '^par\s' && a:mode is# 'n'
        sil exe 'norm! '.lnum1.'Ggw'.lnum2.'G'
        return
    endif

    " The last character of the paragraph needs to be a valid punctuation ending
    " for a sentence. Otherwise, our function could wrongly delete some lines.
    if getline(lnum2) =~# '\s*[^.!?:]$'
        echo 'last char is not a valid punctuation ending for a sentence'
        return
    endif

    let pos = getcurpos()
    try
        let was_commented = s:is_commented()
        let cml = get(split(&l:cms, '%s'), 0, '')

        call s:prepare(lnum1, lnum2, 'split_paragraph')

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
        let rep = "\n\n".indent
        sil exe printf('keepj keepp s/%s/\=%s/ge', pat, string(rep))

        " 2 empty lines have been added (one where we are right now, and the one above);
        " remove them
        " Why using a global command?{{{
        "
        " To be sure we're deleting empty lines.
        "}}}
        sil keepj keepp -,g/^\s*$/d_

        " format each non-empty line with `par#gqq()`
        sil exe printf('keepj keepp %d,%dg/\S/sil call par#gqq()', lnum1, line('.'))

        " remove empty lines
        if !a:0
            sil exe printf('keepj keepp %d,%dg/^$/d_', lnum1, line('.'))
        endif

        " If the text was commented, make sure it's still commented.
        if was_commented
            for i in range(lnum1, line('.'))
                if !s:is_commented(i)
                    sil exe 'keepj keepp '.i.'CommentToggle'
                endif
            endfor
        endif

        sil update
        call setpos('.', pos)

        " make the mapping repeatable
        if a:mode is# 'n'
            sil! call repeat#set("\<plug>(split-paragraph".(a:0 ? '-with-empty-lines)' : ')'))
        endif
    catch
        return lg#catch_error()
    endtry
endfu

" {{{1
" Util {{{1
fu! s:get_range(mode) abort "{{{2
    let [firstline, lastline] = a:mode is# 'n'
    \ ?     [line("'{"), line("'}")]
    \ :     [line("'<"), line("'>")]

    " get the address of the first line
    let lnum1 = firstline ==# 1 && getline(1) =~# '\S'
    \ ?     1
    \ :     firstline + 1

    " get the address of the last line of the paragraph/selection
    let lnum2 = a:mode is# 'n' && getline(lastline) =~# '^\s*$'
    \ ?     lastline - 1
    \ :     lastline

    return [lnum1, lnum2]
endfu

fu! s:is_commented(...) abort "{{{2
    if empty(&l:cms)
        return 0
    else
    let line = getline(a:0 ? a:1 : line('.'))
    let cml = split(&l:cms, '%s')[0]
    return line =~# '^\s*\V'.escape(cml, '\')
    endif
endfu

fu! s:prepare(lnum1, lnum2, cmd) abort "{{{2
    let [lnum1, lnum2] = [a:lnum1, a:lnum2]
    let range = lnum1.','.lnum2

    " Replace soft hyphens which we sometimes copy from a pdf.
    " They are annoying because they mess up the display of nearby characters.
    sil exe 'keepj keepp '.range.'s/\%u00ad/-/ge'

    " pattern describing a hyphen breaking a word on two lines
    let pat = '[\u2010-]\ze\n\s*\S\+'
    " Replace every hyphen breaking a word on two lines, with a ‘C-a’.
    " Why?{{{
    "
    " Because we don't want them. So, we mark them now, to remove them later.
    "}}}
    " Ok, but why don't you remove them right now?{{{
    "
    " We need to also remove the spaces which may come after on the next line.
    " Otherwise, a word like:
    "
    "       spec-
    "       ification
    "
    " ... could be transformed like this:
    "
    "       spec  ification
    "
    " At that  point, we would  have no way  to determine whether  2 consecutive
    " words are in fact the 2 parts of a single word which need to be merged.
    " So we need  to remove the hyphen,  and the newline, and the  spaces all at
    " once.
    " But if we  do that now, we'll  alter the range, which will  cause the next
    " commands (:join, gq) from operating on the wrong lines.
    "}}}
    sil exe 'keepj keepp '.range.'s/'.pat."/\<c-a>/ge"
    "                                         │{{{
    "                                         └ You can use `\x01` in a string:
    "                                                echo "\x01"
    "
    "                                           You can use `\%x01` in a pattern:
    "                                               /\%x01
    "
    "                                           But here, we're neither in a string nor in a pattern.
    "}}}

    if a:cmd is# 'split_paragraph'
        " In a markdown file, we could have a leading `>` in front of quoted lines.
        " The next `:j` won't remove them. We need to do it manually, and keep only
        " the first one.
        " TODO: What happens if there are nested quotes?
        sil exe 'keepj '.(lnum1+(lnum1 < lnum2 ? 1 : 0)).','.lnum2.'s/^>//e'

        " join all the lines in a single one
        sil exe 'keepj '.range.'j'

        " Now that we've joined all the lines, remove every ‘C-a’.
        sil keepj keepp s/\%x01\s*//ge
    endif
endfu

