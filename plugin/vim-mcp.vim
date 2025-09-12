" vim-mcp.vim - MCP integration for Vim (Unix socket client)
" Requires Vim 8+ with +channel or Neovim

if exists('g:loaded_vim_mcp')
  finish
endif
let g:loaded_vim_mcp = 1

let g:vim_mcp_enabled = get(g:, 'vim_mcp_enabled', 1)
if !g:vim_mcp_enabled
  finish
endif

command! VimMCPConnect call vim_mcp#Connect()
command! VimMCPDisconnect call vim_mcp#Disconnect()
command! VimMCPReconnect call vim_mcp#Disconnect() | call vim_mcp#Connect()
command! VimMCPStatus call vim_mcp#Status()
command! VimMCPTestState echo json_encode(vim_mcp#GetVimState())

augroup vim_mcp
  autocmd!
  autocmd VimEnter * call vim_mcp#Connect()
  autocmd VimLeavePre * call vim_mcp#Disconnect()
  autocmd BufEnter,BufWrite,WinEnter * call vim_mcp#SendStateUpdate()
augroup END
