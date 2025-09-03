# vim-mcp

Simple MCP (Model Context Protocol) integration for Vim and Claude Code.

## Features

- Connect Claude Code to your Vim instances
- Query Vim state (buffers, windows, cursor position, etc.)
- Automatic instance selection when only one Vim is running
- Multiple Vim instance support with selection prompts

## Installation

### 1. Install the Vim Plugin

Add to your `.vimrc` using your preferred plugin manager:

```vim
" Using vim-plug
Plug '~/Project/vim-mcp2/vim-mcp-plugin'

" Or manually copy vim-mcp.vim to ~/.vim/plugin/
```

### 2. Install Node.js Dependencies

```bash
cd ~/Project/vim-mcp2/vim-mcp-server
npm install
```

### 3. Configure Claude Code

Add to your Claude Code MCP settings (`~/.config/claude-code/mcp-servers.json`):

```json
{
  "mcpServers": {
    "vim-mcp": {
      "command": "node",
      "args": ["/Users/iirianto/Project/vim-mcp2/vim-mcp-server/index.js"]
    }
  }
}
```

## Quick Start

### Step-by-Step Connection Process

1. **Start the MCP server** (run this once):
   ```bash
   cd vim-mcp-server
   node index.js
   ```

2. **Open Vim instances** (the plugin connects automatically):
   ```bash
   vim file1.txt    # First instance
   vim file2.txt    # Second instance (in another terminal)
   ```

3. **In Claude Code, list available Vim instances:**
   ```
   list vim instances
   ```

4. **If multiple instances are found, select one:**
   ```
   select vim instance <instance-id>
   ```

5. **Start querying your Vim state:**
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
   - `execute command <description>` - Execute natural language commands (NEW!)
   - `exit vim` - Safely exit Vim with unsaved changes detection
   - Examples: "save file", "set line numbers", "quit vim"

3. **Query Examples:**
   - "How many buffers do I have?"
   - "What buffers are open?"
   - "What is my cursor position?"
   - "Show me the current buffer content"
   - "What windows are open?"

### Natural Language Commands with Intelligent Execution (ENHANCED!)

The `execute command` feature uses intelligent natural language processing to understand your intent and convert it to Vim commands. It now includes state verification to confirm commands executed successfully:

**Flexible Phrasing - All of these work:**
```
execute command "split vim into 4 equal windows"
execute command "divide the screen into 4 parts"  
execute command "make 4 window sections"
execute command "create 4 equal panes"
```

**Window Management:**
```
execute command "split the window vertically"
execute command "make a horizontal split"
execute command "go to the left window"
execute command "move to the window on the right"
```

**Tab Management:**
```
execute command "create 3 new tabs"
execute command "open foo.md, bar.md, and baz.md in separate tabs"
execute command "switch to next tab"
execute command "close this tab"
```

**File & Settings:**
```
execute command "save the current file"
execute command "turn on line numbers"
execute command "enable search highlighting"
execute command "open the file called example.txt"
```

**Buffer Operations:**
```
execute command "go to next buffer"
execute command "switch to previous buffer"
execute command "close current buffer"
```

**Enhanced Features:**
- **State Verification**: Automatically verifies commands worked by comparing Vim state before/after execution
- **Smart Understanding**: Handles typos and variations in phrasing
- **Context Awareness**: Understands intent and can interpret complex multi-step requests
- **Safety Validation**: Only allows safe, whitelisted Vim commands with dangerous command blocking
- **Detailed Feedback**: Shows exactly which Vim commands were executed and verification results
- **Exit Command Handling**: Special handling for quit commands with proper socket closure detection
- **Multi-Command Execution**: Automatically breaks down complex requests into multiple Vim commands

**Verification Examples:**
When you run `execute command "split vim into 4 equal windows"`, you'll see:
```
> split
Window split successful. Windows increased from 1 to 2.

> vsplit  
Vertical split successful. Windows increased from 2 to 3.

> wincmd k
Window navigation command executed: wincmd k

> vsplit
Vertical split successful. Windows increased from 3 to 4.
```

**Safety & Reliability:**
- Commands are validated against a whitelist of safe Vim Ex commands
- Dangerous operations like shell execution, file deletion are blocked
- State verification ensures commands actually worked as expected
- Clear error messages for invalid or unsupported requests

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

## Development

To run the MCP server directly:

```bash
cd vim-mcp-server
node index.js
```

The server uses stdio for MCP communication and Unix domain sockets for real-time Vim communication.

## Project Structure

```
vim-mcp2/
├── vim-mcp-plugin/          # Vim plugin directory
│   └── vim-mcp.vim         # VimScript plugin file
├── vim-mcp-server/          # Node.js MCP server
│   ├── index.js            # Main server file
│   ├── package.json        # Node.js dependencies
│   └── package-lock.json   # Dependency lock file
├── docs/                    # Documentation
└── README.md               # This file
```
