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

## Usage

### Basic Commands in Claude Code

1. **Connect to Vim:**
   - "Connect to Vim" - Connects to a Vim instance (auto-selects if only one)
   - "List Vim instances" - Shows all available Vim instances
   - "Select vim instance [id]" - Connect to a specific instance

2. **Query Vim State:**
   - "How many buffers do I have?"
   - "What buffers are open?"
   - "What is my cursor position?"
   - "Show me the current buffer content"
   - "What windows are open?"

### Vim Commands

The plugin starts automatically when Vim opens. You can also use:

- `:VimMCPStatus` - Check if the plugin is running
- `:VimMCPRestart` - Restart the MCP connection
- `:VimMCPStop` - Stop the MCP server

## How It Works

1. Each Vim instance creates a state file at `/tmp/vim-mcp-{instance-id}-state.json`
2. Vim registers itself in `/tmp/vim-mcp-registry.json`
3. Vim continuously updates its state file (every 1 second)
4. The MCP server reads state files directly to query Vim state
5. Claude Code communicates with the MCP server via Model Context Protocol

## Requirements

- Vim 8+ OR Neovim 0.5+
- Node.js 18+
- File system access to `/tmp` directory
- Cross-platform compatible (Linux/macOS/Windows)

## Troubleshooting

1. **No Vim instances found:**
   - Make sure Vim is running with the plugin loaded
   - Check `:VimMCPStatus` in Vim
   - Verify the state file exists: `ls /tmp/vim-mcp-*-state.json`

2. **State reading errors:**
   - Check the registry file: `cat /tmp/vim-mcp-registry.json`
   - Check the state file: `cat /tmp/vim-mcp-{instance-id}-state.json`
   - Restart the Vim plugin: `:VimMCPRestart`
   - Check for errors in Vim: `:messages`

3. **Clean up stale files:**
   ```bash
   rm /tmp/vim-mcp-*-state.json
   rm /tmp/vim-mcp-registry.json
   ```

## Development

To run the MCP server directly:

```bash
cd vim-mcp-server
node index.js
```

The server uses stdio for MCP communication and reads JSON state files for Vim state.

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