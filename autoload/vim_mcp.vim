" vim_mcp.vim - Main coordinator for MCP integration

" Handle incoming messages from MCP server
function! s:HandleMessage(channel, msg)
  try
    call vim_mcp#utils#DebugLog('Received message: ' . (len(a:msg) > 100 ? a:msg[:100] . '...' : a:msg))

    " Parse JSON message
    let l:message = json_decode(a:msg)

    " Handle different message types
    if has_key(l:message, 'type')
      if l:message.type == 'registered'
        call vim_mcp#utils#DebugLog('Registered with server as ' . l:message.instance_id)
        call vim_mcp#connection#MarkConnected(l:message.instance_id)
      endif
    elseif has_key(l:message, 'method')
      call vim_mcp#utils#DebugLog('Processing method: ' . l:message.method)
      " Handle RPC-style requests
      let l:response = {
        \ 'id': get(l:message, 'id', 0)
        \ }

      if l:message.method == 'get_state'
        call vim_mcp#utils#DebugLog('Getting Vim state...')
        let l:response.result = vim_mcp#state#GetVimState()
        call vim_mcp#utils#DebugLog('State retrieved, sending response')
      elseif l:message.method == 'execute_command'
        call vim_mcp#utils#DebugLog('Executing command: ' . l:message.params.command)
        let l:response.result = vim_mcp#execute#ExecuteCommand(l:message.params.command)
        call vim_mcp#utils#DebugLog('Command executed, sending response')
      elseif l:message.method == 'search_help'
        call vim_mcp#utils#DebugLog('Searching help for: ' . l:message.params.query)
        let l:response.result = vim_mcp#search_help#SearchHelp(l:message.params.query)
        call vim_mcp#utils#DebugLog('Help search completed, sending response')
      else
        let l:response.error = {
          \ 'code': -32601,
          \ 'message': 'Method not found'
          \ }
      endif

      " Send response back
      call vim_mcp#connection#SendMessage(l:response)
      call vim_mcp#utils#DebugLog('Response sent')
    endif
  catch
    call vim_mcp#utils#DebugLog('Error handling message: ' . v:exception)
    echohl ErrorMsg | echo 'vim-mcp: Error handling message: ' . v:exception | echohl None
  endtry
endfunction

" Initialize connection module with our message handler
function! s:InitConnection()
  call vim_mcp#connection#SetMessageHandler(function('s:HandleMessage'))
endfunction

" Connect to MCP server
function! vim_mcp#Connect()
  call s:InitConnection()
  call vim_mcp#connection#Connect()
endfunction

" Disconnect from server
function! vim_mcp#Disconnect()
  call vim_mcp#connection#Disconnect()
endfunction

" Backward compatibility - expose GetVimState
function! vim_mcp#GetVimState()
  return vim_mcp#state#GetVimState()
endfunction

" Send state update to server
function! vim_mcp#SendStateUpdate()
  if vim_mcp#connection#IsConnected()
    let l:msg = {
          \ 'type': 'state_update',
          \ 'state': vim_mcp#state#GetVimState()
          \ }
    call vim_mcp#connection#SendMessage(l:msg)
  endif
endfunction

" Status command
function! vim_mcp#Status()
  let l:instance_id = vim_mcp#connection#GetInstanceID()
  echo 'vim-mcp: ' . (vim_mcp#connection#IsConnected() ? 'Connected to server as ' . l:instance_id : 'Not connected')
endfunction
