" vim_mcp/state.vim - Vim state management

" Get current Vim state
function! vim_mcp#state#GetVimState()
  call vim_mcp#utils#DebugLog('Starting GetVimState()')
  let l:state = {}

  try
    " Current buffer info (minimal)
    call vim_mcp#utils#DebugLog('Getting current buffer info')
    let l:current_buf = {}
    let l:current_buf.id = bufnr('%')
    let l:current_buf.name = expand('%:p')
    let l:current_buf.filetype = &filetype
    let l:current_buf.line_count = line('$')
    let l:current_buf.modified = &modified
    let l:current_buf.content = []
    let l:state.current_buffer = l:current_buf
    call vim_mcp#utils#DebugLog('Current buffer info done')

    " All buffers (minimal)
    call vim_mcp#utils#DebugLog('Getting buffer list')
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
    call vim_mcp#utils#DebugLog('Buffer list done, found ' . len(l:buffers) . ' buffers')

    " Windows
    call vim_mcp#utils#DebugLog('Getting window info')
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
    call vim_mcp#utils#DebugLog('Window info done, found ' . len(l:windows) . ' windows')

    " Tabs
    call vim_mcp#utils#DebugLog('Getting tab info')
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
    call vim_mcp#utils#DebugLog('Tab info done, found ' . len(l:tabs) . ' tabs')

    " Basic info only
    let l:state.cursor = getcurpos()[1:2]
    let l:state.mode = mode()
    let l:state.cwd = getcwd()

    call vim_mcp#utils#DebugLog('GetVimState() completed successfully')
    return l:state
  catch
    call vim_mcp#utils#DebugLog('Error in GetVimState(): ' . v:exception)
    return {'error': 'Failed to get state: ' . v:exception}
  endtry
endfunction