" vim_mcp/search_help.vim - Vim help search functionality

" Search Vim help and open the most relevant section
function! vim_mcp#search_help#SearchHelp(query)
  call vim_mcp#utils#DebugLog('Searching help for: ' . a:query)

  try
    " First, try exact help match
    try
      execute 'silent help ' . a:query
      " If we get here, the help topic was found
      let l:tag = a:query
      let l:file = expand('%:p')
      let l:line = line('.')

      call vim_mcp#utils#DebugLog('Found exact help match for: ' . a:query)
      return {
        \ 'success': 1,
        \ 'tag': l:tag,
        \ 'file': l:file,
        \ 'line': l:line,
        \ 'query': a:query
        \ }
    catch
      " Exact match failed, try fuzzy search
      call vim_mcp#utils#DebugLog('Exact match failed, trying fuzzy search')
    endtry

    " Try helpgrep for pattern search
    try
      " Use helpgrep to find matching topics
      redir => l:helpgrep_output
      silent execute 'helpgrep \c' . escape(a:query, '[]~.*^$\')
      redir END

      " Jump to the first match
      if exists(':cc')
        silent cc 1
        let l:tag = 'pattern match'
        let l:file = expand('%:p')
        let l:line = line('.')

        call vim_mcp#utils#DebugLog('Found pattern match via helpgrep')
        return {
          \ 'success': 1,
          \ 'tag': l:tag,
          \ 'file': l:file,
          \ 'line': l:line,
          \ 'query': a:query,
          \ 'method': 'helpgrep'
          \ }
      endif
    catch
      call vim_mcp#utils#DebugLog('Helpgrep also failed: ' . v:exception)
    endtry

    " If both methods fail, try some common variations
    let l:variations = [
      \ a:query . '()',
      \ ':' . a:query,
      \ 'g:' . a:query,
      \ '*' . a:query . '*'
      \ ]

    for l:variation in l:variations
      try
        execute 'silent help ' . l:variation
        let l:tag = l:variation
        let l:file = expand('%:p')
        let l:line = line('.')

        call vim_mcp#utils#DebugLog('Found help with variation: ' . l:variation)
        return {
          \ 'success': 1,
          \ 'tag': l:tag,
          \ 'file': l:file,
          \ 'line': l:line,
          \ 'query': a:query,
          \ 'method': 'variation'
          \ }
      catch
        " Continue to next variation
      endtry
    endfor

    " No help found
    call vim_mcp#utils#DebugLog('No help found for: ' . a:query)
    return {
      \ 'success': 0,
      \ 'query': a:query,
      \ 'message': 'No help found for this topic'
      \ }

  catch
    call vim_mcp#utils#DebugLog('Error in SearchHelp: ' . v:exception)
    return {
      \ 'success': 0,
      \ 'error': v:exception,
      \ 'query': a:query
      \ }
  endtry
endfunction