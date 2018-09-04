" Jump to the next or previous function.
"
" mode can be 'n', 'o', or 'v' for normal, operator-pending, or visual mode.
" dir can be 'next' or 'prev'.
fun! gopher#motion#func_jump(mode, dir) abort
  " Get motion count; donere here as some commands later on will reset it.
  " -1 because the index starts from 0 in motion.
  let l:cnt = v:count1 - 1

  " Set context mark so we can jump back with  '' or ``
  normal! m'

  " select already previously selected visual content and continue from there.
  " If it's the first time starts with the visual mode. This is needed so
  " after selecting something in visual mode, every consecutive motion
  " continues.
  if a:mode is# 'v'
    normal! gv
  endif

  let l:loc = gopher#motion#func_loc(a:dir, l:cnt)
  if l:loc is 0
    return
  endif

  " Jump to top or bottom of file if we're at the first or last function.
  if type(l:loc) is v:t_dict && get(l:loc, 'err', '') is? 'no functions found'
    exe 'keepjumps normal! ' . (a:dir is# 'next' ? 'G' : 'gg')
    return
  endif

  let l:info = l:loc.fn

  " Select entire function in visual mode.
  if a:mode is# 'v' && a:dir is# 'next'
    keepjumps call cursor(l:info.rbrace.line, 1)
    return
  endif

  if a:mode is# 'v' && a:dir is# 'prev'
    " TODO: hmm, why isn't this in 'next'?
    "if has_key(l:info, 'doc') && go#config#TextobjIncludeFunctionDoc()
      keepjumps call cursor(l:info.doc.line, 1)
    "else
    "  keepjumps call cursor(info.func.line, 1)
    "endif
    return
  endif

  keepjumps call cursor(l:info.func.line, 1)
endfun

" Get the location of the previous or next function.
fun! gopher#motion#func_loc(dir, cnt) abort
  let [l:fname, l:tmp] = gopher#internal#tmpmod()

  try
    let l:cmd = [
          \ 'motion',
          \ '-format', 'vim',
          \ '-file', l:fname,
          \ '-offset', gopher#internal#cursor_offset(),
          \ '-shift', a:cnt,
          \ '-mode', a:dir,
          \ ]

    " TODO
    "if go#config#TextobjIncludeFunctionDoc()
      let l:cmd += ['-parse-comments']
    "endif

    let [l:out, l:err] = gopher#internal#tool(l:cmd)
    if l:err
      call gopher#internal#error(out)
      return
    endif
  finally
    if l:tmp isnot# ''
      call delete(l:tmp)
    endif
  endtry

  let l:loc = json_decode(l:out)
  if type(l:loc) isnot v:t_dict "|| !has_key(l:loc, 'fn')
    return 0
  endif

  return l:loc
endfun

fun! gopher#motion#comment(mode) abort
  let [l:fname, l:tmp] = gopher#internal#tmpmod()

  try
    let l:cmd = ['motion',
          \ '-format', 'json',
          \ '-file', l:fname,
          \ '-offset', gopher#internal#cursor_offset(),
          \ '-mode', 'comment',
          \ ]

    let [l:out, l:err] = gopher#internal#tool(l:cmd)
    if l:err
      call gopher#internal#error(l:out)
      return
    endif
  finally
    if l:tmp isnot# ''
      call delete(l:tmp)
    endif
  endtry

  let l:loc = json_decode(l:out)
  if type(l:loc) isnot v:t_dict || !has_key(l:loc, 'comment')
    return
  endif

  let l:info = l:loc.comment
  call cursor(l:info.startLine, l:info.startCol)

  " Adjust cursor to exclude start comment markers. Try to be a little bit
  " clever when using multi-line '/*' markers.
  if a:mode is# 'i'
    " Trim whitespace so matching below works correctly
    let l:line = substitute(getline('.'), '^\s*\(.\{-}\)\s*$', '\1', '')

    " //text
    if l:line[:2] is# '// '
      call cursor(l:info.startLine, l:info.startCol+3)
    " // text
    elseif l:line[:1] is# '//'
      call cursor(l:info.startLine, l:info.startCol+2)
    " /*
    " text
    elseif l:line =~# '^/\* *$'
      call cursor(l:info.startLine+1, 0)
      " /*
      "  * text
      if getline('.')[:2] is# ' * '
        call cursor(l:info.startLine+1, 4)
      " /*
      "  *text
      elseif getline('.')[:1] is# ' *'
        call cursor(l:info.startLine+1, 3)
      endif
    " /* text
    elseif l:line[:2] is# '/* '
      call cursor(l:info.startLine, l:info.startCol+3)
    " /*text
    elseif l:line[:1] is# '/*'
      call cursor(l:info.startLine, l:info.startCol+2)
    endif
  endif

  normal! v

  " Exclude trailing newline.
  if a:mode is# 'i'
    let l:info.endCol -= 1
  endif

  call cursor(l:info.endLine, l:info.endCol)

  " Exclude trailing '*/'.
  if a:mode is# 'i'
    let l:line = getline('.')
    " text
    " */
    if l:line =~# '^ *\*/$'
      call cursor(l:info.endLine - 1, len(getline(l:info.endLine - 1)))
    " text */
    elseif l:line[-3:] is# ' */'
      call cursor(l:info.endLine, l:info.endCol - 3)
    " text*/
    elseif l:line[-2:] is# '*/'
      call cursor(l:info.endLine, l:info.endCol - 2)
    endif
  endif
endfun

" Select a function in visual mode.
function! gopher#motion#func(mode) abort
  let [l:fname, l:tmp] = gopher#internal#tmpmod()

  try
    let l:cmd = ['motion',
          \ '-format', 'vim',
          \ '-file', l:fname,
          \ '-offset', gopher#internal#cursor_offset(),
          \ '-mode', 'enclosing',
          \ ]

    " TODO
    "if go#config#TextobjIncludeFunctionDoc()
      let l:cmd += ['-parse-comments']
    "endif

    let [l:out, l:err] = gopher#internal#tool(l:cmd)
    if l:err
      call gopher#internal#error(out)
      return
    endif
  finally
    if l:tmp isnot? ''
      call delete(l:tmp)
    endif
  endtry

  let l:loc = json_decode(l:out)
  if type(l:loc) isnot v:t_dict || !has_key(l:loc, 'fn')
    return
  endif

  let l:info = l:loc.fn

  if a:mode is# 'a'
    " anonymous functions doesn't have associated doc. Also check if the user
    " want's to include doc comments for function declarations
    " TODO
    if 0
    "if has_key(l:info, 'doc') && go#config#TextobjIncludeFunctionDoc()
    "  call cursor(l:info.doc.line, l:info.doc.col)
    "elseif l:info['sig']['name'] is '' && go#config#TextobjIncludeVariable()
    "  " one liner anonymous functions
    "  if l:info.lbrace.line is l:info.rbrace.line
    "    " jump to first nonblack char, to get the correct column
    "    call cursor(l:info.lbrace.line, 0 )
    "    normal! ^
    "    call cursor(l:info.func.line, col("."))
    "  else
    "    call cursor(l:info.func.line, l:info.rbrace.col)
    "  endif
    "else
      call cursor(l:info.func.line, l:info.func.col)
    endif

    normal! v
    call cursor(l:info.rbrace.line, l:info.rbrace.col)
    return
  elseif a:mode is# 'i'
    " if the function is a one liner we need to select only that portion
    if l:info.lbrace.line is l:info.rbrace.line
      call cursor(l:info.lbrace.line, l:info.lbrace.col + 1)
      normal! v
      call cursor(l:info.rbrace.line, l:info.rbrace.col - 1)
      return
    endif

    call cursor(l:info.lbrace.line + 1, 1)
    normal! V
    call cursor(l:info.rbrace.line - 1, 1)
  endif
endfun
