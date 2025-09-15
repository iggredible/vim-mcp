" vim_mcp.vim - Autoloaded functions for MCP integration

" Global variables
let s:instance_id = ''
let s:channel = v:null
let s:connected = 0
let s:connection_timer = v:null
let s:mcp_socket_path = get(g:, 'vim_mcp_socket_path', '/tmp/vim-mcp-server.sock')
let s:reconnect_interval = get(g:, 'vim_mcp_reconnect_interval', 5000)
let s:debug_enabled = get(g:, 'vim_mcp_debug', 0)

" Silent debug logging function to avoid interfering with user input
function! s:DebugLog(msg)
  if s:debug_enabled
    " Only show debug messages if explicitly enabled
    echom 'vim-mcp: ' . a:msg
  endif
endfunction

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

" Execute a Vim command and return the result
function! s:ExecuteCommand(command)
  " Silent debug logging to avoid interfering with user input
  call s:DebugLog('Executing command: ' . a:command)

  try
    " Add the command to Vim's command-line history
    call histadd(':', a:command)

    " Capture command output
    redir => l:output
    silent execute a:command
    redir END

    return {
      \ 'success': 1,
      \ 'output': l:output,
      \ 'command': a:command
      \ }
  catch
    call s:DebugLog('Error executing command: ' . v:exception)

    " Add to history even if command failed
    call histadd(':', a:command)

    return {
      \ 'success': 0,
      \ 'error': v:exception,
      \ 'output': '',
      \ 'command': a:command
      \ }
  endtry
endfunction

" Get current Vim state
function! vim_mcp#GetVimState()
  call s:DebugLog('Starting GetVimState()')
  let l:state = {}

  try
    " Current buffer info (minimal)
    call s:DebugLog('Getting current buffer info')
    let l:current_buf = {}
    let l:current_buf.id = bufnr('%')
    let l:current_buf.name = expand('%:p')
    let l:current_buf.filetype = &filetype
    let l:current_buf.line_count = line('$')
    let l:current_buf.modified = &modified
    let l:current_buf.content = []
    let l:state.current_buffer = l:current_buf
    call s:DebugLog('Current buffer info done')

    " All buffers (minimal)
    call s:DebugLog('Getting buffer list')
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
    call s:DebugLog('Buffer list done, found ' . len(l:buffers) . ' buffers')

    " Windows
    call s:DebugLog('Getting window info')
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
    call s:DebugLog('Window info done, found ' . len(l:windows) . ' windows')

    " Tabs
    call s:DebugLog('Getting tab info')
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
    call s:DebugLog('Tab info done, found ' . len(l:tabs) . ' tabs')

    " Basic info only
    let l:state.cursor = getcurpos()[1:2]
    let l:state.mode = mode()
    let l:state.cwd = getcwd()

    call s:DebugLog('GetVimState() completed successfully')
    return l:state
  catch
    call s:DebugLog('Error in GetVimState(): ' . v:exception)
    return {'error': 'Failed to get state: ' . v:exception}
  endtry
endfunction

" Handle incoming messages from MCP server
function! s:HandleMessage(channel, msg)
  try
    call s:DebugLog('Received message: ' . (len(a:msg) > 100 ? a:msg[:100] . '...' : a:msg))

    " Parse JSON message
    let l:message = json_decode(a:msg)

    " Handle different message types
    if has_key(l:message, 'type')
      if l:message.type == 'registered'
        call s:DebugLog('Registered with server as ' . l:message.instance_id)
        let s:connected = 1
      endif
    elseif has_key(l:message, 'method')
      call s:DebugLog('Processing method: ' . l:message.method)
      " Handle RPC-style requests
      let l:response = {
        \ 'id': get(l:message, 'id', 0)
        \ }

      if l:message.method == 'get_state'
        call s:DebugLog('Getting Vim state...')
        let l:response.result = vim_mcp#GetVimState()
        call s:DebugLog('State retrieved, sending response')
      elseif l:message.method == 'execute_command'
        call s:DebugLog('Executing command: ' . l:message.params.command)
        let l:response.result = s:ExecuteCommand(l:message.params.command)
        call s:DebugLog('Command executed, sending response')
      else
        let l:response.error = {
          \ 'code': -32601,
          \ 'message': 'Method not found'
          \ }
      endif

      " Send response back
      call s:SendMessage(l:response)
      call s:DebugLog('Response sent')
    endif
  catch
    call s:DebugLog('Error handling message: ' . v:exception)
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
  call s:DebugLog('Disconnected from server')
  let s:connected = 0
  let s:channel = v:null

  " Start persistent retry timer
  call s:StartConnectionTimer()
endfunction

" Connect to MCP server
function! vim_mcp#Connect()
  if s:channel != v:null && ch_status(s:channel) == 'open'
    return  " Already connected"
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
      call s:DebugLog('Connected to server at ' . s:mcp_socket_path)
    else
      throw 'Failed to connect - channel not open'
    endif
  catch
    let s:channel = v:null
    let s:connected = 0

    " Show error but don't spam if already retrying
    if s:connection_timer == v:null
      call s:DebugLog('MCP server not available, will retry every ' . (s:reconnect_interval / 1000) . 's')
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
      call s:DebugLog('Successfully connected to MCP server')
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
function! vim_mcp#SendStateUpdate()
  if s:connected
    let l:msg = {
          \ 'type': 'state_update',
          \ 'state': vim_mcp#GetVimState()
          \ }
    call s:SendMessage(l:msg)
  endif
endfunction

" Disconnect from server
function! vim_mcp#Disconnect()
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

" Status command
function! vim_mcp#Status()
  echo 'vim-mcp: ' . (s:connected ? 'Connected to server as ' . s:instance_id : 'Not connected')
endfunction
