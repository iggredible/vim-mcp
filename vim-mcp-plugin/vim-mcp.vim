" vim-mcp.vim - Simple MCP integration for Vim
" Requires Vim 8+ with +channel or Neovim

echo 'HEYYYY'
if exists('g:loaded_vim_mcp')
  finish
endif
let g:loaded_vim_mcp = 1

echo 'LOADEDDDD'

" Configuration
let g:vim_mcp_enabled = get(g:, 'vim_mcp_enabled', 1)
if !g:vim_mcp_enabled
  finish
endif

" Global variables
let s:instance_id = ''
let s:socket_path = ''
let s:state_path = ''
let s:server = v:null
let s:registry_path = '/tmp/vim-mcp-registry.json'

" Generate instance ID
function! s:GenerateInstanceID()
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

" Get current Vim state
function! s:GetVimState()
  let l:state = {}

  " Current buffer info
  let l:current_buf = {}
  let l:current_buf.id = bufnr('%')
  let l:current_buf.name = expand('%:p')
  let l:current_buf.filetype = &filetype
  let l:current_buf.line_count = line('$')
  let l:current_buf.modified = &modified
  let l:current_buf.content = getline(1, '$')
  let l:state.current_buffer = l:current_buf

  " All buffers
  let l:buffers = []
  for l:bufnr in range(1, bufnr('$'))
    if buflisted(l:bufnr)
      let l:buf = {}
      let l:buf.id = l:bufnr
      let l:buf.name = bufname(l:bufnr)
      let l:buf.modified = getbufvar(l:bufnr, '&modified')
      let l:buf.loaded = bufloaded(l:bufnr)
      call add(l:buffers, l:buf)
    endif
  endfor
  let l:state.buffers = l:buffers

  " Windows
  let l:windows = []
  for l:winnr in range(1, winnr('$'))
    let l:win = {}
    let l:win.id = l:winnr
    let l:win.buffer_id = winbufnr(l:winnr)
    let l:win.width = winwidth(l:winnr)
    let l:win.height = winheight(l:winnr)
    call add(l:windows, l:win)
  endfor
  let l:state.windows = l:windows

  " Cursor position
  let l:state.cursor = getcurpos()[1:2]  " [line, column]

  " Current mode
  let l:state.mode = mode()

  " Working directory
  let l:state.cwd = getcwd()

  " Visual selection if in visual mode
  if mode() =~# '[vV]'
    let [l:start_line, l:start_col] = getpos("'<")[1:2]
    let [l:end_line, l:end_col] = getpos("'>")[1:2]
    let l:state.selection = {
          \ 'start': [l:start_line, l:start_col],
          \ 'end': [l:end_line, l:end_col],
          \ 'text': getline(l:start_line, l:end_line)
          \ }
  endif

  return l:state
endfunction

" Handle incoming messages from MCP server
function! s:HandleMessage(channel, msg)
  try
    let l:request = json_decode(a:msg)
    let l:response = {'id': get(l:request, 'id', 0)}

    if l:request.method == 'get_state'
      let l:response.result = s:GetVimState()
    else
      let l:response.error = {'code': -32601, 'message': 'Method not found'}
    endif

    call ch_sendraw(a:channel, json_encode(l:response) . "\n")
  catch
    echohl ErrorMsg | echo 'vim-mcp: Error handling message: ' . v:exception | echohl None
  endtry
endfunction

" Update registry
function! s:UpdateRegistry()
  let l:registry = {}

  " Load existing registry
  if filereadable(s:registry_path)
    try
      let l:registry = json_decode(readfile(s:registry_path)[0])
    catch
      " Registry is corrupted, start fresh
    endtry
  endif

  " Update our entry
  let l:info = {}
  let l:info.socket = s:socket_path
  let l:info.pid = getpid()
  let l:info.cwd = getcwd()
  let l:info.main_file = expand('%:p')
  let l:info.started = strftime('%Y-%m-%dT%H:%M:%S')

  " Get buffer list
  let l:buffers = []
  for l:bufnr in range(1, bufnr('$'))
    if buflisted(l:bufnr)
      call add(l:buffers, bufname(l:bufnr))
    endif
  endfor
  let l:info.buffers = l:buffers
  let l:info.last_seen = strftime('%Y-%m-%dT%H:%M:%S')

  let l:registry[s:instance_id] = l:info

  " Write registry
  call writefile([json_encode(l:registry)], s:registry_path)
endfunction

" Write current state to file
function! s:WriteStateFile()
  if empty(s:state_path)
    return
  endif
  
  try
    let l:state = s:GetVimState()
    call writefile([json_encode(l:state)], s:state_path)
  catch
    " Ignore errors during state writing
  endtry
endfunction

" Remove from registry
function! s:RemoveFromRegistry()
  if !filereadable(s:registry_path)
    return
  endif

  try
    let l:registry = json_decode(readfile(s:registry_path)[0])
    if has_key(l:registry, s:instance_id)
      unlet l:registry[s:instance_id]
      call writefile([json_encode(l:registry)], s:registry_path)
    endif
  catch
    " Ignore errors during cleanup
  endtry
endfunction

" Start the MCP socket server
function! s:StartServer()
  if s:server != v:null
    return
  endif

  let s:instance_id = s:GenerateInstanceID()
  let s:socket_path = '/tmp/vim-mcp-' . s:instance_id . '.sock'
  let s:state_path = '/tmp/vim-mcp-' . s:instance_id . '-state.json'

  " Remove old socket if it exists
  if filereadable(s:socket_path)
    call delete(s:socket_path)
  endif

  try
    " Use file-based communication instead of sockets
    call s:UpdateRegistry()
    call s:WriteStateFile()
    echom 'vim-mcp: Started with ID ' . s:instance_id
    
    " Update state and registry periodically
    if has('timers')
      call timer_start(30000, {-> s:UpdateRegistry()}, {'repeat': -1})
      call timer_start(1000, {-> s:WriteStateFile()}, {'repeat': -1})
    endif
    
    " Set server as active
    let s:server = 1
  catch
    echohl ErrorMsg | echo 'vim-mcp: Error: ' . v:exception | echohl None
  endtry
endfunction

" Stop the server
function! s:StopServer()
  if s:server != v:null && s:server != 0
    " If we had a real channel, we'd close it here
    " call ch_close(s:server)
    let s:server = v:null
  endif

  " Remove socket and state files
  if !empty(s:socket_path) && filereadable(s:socket_path)
    call delete(s:socket_path)
  endif
  if !empty(s:state_path) && filereadable(s:state_path)
    call delete(s:state_path)
  endif

  " Remove from registry
  call s:RemoveFromRegistry()
endfunction

" Commands
command! VimMCPStart call s:StartServer()
command! VimMCPStop call s:StopServer()
command! VimMCPRestart call s:StopServer() | call s:StartServer()
command! VimMCPStatus echo 'vim-mcp: ' . (s:server != v:null && s:server != 0 ? 'Running with ID ' . s:instance_id : 'Not running')

" Auto-start on Vim startup
augroup vim_mcp
  autocmd!
  autocmd VimEnter * call s:StartServer()
  autocmd VimLeavePre * call s:StopServer()
  " Update registry when buffers change
  autocmd BufAdd,BufDelete * call s:UpdateRegistry()
augroup END
