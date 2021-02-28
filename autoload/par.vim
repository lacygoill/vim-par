vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

# Init {{{1

import Catch from 'lg.vim'

var split_paragraph: dict<any> = {
    mode: '',
    with_empty_lines: false,
    }

# Interface {{{1
def par#gq(type: any = '', arg_lnum2 = 0): string #{{{2
    if typename(type) == 'string' && type == ''
        &opfunc = 'par#gq'
        return 'g@'
    endif

    split_paragraph.mode = mode()
    var lnum1: number
    var lnum2: number
    if arg_lnum2 == 0
        [lnum1, lnum2] = GetRange('gq')
    else
        [lnum1, lnum2] = [type, arg_lnum2]
    endif

    # If `'fp'` doesn't invoke `par(1)`,  but something else like `js-beautify`,
    # we should let the external program do its job without interfering.
    if GetFp() !~ '^par\s'
        sil exe 'norm! ' .. lnum1 .. 'Ggq' .. lnum2 .. 'G'
        return ''
    endif

    try
        var cml: string = GetCml(true)

        if HasToFormatList(lnum1)
            FormatList(lnum1, lnum2)
        else
            var kind_of_text: string = GetKindOfText(lnum1, lnum2)
            if kind_of_text == 'mixed'
                echo 'can''t format a mix of diagram and regular lines'
            elseif kind_of_text == 'diagram'
                if search('\s[┐┘]', 'nW', lnum2) > 0
                    echo 'can''t format a diagram with branches on the right'
                    return ''
                endif
                GqInDiagram(lnum1, lnum2)
            else
                Gq(lnum1, lnum2)
            endif
        endif
    catch
        Catch()
        return ''
    endtry
    return ''
enddef

def par#splitParagraphSetup(with_empty_lines = false): string #{{{2
    split_paragraph = {
        mode: mode(),
        with_empty_lines: with_empty_lines,
        }
    &opfunc = 'par#splitParagraph'
    return 'g@' .. (mode() == 'n' ? 'l' : '')
enddef

def par#removeDuplicateSpaces(type = ''): string #{{{2
    if type == ''
        &opfunc = 'par#removeDuplicateSpaces'
        return 'g@'
    endif
    var range: string = ':' .. line("'[") .. ',' .. line("']")
    exe range .. 'RemoveTabs'
    exe 'keepj keepp ' .. range .. 's/\%([.?!]\@1<=  \S\)\@!\&[ \t\xa0]\{2,}/ /gce'
    #                                 ├──────────────────────┘    ├──┘
    #                                 │                           └ no-break space
    #                                 └ preserve french spacing
    #                                   which imo improves the readability of our notes
    # https://en.wikipedia.org/wiki/History_of_sentence_spacing#French_and_English_spacing
    return ''
enddef

def par#splitParagraph(_: any) #{{{2
    if getline('.') =~ '^\s*$'
        return
    endif

    var pos: list<number> = getcurpos()
    try
        var lnum1: number
        var lnum2: number
        [lnum1, lnum2] = GetRange('split-paragraph')

        if HasToFormatList(lnum1)
            FormatList(lnum1, lnum2)
            return
        endif

        var remove_final_dot: bool = false
        # The last character of the paragraph needs to be a valid punctuation ending
        # for a sentence.  Otherwise, our function could wrongly delete some lines.
        if getline(lnum2) =~ '\s*[^.!?:]$'
            remove_final_dot = true
            setline(lnum2, getline(lnum2) .. '.')
        endif

        var was_commented: bool = IsCommented()

        RemoveHyphens(lnum1, lnum2, 'split_paragraph')

        # break down the line according to the punctuation
        var pat: string = '\C\%('
            # don't break after `e.g.`, `i.e.`, ...
            .. '[a-z][.][a-z]'
            # don't break after `etc.` or `resp.`
            .. '\|etc\|resp'
            # don't break something like `...`
            .. '\|[.][.]'
            .. '\)\@4<!'
            .. '[.!?]\zs\%(\s\+\|$\)\|:\zs\s*$'

        var changedtick: number = b:changedtick
        # Why `[.a-z]\@!` instead of `\u`?{{{
        #
        # A sentence doesn't always begin with an uppercase character.
        # For example, it may begin with a quote.
        #}}}
        var indent: string = getline(lnum1)->matchstr('^\s*')
        var rep: string = "\n\n" .. indent
        sil exe printf('keepj keepp s/%s/\=%s/ge', pat, string(rep))

        if b:changedtick != changedtick
            # If the previous command has changed/split the paragraph, two empty
            # lines have  probably been added (one  where we are right  now, and
            # the one above).  Remove them.
            # Why using a global command?{{{
            #
            # To be sure we're deleting empty lines.
            #}}}
            sil keepj keepp :-,g/^\s*$/d _
            # it seems necessary when we press `SPC p` in visual mode, otherwise
            # one extra line is unexpectedly formatted
            :-
        endif

        # format each non-empty line with our custom `gq`
        sil exe printf('keepj keepp :%d,%dg/\S/ParGq', lnum1, line('.'))
        lnum2 = line("']")

        # If the text was commented, make sure it's still commented.
        if was_commented
            MakeSureProperlyCommented(lnum1, lnum2)
        endif

        # don't move this block after the one removing empty lines,
        # because removing lines will affect `lnum2`
        if remove_final_dot
            getline(lnum2)->substitute('\.$', '', '')->setline(lnum2)
        endif

        # remove empty lines
        if !split_paragraph.with_empty_lines
            sil exe printf('keepj keepp :%d,%dg/^$/d _', lnum1, lnum2)
        endif
    catch
        Catch()
        return
    finally
        setpos('.', pos)
    endtry
enddef
# }}}1
# Core {{{1
def Gq(arg_lnum1: number, arg_lnum2: number) #{{{2
    var lnum1: number = arg_lnum1
    var lnum2: number = arg_lnum2
    var was_commented: bool = IsCommented()

    # remove undesired hyphens
    RemoveHyphens(lnum1, lnum2, 'gq')

    # If the text has a reference link with spaces, replace every possible space with ‘C-b’.{{{
    #
    # In a markdown file, if we stumble upon a reference link:
    #
    #     [some description][id]
    #
    # And if the  description, or the reference, contains  some spaces, `par(1)`
    # may break the link on two lines.
    # We don't want that.
    # So, we temporarily replace them with ‘C-b’.
    #}}}
    sil exe 'keepj keepp '
        .. ':' .. lnum1 .. ',' .. lnum2
        .. 's/\[.\{-}\]\[\d\+\]/\=submatch(0)->substitute(" ", "\<c-b>", "g")/ge'

    # format the text-object
    sil exe 'norm! ' .. lnum1 .. 'Ggq' .. lnum2 .. 'G'
    lnum2 = line("']")

    # `RemoveHyphens()` may have left some ‘C-a’s
    sil exe 'keepj keepp :' .. lnum1 .. ',' .. lnum2 .. 's/\%x01\s*//ge'

    # Why?{{{
    #
    # Since we may have altered the  text after removing some ‘C-a’s, we
    # need  to re-format  it, to  be  sure that  `gq` has  done its  job
    # correctly, and that the operation is idempotent.
    #
    # Had we removed the hyphens before invoking `gq`, we would not need
    # to re-format.
    # But  removing them,  and the  newlines which  follow, BEFORE  `gq`
    # would alter the range.
    # I don't want to recompute the range.
    # It's easier to remove them AFTER `gq`, and re-format a second time.
    #}}}
    sil exe 'norm! ' .. lnum1 .. 'Ggq' .. lnum2 .. 'G'

    # If  the original  text had  a reference  link with  spaces, replace  every
    # possible ‘C-b’ with a space.
    sil exe 'keepj keepp '
        .. ':' .. lnum1 .. ',' .. lnum2
        .. 's/\[.\{-}\]\[\d\+\]/\=submatch(0)->substitute("\<c-b>", " ", "g")/ge'

    # If the text was commented, make sure it's still commented.
    # Necessary if  we've pressed `gqq`  on a long commented  line which
    # has been split into several lines.
    if was_commented
        MakeSureProperlyCommented(lnum1, lnum2)
    endif

    # Why?{{{
    #
    # Sometimes, a superfluous space is added.
    # MWE: Press `gqq` on the following line.

    # I'm not sure our mappings handle diagrams that well.  In particular when there're several diagram characters on a single line.

    # →

    # superfluous space
    # v
    #  I'm not  sure  our mappings  handle diagrams  that  well.  In particular  when
    # there're several diagram characters on a single line.
    #}}}
    var line: string = getline(lnum1)
    var pat: string = '^\s*' .. GetCml() .. '\s\zs\s'
    if line =~ pat
        substitute(line, pat, '', '')->setline(lnum1)
        sil exe 'norm! ' .. lnum1 .. 'Ggq' .. lnum2 .. 'G'
    endif
enddef

def GqInDiagram(arg_lnum1: number, arg_lnum2: number) #{{{2
    var lnum1: number = arg_lnum1
    var lnum2: number = arg_lnum2
    var cml: string = GetCml(true)
    var pos: list<number> = getcurpos()

    # Make sure 2 consecutive branches of a diagram are separated by an empty line:{{{
    #
    # Otherwise, if you have sth like this:
    #
    #     │ some long comment
    #     │         ┌ some long comment
    #
    # The formatting won't work as expected.
    # We need to make sure that all branches are separated:
    #
    #     │ some long comment
    #     │
    #     │         ┌ some long comment
    #}}}
    var g: number = 0
    while search('[┌└]', 'W') > 0 && g < 100
        g += 1
        var l: number = line('.')
        # if the previous line is not an empty diagram line
        if getline(l - 1) !~ '^\s*' .. cml .. '\s*│\s*$' && l <= lnum2 && l > lnum1
            # put one above
            var line: string = getline(l)
                ->substitute('\s*┌.*', '', '')
                ->substitute('└\zs.*', '', '')
                ->substitute('└$', '│', '')
            append(l - 1, line)
            lnum2 += 1
        endif
    endwhile

    # For lower diagrams, we need to put a bar in front of every line which has no diagram character:{{{
    #
    #     └ some comment
    #       some comment
    #       some comment
    # →
    #     └ some comment
    #     | some comment
    #     | some comment
    #}}}
    setpos('.', pos)
    g = 0
    while search('└', 'W', lnum2) > 0 && g <= 100
        g += 1
        if GetCharAbove() !~ '[│├┤]'
            continue
        endif
        var pos_: list<number> = getcurpos()
        var gg: number = 0
        while GetCharBelow() == ' ' && GetCharAfter() == ' ' && gg <= 100
            gg += 1
            exe 'norm! jr|'
        endwhile
        setpos('.', pos_)
    endwhile

    # temporarily replace diagram characters with control characters
    sil exe printf('keepj keepp %d,%ds/[┌└]/\="│ ".%s[submatch(0)]/e',
        lnum1, lnum2, {'┌': "\x01", '└': "\x02"})
    sil exe printf('keepj keepp %d,%ds/│/|/ge', lnum1, lnum2)

    # format the lines
    sil exe 'norm! ' .. lnum1 .. 'Ggq' .. lnum2 .. 'G'

    # `gq` could have increased the number of lines, or reduced it.{{{
    #
    # There's no  guarantee that  `lnum2` still matches  the end  of the
    # original text.
    #}}}
    lnum2 = line("']")

    # restore diagram characters
    sil exe printf('keepj keepp :%d,%ds/| \([\x01\x02]\)/\=%s[submatch(1)]/ge',
        lnum1, lnum2, {"\x01": '┌', "\x02": '└'})
    # pattern describing a bar preceded by only spaces or other bars
    var pat: string = '\%(^\s*' .. cml .. '[ |]*\)\@<=|'
    sil exe printf('keepj keepp %d,%ds/%s/│/ge', lnum1, lnum2, pat)

    # For lower diagrams, there will be an undesired `│` below every `└`.
    # We need to remove them.
    setpos('.', pos)
    g = 0
    while search('└', 'W', lnum2) > 0 && g <= 100
        g += 1
        var gg: number = 0
        while GetCharBelow() =~ '[│|]' && gg <= 100
            gg += 1
            exe 'norm! jr '
        endwhile
    endwhile

    setpos('.', pos)
enddef

def FormatList(lnum1: number, lnum2: number) #{{{2
    var ai_save: bool = &l:ai
    var bufnr: number = bufnr('%')
    try
        # `'ai'` needs to be set so that `gw` can properly indent the formatted lines
        setl ai
        sil exe 'norm! ' .. lnum1 .. 'Ggw' .. lnum2 .. 'G'
    catch
        Catch()
        return
    finally
        setbufvar(bufnr, '&ai', ai_save)
    endtry
enddef

def MakeSureProperlyCommented(lnum1: number, lnum2: number) #{{{2
    for i in range(lnum1, lnum2)
        if !IsCommented(i)
            sil exe 'keepj keepp :' .. i .. 'CommentToggle'
        endif
    endfor
enddef

def RemoveHyphens(lnum1: number, lnum2: number, cmd: string) #{{{2
    var range: string = ':' .. lnum1 .. ',' .. lnum2

    # Replace soft hyphens which we sometimes copy from a pdf.
    # They are annoying because they mess up the display of nearby characters.
    sil exe 'keepj keepp ' .. range .. 's/\%u00ad/-/ge'

    # pattern describing a hyphen breaking a word on two lines
    var pat: string = '[\u2010-]\ze\n\s*\S\+'
    # Replace every hyphen breaking a word on two lines, with a ‘C-a’.{{{
    #
    # We don't want them.  So, we mark them now, to remove them later.
    #}}}
    # Why don't you remove them right now?{{{
    #
    # We need to also remove the spaces which may come after on the next line.
    # Otherwise, a word like:
    #
    #     spec-
    #     ification
    #
    # ... could be transformed like this:
    #
    #     spec  ification
    #
    # At that  point, we would  have no way  to determine whether  2 consecutive
    # words are in fact the 2 parts of a single word which need to be merged.
    # So we need to remove the hyphen, the newline, and the spaces all at once.
    # But if we  do that now, we'll  alter the range, which will  cause the next
    # commands (`:join`, `gq`) from operating on the wrong lines.
    #}}}
    sil exe 'keepj keepp ' .. range .. 's/' .. pat .. "/\x01/ge"

    if cmd == 'split_paragraph'
        # In a markdown file, we could have a leading `>` in front of quoted lines.
        # The next `:j` won't remove them.  We  need to do it manually, and keep
        # only the first one.
        # TODO: What happens if there are nested quotes?
        sil exe 'keepj keepp :' .. (lnum1 + (lnum1 < lnum2 ? 1 : 0)) .. ',' .. lnum2 .. 's/^>//e'

        # join all the lines in a single one
        sil exe 'keepj ' .. range .. 'j'

        # Now that we've joined all the lines, remove every ‘C-a’.
        sil keepj keepp s/\%x01\s*//ge
    endif
enddef
# }}}1
# Util {{{1
def GetCharAbove(): string #{{{2
    # `virtcol()` may  not be  totally reliable,  but it  should be  good enough
    # here, because the lines we format should not be too long.
    return (line('.') - 1)->getline()->matchstr('\%' .. virtcol('.') .. 'v.')
enddef

def GetCharAfter(): string #{{{2
    return getline('.')->strpart(col('.') - 1)[1]
enddef

def GetCharBelow(): string #{{{2
    return (line('.') + 1)->getline()->matchstr('\%' .. virtcol('.') .. 'v.')
enddef

def GetCml(with_equal_quantifier = false): string #{{{2
    if &l:cms == ''
        return ''
    endif
    if &ft == 'vim'
        return '["#]'
    else
        var cml: string = matchstr(&l:cms, '\S*\ze\s*%s')
        return with_equal_quantifier
            ? '\%(\V' .. escape(cml, '\') .. '\m\)\='
            : '\V' .. escape(cml, '\') .. '\m'
    endif
enddef

def GetFp(): string #{{{2
    return &l:fp == ''
        ? &g:fp
        : &l:fp
enddef

def GetKindOfText(lnum1: number, lnum2: number): string #{{{2
    var kind: string = getline(lnum1) =~ '[│┌└]'
        ? 'diagram'
        : 'normal'

    if lnum2 == lnum1
        return kind
    endif

    for i in range(lnum1 + 1, lnum2)
        if getline(i) =~ '[│┌└]' && kind == 'normal'
        || getline(i) !~ '[│┌└]' && kind == 'diagram'
            return 'mixed'
        endif
    endfor
    return kind
enddef

def GetRange(for_who: string): list<number> #{{{2
    var lnum1: number
    var lnum2: number

    if split_paragraph.mode =~ "^[vV\<c-v>]$"
        [lnum1, lnum2] = [line("'<"), line("'>")]
        # Why not returning the previous addresses directly?{{{
        #
        # If we select  a diagram, we should exclude the  first/last line, if it
        # looks like this:
        #
        #     │    │
        #
        # Otherwise, `par(1)` will  remove this line, which makes  the diagram a
        # little ugly.
        #
        # And, if the first/last line looks like:
        #
        #     ┌──┤    ┌──┤
        #
        # The formatting is wrong.
        # So, in both cases, we should ignore those lines.
        #}}}
        var cml: string = GetCml(true)
        var pat: string = '^\s*' .. cml .. '\%(\s*│\)\+\s*$'
        if getline(lnum1) =~ pat
            lnum1 += 1
        elseif getline(lnum2) =~ pat
            lnum2 -= 1
        elseif getline(lnum2) =~ '[├┤]'
            lnum2 -= 1
        elseif getline(lnum1) =~ '[├┤]'
            lnum1 += 1
        endif
        return [lnum1, lnum2]
    endif

    if for_who == 'gq'
        return [line("'["), line("']")]
    endif

    var firstline: number = line("'{")
    var lastline: number = line("'}")

    # get the address of the first line
    lnum1 = firstline == 1 && getline(1) =~ '\S'
        ? 1
        : firstline + 1

    # get the address of the last line of the paragraph
    lnum2 = getline(lastline) =~ '^\s*$'
        ? lastline - 1
        : lastline

    return [lnum1, lnum2]
enddef

def HasToFormatList(lnum1: number): bool #{{{2
    # Format sth like this:
    #    - the quick brown fox jumps over the lazy dog the quick brown fox jumps over the lazy dog
    #    - the quick brown fox jumps over the lazy dog the quick brown fox jumps over the lazy dog
    return getline(lnum1) =~ &l:flp && GetFp() =~ '^par\s'
enddef

def IsCommented(i = 0): bool #{{{2
    if &l:cms == ''
        return false
    else
        var line: string = getline(i == 0 ? '.' : i)
        return line =~ '^\s*' .. GetCml()
    endif
enddef

