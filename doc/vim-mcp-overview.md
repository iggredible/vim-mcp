# vim-mcp: Overview

## Summary

vim-mcp provides Model Context Protocol (MCP) integration between Claude Code and Vim editor instances. The system enables Claude Code to read and manipulate Vim state through standardized MCP resources and tools, supporting multiple concurrent Vim instances with automatic instance selection and graceful connection handling.

## Architectural Overview

```
Claude Code <--[MCP/stdio]--> vim-mcp-server <--[Unix Socket]--> Vim instances
```

Components:
- **Claude Code**: MCP client that initiates all interactions
- **vim-mcp-server**: Node.js MCP server that manages Vim instances and routes commands
- **vim-mcp (plugin)**: Vim plugin that connects to the server and provides state information
- **Registry**: JSON file at `/tmp/vim-mcp-registry.json` tracking active instances

## Communication Flow

1. **Server Startup**: vim-mcp-server starts and creates Unix socket at `/tmp/vim-mcp-server.sock`
2. **Vim Registration**: Vim instances connect to the socket and send registration messages with their instance ID
3. **Command Routing**: Claude sends MCP commands → server routes to selected Vim instance → returns results
4. **State Synchronization**: Vim instances push state updates on buffer/window changes; server pulls state on MCP resource requests

## Protocols

### MCP Protocol (Claude Code ↔ vim-mcp-server)
- **Transport**: stdio (stdin/stdout)
- **Encoding**: JSON-RPC 2.0
- **Protocol**: Model Context Protocol v1.0

### Unix Socket Protocol (vim-mcp-server ↔ Vim)
- **Transport**: Unix domain sockets
- **Socket Path**: `/tmp/vim-mcp-server.sock`
- **Encoding**: Newline-delimited JSON messages
- **Message Types**: register, get_state, execute_command, and their responses

## MCP Resources and Tools

### MCP Resources

| URI | Description | Availability |
|-----|-------------|--------------|
| `vim://instances` | List of all Vim instances | Always |
| `vim://state` | Complete state of selected instance | When connected |
| `vim://buffers` | All buffers information | When connected |
| `vim://tabs` | All tabs information | When connected |

### MCP Tools

Instance Management:
- **list_vim_instances**: List all connected instances
- **select_vim_instance**: Connect to specific instance by ID

Vim Interaction:
- **vim_execute**: Execute Ex commands in Vim
- **exit_vim**: Exit Vim with unsaved changes handling
- **get_vim_state**: Get current Vim state

