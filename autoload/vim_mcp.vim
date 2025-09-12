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
    " Skip content for now to avoid timeouts
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
