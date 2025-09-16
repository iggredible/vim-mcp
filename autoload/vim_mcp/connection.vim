" vim_mcp/connection.vim - Server connection management

" Connection state variables
let s:channel = v:null
let s:connected = 0
let s:connection_timer = v:null
let s:instance_id = ''
let s:mcp_socket_path = get(g:, 'vim_mcp_socket_path', '/tmp/vim-mcp-server.sock')
let s:reconnect_interval = get(g:, 'vim_mcp_reconnect_interval', 5000)

" Get connection status
function! vim_mcp#connection#IsConnected()
  return s:connected
endfunction

" Get channel
function! vim_mcp#connection#GetChannel()
  return s:channel
endfunction

" Get instance ID
function! vim_mcp#connection#GetInstanceID()
  return s:instance_id
endfunction

" Set message handler (callback from main module)
let s:message_handler = v:null
function! vim_mcp#connection#SetMessageHandler(handler)
  let s:message_handler = a:handler
endfunction

" Handle incoming messages from MCP server
function! s:HandleMessage(channel, msg)
  if s:message_handler != v:null
    call s:message_handler(a:channel, a:msg)
  endif
endfunction

" Send message to MCP server
function! vim_mcp#connection#SendMessage(msg)
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
  call vim_mcp#utils#DebugLog('Disconnected from server')
  let s:connected = 0
  let s:channel = v:null

  " Start persistent retry timer
  call s:StartConnectionTimer()
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
            \   'buffers': vim_mcp#utils#GetBufferList(),
            \   'version': v:version
            \ }
            \ }
      call vim_mcp#connection#SendMessage(l:register_msg)
      call vim_mcp#utils#DebugLog('Successfully connected to MCP server')
    else
      let s:channel = v:null
    endif
  catch
    let s:channel = v:null
    " Continue retrying silently
  endtry
endfunction

" Connect to MCP server
function! vim_mcp#connection#Connect()
  if s:channel != v:null && ch_status(s:channel) == 'open'
    return  " Already connected"
  endif

  " Generate instance ID if not set
  if empty(s:instance_id)
    let s:instance_id = vim_mcp#utils#GenerateInstanceID()
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
            \   'buffers': vim_mcp#utils#GetBufferList(),
            \   'version': v:version
            \ }
            \ }
      call vim_mcp#connection#SendMessage(l:register_msg)
      call vim_mcp#utils#DebugLog('Connected to server at ' . s:mcp_socket_path)
    else
      throw 'Failed to connect - channel not open'
    endif
  catch
    let s:channel = v:null
    let s:connected = 0

    " Show error but don't spam if already retrying
    if s:connection_timer == v:null
      call vim_mcp#utils#DebugLog('MCP server not available, will retry every ' . (s:reconnect_interval / 1000) . 's')
    endif

    " Start persistent retry timer
    call s:StartConnectionTimer()
  endtry
endfunction

" Disconnect from server
function! vim_mcp#connection#Disconnect()
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

" Mark as connected (called by main module when registration succeeds)
function! vim_mcp#connection#MarkConnected(instance_id)
  let s:connected = 1
  if !empty(a:instance_id)
    let s:instance_id = a:instance_id
  endif
endfunction