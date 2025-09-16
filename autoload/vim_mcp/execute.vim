" vim_mcp/execute.vim - Command execution functionality

" Execute a Vim command and return the result
function! vim_mcp#execute#ExecuteCommand(command)
  " Silent debug logging to avoid interfering with user input
  call vim_mcp#utils#DebugLog('Executing command: ' . a:command)

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
    call vim_mcp#utils#DebugLog('Error executing command: ' . v:exception)

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