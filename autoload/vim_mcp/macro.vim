" vim_mcp/macro.vim - Macro recording functionality

" Record a macro from a sequence of keystrokes
function! vim_mcp#macro#RecordMacro(macro_sequence, register, execute)
  call vim_mcp#utils#DebugLog('Recording macro in register ' . a:register . ': ' . a:macro_sequence)

  try
    " Ensure we're in normal mode
    if mode() != 'n'
      execute "normal! \<Esc>"
    endif

    " Store the macro in the specified register
    " We use setreg() to directly set the register content
    call setreg(a:register, a:macro_sequence, 'c')

    " Build result
    let l:result = {
      \ 'success': 1,
      \ 'register': a:register,
      \ 'macro_sequence': a:macro_sequence
      \ }

    " Execute the macro if requested
    if a:execute
      try
        " Execute the macro from the register
        execute 'normal! @' . a:register
        let l:result.output = 'Macro executed successfully'
      catch
        let l:result.output = 'Macro recorded but execution failed: ' . v:exception
      endtry
    else
      let l:result.output = 'Macro recorded successfully'
    endif

    return l:result
  catch
    call vim_mcp#utils#DebugLog('Error recording macro: ' . v:exception)
    return {
      \ 'success': 0,
      \ 'error': v:exception
      \ }
  endtry
endfunction

" Helper function to validate register name
function! vim_mcp#macro#ValidateRegister(register)
  " Check if it's a valid register (a-z, 0-9)
  return a:register =~# '^[a-z0-9]$'
endfunction

" Helper function to describe what a macro does (for user feedback)
function! vim_mcp#macro#DescribeMacro(macro_sequence)
  " This could be enhanced to provide a human-readable description
  " For now, just return the raw sequence
  return 'Macro sequence: ' . a:macro_sequence
endfunction