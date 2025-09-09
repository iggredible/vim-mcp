# vim-mcp

Simple MCP (Model Context Protocol) integration for Vim and Claude Code.

## Features

- Connect Claude Code to your Vim instances
- Query Vim state (buffers, windows, cursor position, etc.)
- Automatic instance selection when only one Vim is running
- Multiple Vim instance support with selection prompts

## Installation

### Prerequisites

- **Node.js** >= 18.0.0
- **Vim** 8.0+ with `+channel` feature OR **Neovim** >= 0.5
  - Check Vim: `vim --version | grep +channel`
  - Check Neovim: `nvim --version`

### Install the Vim Plugin

Using vim-plug:
```vim
Plug 'iggredible/vim-mcp'
```

Then restart Vim or run `:PlugInstall` (for vim-plug).

### Install the MCP Server

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

1. **Install Node.js dependencies**:
   ```bash
   cd ~/.vim/plugged/vim-mcp/server
   npm install
   ```

2. **Make the binary executable**:
   ```bash
   chmod +x bin/vim-mcp
   ```

3. **(Optional) Install globally for system-wide `vim-mcp` command** (inside the `/server` directory):
   ```bash
   npm install -g .
   ```
   
   If this fails due to permissions, you can either:
   - Use `sudo npm install -g .` (not recommended)
   - Skip global installation and use the full path in your config

### Configure Claude Code

After installation, add one of these configurations to your Claude Code MCP settings (`~/.claude.json`):

**If global install succeeded (if `vim-mcp` command is available):**
```json
  "mcpServers": {
    "vim-mcp": {
      "command": "vim-mcp",
      "args": []
    },
  }
```

**If global install failed (fallback):**
```json
{
  "mcpServers": {
    "vim-mcp": {
      "command": "node",
      "args": ["/path/to/vim-mcp/server/bin/vim-mcp"]
    }
  }
}
```

The install script will show you exactly which configuration to use.

## Uninstall

To remove vim-mcp:

1. **Remove the plugin from your `.vimrc`:**
   ```vim
   " Delete or comment out this line:
   " Plug 'iggredible/vim-mcp'
   ```

2. **Clean up the plugin files:**
   ```vim
   :PlugClean
   ```

3. **Remove the global `vim-mcp` command (if installed):**
   ```bash
   npm uninstall -g vim-mcp
   ```

4. **Remove from Claude Code configuration:**
   Edit `~/.claude.json` and remove the `vim-mcp` section from `mcpServers`

5. **Clean up temporary files (optional):**
   ```bash
   rm -f /tmp/vim-mcp-server.sock
   rm -f /tmp/vim-mcp-registry.json
   rm -f /tmp/vim-mcp-preference.txt
   ```

6. **Restart Vim and Claude Code** to ensure all connections are cleared.

## Quick Start

### Step-by-Step Connection Process

1. **Open Vim instances** (the plugin connects automatically):
   ```bash
   vim file1.txt    # First instance
   vim file2.txt    # Second instance (in another terminal)
   ```

2. **In Claude Code, list available Vim instances:**
   ```
   list vim instances
   ```

3. **If multiple instances are found, select one:**
   ```
   select vim instance <instance-id>
   ```

4. **Start querying your Vim state:**
   ```
   get vim state
   ```

### Basic Commands in Claude Code

1. **Instance Management:**
   - `list vim instances` - Shows all connected Vim instances
   - `select vim instance <id>` - Connect to a specific instance
   - `get vim state` - Get complete state of selected instance
   - `exit vim` - Exit Vim with proper handling of unsaved changes

2. **Vim Control:**
   - `execute vim command <ex-command>` - Execute any Ex command in Vim
   - `execute command <ex-command>` - Execute direct Ex commands (e.g., ":split", ":vsplit")
   - `exit vim` - Safely exit Vim with unsaved changes detection

3. **Query Examples:**
   - "How many buffers do I have?"
   - "What buffers are open?"
   - "What is my cursor position?"
   - "Show me the current buffer content"
   - "What windows are open?"

### Direct Ex Command Execution

The `execute command` feature allows you to run Vim Ex commands directly:

**Window Management:**
```
execute command ":split"          # Horizontal split
execute command ":vsplit"         # Vertical split  
execute command ":wincmd h"       # Move to left window
execute command ":wincmd l"       # Move to right window
```

**Tab Management:**
```
execute command ":tabnew"         # Create new tab
execute command ":tabnext"        # Switch to next tab
execute command ":tabprev"        # Switch to previous tab
execute command ":tabclose"       # Close current tab
```

**File & Settings:**
```
execute command ":w"              # Save current file
execute command ":set number"     # Show line numbers
execute command ":set hlsearch"   # Enable search highlighting
execute command ":e filename"     # Open file
```

**Buffer Operations:**
```
execute command ":bnext"          # Go to next buffer
execute command ":bprev"          # Go to previous buffer
execute command ":bdelete"        # Delete current buffer
```

### Safe Exit Feature

The `exit vim` command provides safe exit functionality with three modes:

- **Default (check)**: Checks for unsaved changes and warns you before exiting
- **Save and exit**: Saves all modified buffers and exits (`exit vim save_and_exit`)  
- **Force exit**: Exits without saving, discarding changes (`exit vim force_exit`)

Examples:
```
exit vim                    # Safe exit - warns about unsaved changes
exit vim save_and_exit     # Save all files and exit
exit vim force_exit        # Exit without saving (discard changes)
```

### Vim Commands

The plugin connects automatically when Vim opens. You can also use:

- `:VimMCPStatus` - Check connection status
- `:VimMCPConnect` - Manually connect to server
- `:VimMCPDisconnect` - Disconnect from server
- `:VimMCPReconnect` - Reconnect to server

## How It Works

1. The MCP server starts a Unix socket server at `/tmp/vim-mcp-server.sock`
2. Each Vim instance connects to the server as a Unix socket client
3. Vim sends registration and state updates to the server
4. The server maintains active connections to all Vim instances
5. Claude Code communicates with the MCP server via Model Context Protocol

## Requirements

- Vim 8+ with `+channel` feature OR Neovim 0.5+
- Node.js 18+
- Unix domain socket support (Linux/macOS)
- File system write access to `/tmp` directory
- [claude code](https://www.anthropic.com/claude-code) or similar tools that support MCP

## Troubleshooting

1. **No Vim instances found:**
   - Make sure Vim is running with the plugin loaded
   - Check `:VimMCPStatus` in Vim to see connection status
   - Run `:VimMCPReconnect` in Vim to connect to the server
   - Verify the MCP server is running: `node vim-mcp-server/index.js`

2. **Multiple Vim instances not showing up:**
   - Each Vim instance must connect to `/tmp/vim-mcp-server.sock`
   - Run `:VimMCPReconnect` in each Vim instance to refresh connection
   - Old instances may be using outdated socket paths - reconnect fixes this
   - Check `:VimMCPStatus` in each Vim to confirm connection

3. **Connection errors:**
   - Check if the MCP server is running: `node vim-mcp-server/index.js`
   - Verify the socket file exists: `ls -la /tmp/vim-mcp-server.sock`
   - Check socket file permissions: should be user-readable/writable (600)
   - Check for errors in Vim: `:messages`

4. **Clean up stale files:**
   ```bash
   rm /tmp/vim-mcp-server.sock
   rm /tmp/vim-mcp-registry.json
   ```

The server uses stdio for MCP communication and Unix domain sockets for real-time Vim communication.

