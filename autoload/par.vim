" Interface {{{1
fu! par#gq(type, ...) abort "{{{2
    let [lnum1, lnum2] = a:0
            \ ? [a:1, a:2]
            \ : s:get_range('gq', a:type)

    " If 'fp' doesn't invoke `$ par`, but something else like `$ js-beautify`,
    " we should let the external program do its job without interfering.
    if s:get_fp() !~# '^par\s'
        sil exe 'norm! '.lnum1.'Ggq'.lnum2.'G'
        return
    endif

    try
        let cml = s:get_cml('with_equal_quantifier')

        if s:has_to_format_list(lnum1)
            call s:format_list(lnum1, lnum2)
        else
            let kind_of_text = s:get_kind_of_text(lnum1, lnum2)
            if kind_of_text is# 'mixed'
                echo 'can''t format a mix of diagram and regular lines'
            elseif kind_of_text is# 'diagram'
                if search('\s[┐┘]', 'nW', lnum2)
                    echo 'can''t format a diagram with branches on the right'
                    return
                endif
                call s:gq_in_diagram(lnum1, lnum2)
            else
                call s:gq(lnum1, lnum2)
            endif
        endif
    catch
        return lg#catch_error()
    endtry
endfu

fu! par#remove_duplicate_spaces(type) abort "{{{2
    let range = line("'[").','.line("']")
    exe 'keepj keepp '.range.'s/\s\{2,}/ /gc'
endfu

fu! par#split_paragraph(mode, ...) abort "{{{2
    if getline('.') =~# '^\s*$'
        return
    endif

    let pos = getcurpos()
    try
        let [lnum1, lnum2] = s:get_range('split-paragraph', s:split_paragraph_mode)

        if s:has_to_format_list(lnum1)
            call s:format_list(lnum1, lnum2)
            return
        endif

        let remove_final_dot = 0
        " The last character of the paragraph needs to be a valid punctuation ending
        " for a sentence. Otherwise, our function could wrongly delete some lines.
        if getline(lnum2) =~# '\s*[^.!?:]$'
            let remove_final_dot = 1
            call setline(lnum2, getline(lnum2).'.')
        endif

        let was_commented = s:is_commented()

        call s:remove_hyphens(lnum1, lnum2, 'split_paragraph')

        " break the line down according to the punctuation
        "            ┌ don't break after `e.g.`, `i.e.`, ...
        "            ├───────────┐
        let pat = '\C\%([a-z]\.[a-z]\)\@<![.!?]\zs\%(\s\+[.]\@!\|$\)\|:\zs\s*$'
        "                                                 │
        "                                                 └ don't break something like `...`

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

        " format each non-empty line with our custom `gq`
        sil exe printf('keepj keepp %d,%dg/\S/ParGq', lnum1, line('.'))
        let lnum2 = line("']")

        " If the text was commented, make sure it's still commented.
        if was_commented
            call s:make_sure_properly_commented(lnum1, lnum2)
        endif

        " don't move this block after the one removing empty lines,
        " because removing lines will affect `lnum2`
        if remove_final_dot
            call setline(lnum2, substitute(getline(lnum2), '\.$', '', ''))
        endif

        " remove empty lines
        if !s:split_paragraph_with_empty_lines
            sil exe printf('keepj keepp %d,%dg/^$/d_', lnum1, lnum2)
        endif
    catch
        return lg#catch_error()
    finally
        call setpos('.', pos)
    endtry
endfu

" Core {{{1
fu! s:gq(lnum1, lnum2) abort "{{{2
    let [lnum1, lnum2] = [a:lnum1, a:lnum2]
    let was_commented = s:is_commented()

    " remove undesired hyphens
    call s:remove_hyphens(lnum1, lnum2, 'gq')

    " If the text has a reference link with spaces, replace every possible space with ‘C-b’.{{{
    "
    " In a markdown file, if we stumble upon a reference link:
    "
    "     [some description][id]
    "
    " And if  the description, or the  reference, contains some spaces,  `$ par`
    " may break the link on two lines.
    " We don't want that.
    " So, we temporarily replace them with ‘C-b’.
    "}}}
    sil exe 'keepj keepp '.lnum1.','.lnum2.'s/\[.\{-}\]\[\d\+\]/\=substitute(submatch(0), " ", "\<c-b>", "g")/ge'

    " format the text-object
    sil exe 'norm! '.lnum1.'Ggq'.lnum2.'G'
    let lnum2 = line("']")

    " `s:remove_hyphens()` may have left some ‘C-a’s
    sil exe 'keepj keepp '.lnum1.','.lnum2.'s/\%x01\s*//ge'

    " Why?{{{
    "
    " Since we may have altered the  text after removing some ‘C-a’s, we
    " need  to re-format  it, to  be  sure that  `gq` has  done its  job
    " correctly, and that the operation is idempotent.
    "
    " Had we removed the hyphens before invoking `gq`, we would not need
    " to re-format.
    " But  removing them,  and the  newlines which  follow, BEFORE  `gq`
    " would alter the range.
    " I don't want to recompute the range.
    " It's easier to remove them AFTER `gq`, and re-format a second time.
    "}}}
    sil exe 'norm! '.lnum1.'Ggq'.lnum2.'G'

    " If  the original  text had  a reference  link with  spaces, replace  every
    " possible ‘C-b’ with a space.
    sil exe 'keepj keepp '.lnum1.','.lnum2.'s/\[.\{-}\]\[\d\+\]/\=substitute(submatch(0), "\<c-b>", " ", "g")/ge'

    " If the text was commented, make sure it's still commented.
    " Necessary if  we've pressed `gqq`  on a long commented  line which
    " has been split into several lines.
    if was_commented
        call s:make_sure_properly_commented(lnum1, lnum2)
    endif

    " Why?{{{
    "
    " Sometimes, a superfluous space is added.
    " MWE: Press `gqq` on the following line.

    " I'm not sure our mappings handle diagrams that well. In particular when there're several diagram characters on a single line.

    " →

    " superfluous space
    " v
    "  I'm not  sure  our mappings  handle diagrams  that  well. In particular  when
    " there're several diagram characters on a single line.
    "}}}
    let line = getline(lnum1)
    let pat = '^\s*'.s:get_cml().'\s\zs\s'
    if line =~# pat
        call setline(lnum1, substitute(line, pat, '', ''))
        sil exe 'norm! '.lnum1.'Ggq'.lnum2.'G'
    endif
endfu

fu! s:gq_in_diagram(lnum1, lnum2) abort "{{{2
    let [lnum1, lnum2] = [a:lnum1, a:lnum2]
    let cml = s:get_cml('with_equal_quantifier')
    let pos = getcurpos()

    " Make sure 2 consecutive branches of a diagram are separated by an empty line:{{{
    "
    " Otherwise, if you have sth like this:
    "
    "     │ some long comment
    "     │         ┌ some long comment
    "
    " The formatting won't work as expected.
    " We need to make sure that all branches are separated:
    "
    "     │ some long comment
    "     │
    "     │         ┌ some long comment
    "}}}
    let g = 0
    while search('[┌└]', 'W') && g < 100
        let l = line('.')
        " if the previous line is not an empty diagram line
        if getline(l-1) !~# '^\s*'.cml.'\s*│\s*$' && l <= lnum2 && l > lnum1
            " put one above
            let line = getline(l)
            let line = substitute(line, '\s*┌.*', '', '')
            let line = substitute(line, '└\zs.*', '', '')
            let line = substitute(line, '└$', '│', '')
            call append(l-1, line)
            let lnum2 += 1
        endif
        let g += 1
    endwhile

    " For lower diagrams, we need to put a bar in front of every line which has no diagram character:{{{
    "
    "     └ some comment
    "       some comment
    "       some comment
    " →
    "     └ some comment
    "     | some comment
    "     | some comment
    "}}}
    call setpos('.', pos)
    let g = 0
    while search('└', 'W', lnum2)
     \ && g <= 100
        if s:get_char_above() !~# '[│├┤]'
            continue
        endif
        let pos_ = getcurpos()
        let i = 1
        let g_ = 0
        while s:get_char_below() is# ' '
         \ && s:get_char_after() is# ' '
         \ && g_ <= 100
            exe 'norm! jr|'
            let i += 1
            let g_ += 1
        endwhile
        let g += 1
        call setpos('.', pos_)
    endwhile

    " temporarily replace diagram characters with control characters
    sil exe printf('keepj keepp %d,%ds/[┌└]/\="│ ".%s[submatch(0)]/e', lnum1, lnum2,
    \ {'┌': "\x01", '└': "\x02"})
    sil exe printf('keepj keepp %d,%ds/│/|/ge', lnum1, lnum2)

    " format the lines
    sil exe 'norm! '.lnum1.'Ggq'.lnum2.'G'

    " `gq` could have increased the number of lines, or reduced it.{{{
    "
    " There's no  guarantee that  `lnum2` still matches  the end  of the
    " original text.
    "}}}
    let lnum2 = line("']")

    " restore diagram characters
    sil exe printf('keepj keepp %d,%ds/| \([\x01\x02]\)/\=%s[submatch(1)]/ge', lnum1, lnum2,
    \ {"\x01": '┌', "\x02": '└'})
    " pattern describing a bar preceded by only spaces or other bars
    let pat = '\%(^\s*'.cml.'[ |]*\)\@<=|'
    sil exe printf('keepj keepp %d,%ds/%s/│/ge', lnum1, lnum2, pat)

    " For lower diagrams, there will be an undesired `│` below every `└`.
    " We need to remove them.
    call setpos('.', pos)
    let g = 0
    while search('└', 'W', lnum2) && g <= 100
        let i = 1
        let g_ = 0
        while s:get_char_below() =~# '[│|]' && g_ <= 100
            exe 'norm! jr '
            let i += 1
            let g_ += 1
        endwhile
        let g += 1
    endwhile

    call setpos('.', pos)
endfu

fu! s:format_list(lnum1, lnum2) abort "{{{2
    let ai_save = &l:ai
    try
        " 'ai' needs to be set so that `gw` can properly indent the formatted lines
        setl ai
        sil exe 'norm! '.a:lnum1.'Ggw'.a:lnum2.'G'
    catch
        return lg#catch_error()
    finally
        let &l:ai = ai_save
    endtry
endfu

fu! s:make_sure_properly_commented(lnum1, lnum2) abort "{{{2
    for i in range(a:lnum1, a:lnum2)
        if !s:is_commented(i)
            sil exe 'keepj keepp '.i.'CommentToggle'
        endif
    endfor
endfu

fu! s:remove_hyphens(lnum1, lnum2, cmd) abort "{{{2
    let [lnum1, lnum2] = [a:lnum1, a:lnum2]
    let range = lnum1.','.lnum2

    " Replace soft hyphens which we sometimes copy from a pdf.
    " They are annoying because they mess up the display of nearby characters.
    sil exe 'keepj keepp '.range.'s/\%u00ad/-/ge'

    " pattern describing a hyphen breaking a word on two lines
    let pat = '[\u2010-]\ze\n\s*\S\+'
    " Replace every hyphen breaking a word on two lines, with a ‘C-a’.{{{
    "
    " We don't want them. So, we mark them now, to remove them later.
    "}}}
    " Why don't you remove them right now?{{{
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
        sil exe 'keepj keepp'.(lnum1+(lnum1 < lnum2 ? 1 : 0)).','.lnum2.'s/^>//e'

        " join all the lines in a single one
        sil exe 'keepj '.range.'j'

        " Now that we've joined all the lines, remove every ‘C-a’.
        sil keepj keepp s/\%x01\s*//ge
    endif
endfu

" Util {{{1
fu! s:get_char_above() abort "{{{2
    " `virtcol()` may  not be  totally reliable,  but it  should be  good enough
    " here, because the lines we format should not be too long.
    return matchstr(getline(line('.')-1), '\%'.virtcol('.').'v.')
endfu

fu! s:get_char_after() abort "{{{2
    return matchstr(getline('.'), '\%'.col('.').'c.\zs.')
endfu

fu! s:get_char_below() abort "{{{2
    return matchstr(getline(line('.')+1), '\%'.virtcol('.').'v.')
endfu

fu! s:get_cml(...) abort "{{{2
    if &l:cms is# ''
        return ''
    endif
    let cml = split(&l:cms, '%s')[0]
    return a:0
    \ ?        '\%(\V'.escape(cml, '\').'\m\)\='
    \ :        '\V'.escape(cml, '\').'\m'
endfu

fu! s:get_fp() abort "{{{2
    return &l:fp is# ''
    \ ?        &g:fp
    \ :        &l:fp
endfu

fu! s:get_kind_of_text(lnum1, lnum2) abort "{{{2
    let kind = getline(a:lnum1) =~# '[│┌└]'
    \ ?            'diagram'
    \ :            'normal'

    if a:lnum2 ==# a:lnum1
        return kind
    endif

    for i in range(a:lnum1+1, a:lnum2)
        if getline(i) =~# '[│┌└]' && kind is# 'normal'
        \ || getline(i) !~# '[│┌└]' && kind is# 'diagram'
            return 'mixed'
        endif
    endfor
    return kind
endfu

fu! s:get_range(for_who, mode) abort "{{{2
    if a:mode is# 'x'
        let [lnum1, lnum2] = [line("'<"), line("'>")]
        " Why not returning the previous addresses directly?{{{
        "
        " If we select  a diagram, we should exclude the  first/last line, if it
        " looks like this:
        "
        "     │    │
        "
        " Otherwise,  `$ par` will remove  this line, which makes  the diagram a
        " little ugly.
        "
        " And, if the first/last line looks like:
        "
        "     ┌──┤    ┌──┤
        "
        " The formatting is wrong.
        " So, in both cases, we should ignore those lines.
        "}}}
        let cml = s:get_cml('with_equal_quantifier')
        let pat = '^\s*'.cml.'\%(\s*│\)\+\s*$'
        if getline(lnum1) =~# pat
            let lnum1 += 1
        elseif getline(lnum2) =~# pat
            let lnum2 -= 1
        elseif getline(lnum2) =~# '[├┤]'
            let lnum2 -= 1
        elseif getline(lnum1) =~# '[├┤]'
            let lnum1 += 1
        endif

        return [lnum1, lnum2]
    endif

    if a:for_who is# 'gq'
        return [line("'["), line("']")]
    endif

    let [firstline, lastline] = [line("'{"), line("'}")]

    " get the address of the first line
    let lnum1 = firstline ==# 1 && getline(1) =~# '\S'
    \ ?     1
    \ :     firstline + 1

    " get the address of the last line of the paragraph
    let lnum2 = getline(lastline) =~# '^\s*$'
    \ ?     lastline - 1
    \ :     lastline

    return [lnum1, lnum2]
endfu

fu! s:has_to_format_list(lnum1) abort "{{{2
    " Format sth like this:
    "     • the quick brown fox jumps over the lazy dog the quick brown fox jumps over the lazy dog
    "     • the quick brown fox jumps over the lazy dog the quick brown fox jumps over the lazy dog
    return getline(a:lnum1) =~# &l:flp && s:get_fp() =~# '^par\s'
endfu

fu! s:is_commented(...) abort "{{{2
    if &l:cms is# ''
        return 0
    else
        let line = getline(a:0 ? a:1 : line('.'))
        return line =~# '^\s*'.s:get_cml()
    endif
endfu

fu! par#split_paragraph_save_param(mode, with_empty_lines) abort "{{{2
    let s:split_paragraph_mode = a:mode
    let s:split_paragraph_with_empty_lines = a:with_empty_lines
endfu

