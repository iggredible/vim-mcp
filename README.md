# vim-mcp

Simple MCP (Model Context Protocol) integration for Vim and Claude Code.
 
## Features

- Connect Claude Code to one of your Vim instances
- Query Vim state (buffers, windows, cursor position, etc.)
- Execute Vim commands from Claude using natural language

How it works:
1. The MCP server starts a Unix socket server at `/tmp/vim-mcp-server.sock`
2. Each Vim instance connects to the server as a Unix socket client
3. Vim sends registration and state updates to the server
4. The server maintains active connections to all Vim instances
5. Claude Code communicates with the MCP server via Model Context Protocol

### Demo

List and select Vim instance:
<p><img src="https://github.com/user-attachments/assets/1f1e7335-b256-4b7f-be57-bf49cdee1c69" alt="List and select Vim instances" width="75%"></p>

You can (finally) exit Vim!
<p><img src="https://github.com/user-attachments/assets/19436984-1464-41f8-b12a-3d15a54b79cc" alt="List and select Vim instances" width="75%"></p>

For more, check out the [demo wiki page](https://github.com/iggredible/vim-mcp/wiki/Demo)

### Why would anyone need this?

Ok, I get what it does, but why do we need this?

If you're trying to do basic Vim operation like: typing "split the window in half" (24 keystrokes) vs running :sp / :vs (3 kevstrokes), then vim-mcp won't be of much help. Where vim-cmp shines is when **the # keystrokes is unknown**. When you can only describe what you want to do but do not know exactly what to do. Things like complex regex/ macros/ lookups, help semantic search, etc - it's faster to tell Al what you're trying to accomplish than trial-and-error. I think the word I'm looking for is circumlocution?

Here's one scenario where it may be useful:

Suppose you want to perform a complex Vim command that otherwise will take a long time to construct. Claude can easily do it if you can describe what you want to do. Maybe you want to substitute "(test foobar)" with square brackets ONLY IF they come after a 3rd level Markdown header. That's not something I can easily cook up in seconds... but Claude can! Without vim-mcp, Claude would probably print out the command, then I'd have to copy that command somehow, and paste that in Vim. 

With vim-mcp, in Claude, I can prompt:

```
In README.md, substitute the set of parentheses `(SOME TEXT)` with square brackets `[SOME TEXT]`, where SOME TEXT says "test foobar"; do this if the strings come after a 3rd-level header markdown.
```

And that's it! When I did it, Claude came up with the `g` command and executed it for me.
```
vim-mcp - vim_execute (MCP)(command: "g/^### /,/^#\\{1,3\\} \\|^$/s/(test foobar)/[test foobar]/g")
  ⎿  Command executed successfully: g/^### /,/^#\{1,3\} \|^$/s/(test foobar)/[test foobar]/g
```

Bonus: the executed commands aree stored in the command history so you can go back and re-execute them or modify them.

What if you later decided, "Hey, I actually don't want to substitute them with square brackets `[]`, I want to substitute them with curly brackets `{}` instead! You can just access the command history (`q:`, `:history`, or `:` then press up/down) and then make necessary modifications.

So I did `:`, then pressed the up arrow a few times until I saw the command that vim-mcp executed, and changed it to `:g/^### /,/^#\{1,3\} \|^$/s/(test foobar)/{test foobar}/g`. Done! 

### Overview

For a detailed overview, see [vim-mcp overview](doc/vim-mcp-overview.md).

### Tools and Resources

Tools:
1. `list_vim_instances`
2. `select_vim_instance`
3. `get_vim_state`
4. `vim_execute`
5. `exit_vim`
6. `vim_search_help`

Resources:
1. `vim://instances` - List of all available Vim instances
2. `vim://state` - Current state of the selected Vim instance
3. `vim://buffers` - List of all buffers in the selected Vim instance
4. `vim://tabs` - List of all tabs in the selected Vim instance


## Installation

### Prerequisites

- Vim 8+ with `+channel` feature OR Neovim 0.5+
- Node.js 18+
- Unix domain socket support (Linux/macOS)
- File system write access to `/tmp` directory
- [claude code](https://www.anthropic.com/claude-code) / [claude desktop](https://claude.ai/download) or similar tools that support MCP

### Install the Vim Plugin

Using vim-plug:
```vim
Plug 'iggredible/vim-mcp'
```

### Install the MCP Server

The MCP server is a Node project. You need to install the dependencies.

#### Option 1: Using the Install Script

```bash
cd ~/.vim/plugged/vim-mcp  # Or wherever your plugin is installed
./install.sh
```

The install script will automatically:
- Check prerequisites (Node.js and Vim versions)
- Install Node.js dependencies
- Attempt global installation of the `vim-mcp` command
- Show you the correct Claude Code configuration

#### Option 2: Manual Installation

If you prefer to install manually or the `install.sh` script doesn't work:

1. Install Node.js dependencies:

```bash
cd ~/.vim/plugged/vim-mcp/server
npm install
```

`npm install` should also run `chmod +x bin/vim-mcp`

2. (Optional) Install globally for system-wide `vim-mcp` command (inside the `/server` directory):

```bash
npm link
```

If this fails due to permissions or whatever reason, you can skip global installation and use the full path in your config.

### Configure Claude Code

After installation, add one of these configurations to your Claude configuration file:

If global install succeeded (if `vim-mcp` command is available):

```json
  "mcpServers": {
    "vim-mcp": {
      "command": "vim-mcp",
      "args": []
    },
  }
```

If npm link failed:

```json
{
  "mcpServers": {
    "vim-mcp": {
      "command": "node",
      "args": ["/some/path/.vim/plugged/vim-mcp/server/bin/vim-mcp"]
    }
  }
}
```

## Uninstall

To remove vim-mcp:

1. Remove the plugin from your `.vimrc`:
```vim
" Delete or comment out this line:
" Plug 'iggredible/vim-mcp'
```

2. Clean up the plugin files:
```vim
:PlugClean
```

3. Remove the global `vim-mcp` command (if installed):
```bash
npm unlink vim-mcp
```

4. Remove from Claude Code configuration:

Edit the Claude config file and remove the `vim-mcp` section from `mcpServers`

5. **Clean up temporary files (optional):**
```bash
rm -f /tmp/vim-mcp-server.sock
rm -f /tmp/vim-mcp-registry.json
rm -f /tmp/vim-mcp-preference.txt
```

6. **Restart Vim and Claude Code** to ensure all connections are cleared.

## Quick Start

### Step-by-Step Connection Process

1. Open Vim instances (the plugin connects automatically):

```bash
vim file1.txt    # First instance
vim file2.txt    # Second instance (in another terminal)
```

2. In Claude Code, list available Vim instances:

```
list vim instances
```

3. If multiple instances are found, select one:
```
select vim instance file1-vim-12345
```

### Things you can prompt

From the client (claude code), you can:

1. Manage instances:
    - "List vim instances"
    - "Connect to the first one pls"
    - "Select the one with README.md open"

2. Control Vim:
    - "Split into two windows vertically"
    - "execute vim command <ex-command>"
    - "HELP ME EXIT VIM!!!"

3. Query about Vim:
   - "How many buffers do I have?"
   - "What buffers are open?"
   - "What is my cursor position?"
   - "Show me the current buffer content"
   - "How many lines are in the active buffer?"
   - "What language is the file written in?"
   - "What windows are open?"
   - "What is the realistic 10-year target price for BTC?" (*jk*)

### vim-mcp can help you exit Vim!!

You can FINALLY exit Vim! Rejoice! The `exit_vim` tool provides safe exit functionality with three modes:

- Default (check): Checks for unsaved changes and warns you before exiting
- Save and exit: Saves all modified buffers and exits (`exit vim save_and_exit`)  
- Force exit: Exits without saving, discarding changes (`exit vim force_exit`)

Examples:
```
exit vim                   # Safe exit - warns about unsaved changes
exit vim save_and_exit     # Save all files and exit
exit vim force_exit        # Exit without saving (discard changes)
GET ME OUTTA HERE          # You're free! Successfully exited Vim (there were no unsaved changes).
```

### Vim Commands

The plugin connects automatically when Vim opens. However, you can do these from inside Vim:
- `:VimMCPStatus` - Check connection status
- `:VimMCPConnect` - Manually connect to server
- `:VimMCPDisconnect` - Disconnect from server
- `:VimMCPReconnect` - Reconnect to server

