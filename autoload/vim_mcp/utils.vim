" vim_mcp/utils.vim - Shared utility functions

" Global debug flag
let s:debug_enabled = get(g:, 'vim_mcp_debug', 0)

" Silent debug logging function to avoid interfering with user input
function! vim_mcp#utils#DebugLog(msg)
  if s:debug_enabled
    " Only show debug messages if explicitly enabled
    echom 'vim-mcp: ' . a:msg
  endif
endfunction

" Generate instance ID
function! vim_mcp#utils#GenerateInstanceID()
  let l:filename = expand('%:t:r')
  if empty(l:filename)
    let l:filename = 'unnamed'
  endif

  " Get project name from current directory
  let l:project = fnamemodify(getcwd(), ':t')
  if empty(l:project)
    let l:project = 'unknown'
  endif

  let l:pid = getpid()
  return l:filename . '-' . l:project . '-' . l:pid
endfunction

" Get list of buffer names
function! vim_mcp#utils#GetBufferList()
  let l:buffers = []
  for l:bufnr in range(1, bufnr('$'))
    if buflisted(l:bufnr)
      call add(l:buffers, bufname(l:bufnr))
    endif
  endfor
  return l:buffers
endfunction