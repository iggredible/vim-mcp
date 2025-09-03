" vim-mcp.vim - MCP integration for Vim (Unix socket client)
" Requires Vim 8+ with +channel or Neovim

if exists('g:loaded_vim_mcp')
  finish
endif
let g:loaded_vim_mcp = 1

" Configuration
let g:vim_mcp_enabled = get(g:, 'vim_mcp_enabled', 1)
if !g:vim_mcp_enabled
  finish
endif

" Global variables
let s:instance_id = ''
let s:channel = v:null
let s:connected = 0
let s:connection_timer = v:null
let s:mcp_socket_path = get(g:, 'vim_mcp_socket_path', '/tmp/vim-mcp-server.sock')
let s:reconnect_interval = get(g:, 'vim_mcp_reconnect_interval', 5000)

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
  echom 'vim-mcp: Starting GetVimState()'
  let l:state = {}

  try
    " Current buffer info (minimal)
    echom 'vim-mcp: Getting current buffer info'
    let l:current_buf = {}
    let l:current_buf.id = bufnr('%')
    let l:current_buf.name = expand('%:p')
    let l:current_buf.filetype = &filetype
    let l:current_buf.line_count = line('$')
    let l:current_buf.modified = &modified
    " Skip content for now to avoid timeouts
    let l:current_buf.content = []
    let l:state.current_buffer = l:current_buf
    echom 'vim-mcp: Current buffer info done'

    " All buffers (minimal)
    echom 'vim-mcp: Getting buffer list'
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
    echom 'vim-mcp: Buffer list done, found ' . len(l:buffers) . ' buffers'

    " Windows
    echom 'vim-mcp: Getting window info'
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
    echom 'vim-mcp: Window info done, found ' . len(l:windows) . ' windows'

    " Tabs
    echom 'vim-mcp: Getting tab info'
    let l:tabs = []
    for l:tabnr in range(1, tabpagenr('$'))
      let l:tab = {}
      let l:tab.id = l:tabnr
      let l:tab.active = (l:tabnr == tabpagenr())
      " Get tab label/title if available
      let l:tab.title = gettabvar(l:tabnr, 'title', '')
      if empty(l:tab.title)
        " Generate default title from main buffer
        let l:main_bufnr = tabpagebuflist(l:tabnr)[tabpagewinnr(l:tabnr) - 1]
        let l:tab.title = fnamemodify(bufname(l:main_bufnr), ':t')
        if empty(l:tab.title)
          let l:tab.title = '[No Name]'
        endif
      endif
      " Get all buffer IDs in this tab
      let l:tab.buffer_ids = tabpagebuflist(l:tabnr)
      " Get window count in this tab
      let l:tab.window_count = len(l:tab.buffer_ids)
      call add(l:tabs, l:tab)
    endfor
    let l:state.tabs = l:tabs
    echom 'vim-mcp: Tab info done, found ' . len(l:tabs) . ' tabs'

    " Basic info only
    let l:state.cursor = getcurpos()[1:2]
    let l:state.mode = mode()
    let l:state.cwd = getcwd()

    echom 'vim-mcp: GetVimState() completed successfully'
    return l:state
  catch
    echom 'vim-mcp: Error in GetVimState(): ' . v:exception
    return {'error': 'Failed to get state: ' . v:exception}
  endtry
endfunction

" Handle incoming messages from MCP server
function! s:HandleMessage(channel, msg)
  try
    echom 'vim-mcp: Received message: ' . a:msg[:100] . '...'

    " Parse JSON message
    let l:message = json_decode(a:msg)

    " Handle different message types
    if has_key(l:message, 'type')
      if l:message.type == 'registered'
        echom 'vim-mcp: Registered with server as ' . l:message.instance_id
        let s:connected = 1
      endif
    elseif has_key(l:message, 'method')
      echom 'vim-mcp: Processing method: ' . l:message.method
      " Handle RPC-style requests
      let l:response = {'id': get(l:message, 'id', 0)}

      if l:message.method == 'get_state'
        echom 'vim-mcp: Getting Vim state...'
        let l:response.result = s:GetVimState()
        echom 'vim-mcp: State retrieved, sending response'
      else
        let l:response.error = {'code': -32601, 'message': 'Method not found'}
      endif

      " Send response back
      call s:SendMessage(l:response)
      echom 'vim-mcp: Response sent'
    endif
  catch
    echom 'vim-mcp: Error handling message: ' . v:exception
    echohl ErrorMsg | echo 'vim-mcp: Error handling message: ' . v:exception | echohl None
  endtry
endfunction

" Send message to MCP server
function! s:SendMessage(msg)
  if s:channel != v:null && ch_status(s:channel) == 'open'
    try
      call ch_sendraw(s:channel, json_encode(a:msg) . "\n")
    catch
      echohl ErrorMsg | echo 'vim-mcp: Error sending message: ' . v:exception | echohl None
    endtry
  endif
endfunction

" Handle channel close
function! s:HandleClose(channel)
  echom 'vim-mcp: Disconnected from server'
  let s:connected = 0
  let s:channel = v:null

  " Start persistent retry timer
  call s:StartConnectionTimer()
endfunction

" Connect to MCP server
function! s:Connect()
  if s:channel != v:null && ch_status(s:channel) == 'open'
    return  " Already connected
  endif

  " Generate instance ID if not set
  if empty(s:instance_id)
    let s:instance_id = s:GenerateInstanceID()
  endif

  try
    " Connect to Unix socket server
    let l:address = 'unix:' . s:mcp_socket_path
    let s:channel = ch_open(l:address, {
          \ 'mode': 'raw',
          \ 'callback': function('s:HandleMessage'),
          \ 'close_cb': function('s:HandleClose')
          \ })

    if ch_status(s:channel) == 'open'
      " Connection successful - clear any retry timer
      call s:StopConnectionTimer()

      " Send registration message
      let l:register_msg = {
            \ 'type': 'register',
            \ 'instance_id': s:instance_id,
            \ 'info': {
            \   'pid': getpid(),
            \   'cwd': getcwd(),
            \   'main_file': expand('%:p'),
            \   'buffers': s:GetBufferList(),
            \   'version': v:version
            \ }
            \ }
      call s:SendMessage(l:register_msg)
      echom 'vim-mcp: Connected to server at ' . s:mcp_socket_path
    else
      throw 'Failed to connect - channel not open'
    endif
  catch
    let s:channel = v:null
    let s:connected = 0

    " Show error but don't spam if already retrying
    if s:connection_timer == v:null
      echom 'vim-mcp: MCP server not available, will retry every ' . (s:reconnect_interval / 1000) . 's'
    endif

    " Start persistent retry timer
    call s:StartConnectionTimer()
  endtry
endfunction

" Start connection retry timer
function! s:StartConnectionTimer()
  if s:connection_timer != v:null
    return  " Timer already running
  endif

  if has('timers')
    let s:connection_timer = timer_start(s:reconnect_interval, function('s:AttemptReconnect'), {'repeat': -1})
  endif
endfunction

" Stop connection retry timer
function! s:StopConnectionTimer()
  if s:connection_timer != v:null && has('timers')
    call timer_stop(s:connection_timer)
    let s:connection_timer = v:null
  endif
endfunction

" Attempt reconnection (called by timer)
function! s:AttemptReconnect(timer)
  if s:connected
    " Already connected, stop timer
    call s:StopConnectionTimer()
    return
  endif

  " Try to connect (silently this time)
  try
    let l:address = 'unix:' . s:mcp_socket_path
    let s:channel = ch_open(l:address, {
          \ 'mode': 'raw',
          \ 'callback': function('s:HandleMessage'),
          \ 'close_cb': function('s:HandleClose')
          \ })

    if ch_status(s:channel) == 'open'
      " Connection successful!
      call s:StopConnectionTimer()

      " Send registration message
      let l:register_msg = {
            \ 'type': 'register',
            \ 'instance_id': s:instance_id,
            \ 'info': {
            \   'pid': getpid(),
            \   'cwd': getcwd(),
            \   'main_file': expand('%:p'),
            \   'buffers': s:GetBufferList(),
            \   'version': v:version
            \ }
            \ }
      call s:SendMessage(l:register_msg)
      echom 'vim-mcp: Successfully connected to MCP server'
    else
      let s:channel = v:null
    endif
  catch
    let s:channel = v:null
    " Continue retrying silently
  endtry
endfunction

" Get list of buffer names
function! s:GetBufferList()
  let l:buffers = []
  for l:bufnr in range(1, bufnr('$'))
    if buflisted(l:bufnr)
      call add(l:buffers, bufname(l:bufnr))
    endif
  endfor
  return l:buffers
endfunction

" Send state update to server
function! s:SendStateUpdate()
  if s:connected
    let l:msg = {
          \ 'type': 'state_update',
          \ 'state': s:GetVimState()
          \ }
    call s:SendMessage(l:msg)
  endif
endfunction

" Disconnect from server
function! s:Disconnect()
  if s:channel != v:null
    try
      call ch_close(s:channel)
    catch
      " Ignore errors during close
    endtry
    let s:channel = v:null
    let s:connected = 0
  endif
endfunction

" Commands
command! VimMCPConnect call s:Connect()
command! VimMCPDisconnect call s:Disconnect()
command! VimMCPReconnect call s:Disconnect() | call s:Connect()
command! VimMCPStatus echo 'vim-mcp: ' . (s:connected ? 'Connected to server as ' . s:instance_id : 'Not connected')
command! VimMCPTestState echo json_encode(s:GetVimState())

" Auto-connect on Vim startup
augroup vim_mcp
  autocmd!
  autocmd VimEnter * call s:Connect()
  autocmd VimLeavePre * call s:Disconnect()
  " Send state updates on certain events
  autocmd BufEnter,BufWrite,WinEnter * call s:SendStateUpdate()
augroup END
