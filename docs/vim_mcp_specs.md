# vim-mcp: Technical Specification

**Version**: 1.0.0  
**Status**: Draft  
**Date**: January 2024  
**Authors**: vim-mcp contributors

## 1. Introduction

### 1.1 Purpose
This specification defines the vim-mcp system, which provides Model Context Protocol (MCP) integration between Claude Code and Vim editor instances, enabling Claude Code to read and manipulate Vim state through standardized MCP resources and tools.

### 1.2 Scope
This document specifies:
- System architecture and components
- Communication protocols
- Data formats and schemas
- Instance management behavior
- Error handling requirements
- Security considerations

### 1.3 Goals
- **G1**: Enable Claude Code to interact with Vim editor state
- **G2**: Support multiple concurrent Vim instances
- **G3**: Provide automatic instance selection when unambiguous
- **G4**: Maintain zero configuration for single-instance use cases
- **G5**: Ensure graceful handling of connection failures

### 1.4 Non-Goals
- Direct Vim-to-Vim communication
- Vim plugin management
- File system operations outside of Vim buffers
- Support for editors other than Vim/Neovim

## 2. Architecture Overview

### 2.1 Components

```
Component         | Responsibility                           | Language
------------------|------------------------------------------|----------
Claude Code       | MCP client, user interface              | (Anthropic)
vim-mcp-server    | MCP server, instance management         | JavaScript/Node.js
vim-mcp.vim       | Vim plugin, state provider              | VimScript
Registry          | Instance tracking                       | JSON file
```

### 2.2 Communication Topology

```
Claude Code <--[MCP/stdio]--> vim-mcp-server <--[Unix Socket]--> Vim instances
                                    |
                                    v
                              [Registry File]
```

## 3. Protocols

### 3.1 MCP Protocol (Claude Code ↔ vim-mcp-server)

**Transport**: stdio (stdin/stdout)  
**Encoding**: JSON-RPC 2.0  
**Protocol**: Model Context Protocol v1.0

### 3.2 Vim Protocol (vim-mcp-server ↔ Vim)

**Transport**: Unix domain sockets (server-client)  
**Socket Path**: `/tmp/vim-mcp-server.sock` (configurable)  
**Encoding**: JSON messages, newline-delimited

#### 3.2.1 Message Types

##### Registration Message (Vim → Server)
```json
{
  "type": "register",
  "instance_id": "string",
  "info": {
    "pid": "number",
    "cwd": "string",
    "main_file": "string",
    "buffers": ["string"],
    "version": "string"
  }
}
```

##### Registration Acknowledgment (Server → Vim)
```json
{
  "type": "registered",
  "instance_id": "string"
}
```

##### State Request (Server → Vim)
```json
{
  "id": "number",
  "method": "get_state",
  "params": {}
}
```

##### State Response (Vim → Server)
```json
{
  "id": "number",
  "result": {
    "current_buffer": {
      "id": "number",
      "name": "string",
      "filetype": "string",
      "content": ["string"],
      "line_count": "number",
      "modified": "boolean"
    },
    "windows": ["object"],
    "buffers": ["object"],
    "cursor": ["number"],
    "mode": "string",
    "cwd": "string"
  }
}
```

## 4. Data Formats

### 4.1 Instance Registry

**Location**: `/tmp/vim-mcp-registry.json`  
**Format**: JSON object with instance_id keys  
**Note**: Registry is automatically cleaned to contain only currently connected instances

```json
{
  "{instance_id}": {
    "socket": "string (legacy, unused - all instances use /tmp/vim-mcp-server.sock)",
    "pid": "number",
    "cwd": "string (working directory)",
    "main_file": "string (primary file path)",
    "started": "string (ISO 8601 timestamp)",
    "buffers": ["string (buffer names)"],
    "last_seen": "string (ISO 8601 timestamp)"
  }
}
```

### 4.4 State Files

**Location Pattern**: `/tmp/vim-mcp-{instance_id}-state.json`  
**Format**: JSON object containing complete Vim state  
**Update Frequency**: Every 1 second (configurable via timer)

### 4.2 Instance ID Format

```
{filename}-{project}-{pid}
```

**Components**:
- `filename`: Base name of primary file without extension (or "unnamed")
- `project`: Directory name of Git root or CWD
- `pid`: Process ID of Vim instance

**Examples**:
- `index-myproject-12345`
- `unnamed-dotfiles-67890`
- `server-api-23456`

### 4.3 Preference Storage

**Location**: `/tmp/vim-mcp-preference.txt`  
**Format**: Plain text, single line containing last selected instance_id

## 5. MCP Resources

### 5.1 Resource Definitions

| URI | Description | MIME Type | Availability |
|-----|-------------|-----------|--------------|
| `vim://instances` | List of all Vim instances | application/json | Always |
| `vim://state` | Complete state of selected instance | application/json | When connected |
| `vim://buffer/current` | Current buffer content | text/plain | When connected |
| `vim://buffers` | All buffers information | application/json | When connected |
| `vim://windows` | Window layout information | application/json | When connected |
| `vim://diagnostics` | LSP diagnostics | application/json | When connected |
| `vim://cursor` | Cursor position and context | application/json | When connected |

## 6. MCP Tools

### 6.1 Tool Definitions

#### Instance Management Tools

| Tool | Parameters | Description | Availability |
|------|-----------|-------------|--------------|
| `list_vim_instances` | none | List all connected instances with selection prompt | Always |
| `select_vim_instance` | instance_id: string | Connect to specific instance | Always |

#### Vim Interaction Tools

| Tool | Parameters | Description | Availability |
|------|-----------|-------------|--------------|
| `vim_execute` | command: string | Execute Ex command | When connected |
| `vim_edit` | file: string, line?: number, column?: number, content?: string | Edit file | When connected |
| `vim_search` | pattern: string, scope?: 'current'\|'all' | Search in buffers | When connected |
| `vim_navigate` | direction: string, count?: number | Navigate in buffer | When connected |
| `vim_get_diagnostics` | buffer?: number | Get LSP diagnostics | When connected |

## 7. Behavior Specifications

### 7.1 Instance Selection Algorithm

```
START
  │
  ├─> Validate active connections (check socket status)
  ├─> Count active instances
  │
  ├─> IF instances == 0:
  │     └─> Return "No instances found, run :VimMCPReconnect in Vim"
  │
  ├─> IF instances == 1:
  │     └─> AUTO-CONNECT to single instance
  │
  └─> IF instances > 1:
        ├─> IF no instance selected:
        │     └─> PROMPT for selection with instance list
        └─> ELSE:
              └─> Use current selection
```

**Key Changes from v1.0**:
- Registry is cleaned automatically to only contain connected instances
- Selection algorithm prioritizes active socket connections over registry entries
- Improved user messaging for reconnection instructions

### 7.2 Connection Lifecycle

#### 7.2.1 Server Startup
1. Claude Code launches vim-mcp-server via MCP configuration
2. Server initializes MCP protocol handler
3. Server starts Unix socket server at /tmp/vim-mcp-server.sock
4. Server loads and validates registry

#### 7.2.2 Vim Connection
1. Vim starts and loads vim-mcp plugin
2. Plugin generates instance_id
3. Plugin connects to Unix socket at /tmp/vim-mcp-server.sock
4. Plugin sends registration message with instance information
5. Server acknowledges registration and stores connection
6. Plugin sends state updates on buffer/window changes

#### 7.2.3 Disconnection Handling
1. On Vim exit: Close Unix socket connection, server removes from registry
2. On server crash: Vim detects connection loss, attempts reconnection every 5 seconds
3. On Vim crash: Server detects closed socket, removes instance from registry
4. **Registry Cleanup**: Registry is automatically cleaned during validation to contain only active connections

### 7.3 State Synchronization

**Push Events** (Vim → Server):
- Buffer change
- Window change  
- Mode change
- File save

**Pull Triggers** (Server → Vim):
- MCP resource read request
- MCP tool execution
- Periodic refresh (optional, configurable)

## 8. Error Handling

### 8.1 Error Conditions

| Condition | Detection | Recovery |
|-----------|-----------|----------|
| No Vim instances | Empty connections map | Wait and inform user |
| Vim instance crash | Socket closed event | Remove from registry |
| Server crash | Connection refused | Vim retries every 5 seconds |
| Socket errors | Unix socket errors | Automatic reconnection |
| Socket file issues | Server bind fails | Clean up and retry |
| Registry corruption | JSON parse error | Reset registry file |

### 8.2 Error Response Format

```json
{
  "error": {
    "code": "number",
    "message": "string",
    "data": {
      "instance_id": "string (optional)",
      "original_error": "string (optional)"
    }
  }
}
```

### 8.3 Error Codes

| Code | Description |
|------|-------------|
| -32600 | Invalid request |
| -32601 | Method not found |
| -32602 | Invalid parameters |
| -32603 | Internal error |
| 1001 | No Vim instance selected |
| 1002 | Vim instance not found |
| 1003 | Vim connection lost |
| 1004 | Command execution failed |

## 9. Security Considerations

### 9.1 File System Security
- Unix socket created with user-only permissions (0600)
- Socket file located in /tmp with server-specific naming
- Registry file created with user-only permissions (0600)
- No network exposure (purely local file system communication)

### 9.2 Command Injection Prevention
- All Vim commands must be validated before execution
- No shell command execution from user input
- File paths must be sanitized

### 9.3 Resource Limits
- Maximum buffer content size: 10MB
- Maximum number of tracked instances: 100
- Connection timeout: 5 seconds
- Registry cleanup: Remove entries older than 24 hours

## 10. Configuration

### 10.1 Claude Code Configuration

**File**: `~/.config/claude-code/mcp-servers.json`

```json
{
  "mcpServers": {
    "vim-mcp": {
      "command": "node",
      "args": ["/absolute/path/to/vim-mcp-server.js"],
      "env": {
        "VIM_MCP_REGISTRY": "/tmp/vim-mcp-registry.json",
        "VIM_MCP_LOG_LEVEL": "info"
      }
    }
  }
}
```

### 10.2 Vim Configuration

```vim
" Required settings
let g:vim_mcp_enabled = 1

" Optional settings
let g:vim_mcp_socket_path = '/tmp/vim-mcp-server.sock'
let g:vim_mcp_reconnect_interval = 5000
let g:vim_mcp_state_push_events = ['BufEnter', 'BufWrite', 'WinEnter']
```

## 11. Implementation Requirements

### 11.1 vim-mcp-server Requirements
- Node.js >= 18.0.0
- @modelcontextprotocol/sdk >= 1.0.0
- Platform: Linux, macOS (Unix domain sockets)
- File system write access to /tmp directory

### 11.2 vim-mcp.vim Requirements
- Vim >= 8.0 with +channel feature OR Neovim >= 0.5
- Unix domain socket support (built into Vim channels)
- JSON encoding/decoding support (built-in)

### 11.3 Performance Requirements
- Instance selection: < 100ms
- State query response: < 200ms  
- Command execution: < 500ms
- Registry update: < 50ms

## 12. Testing Requirements

### 12.1 Unit Tests
- Instance ID generation
- Registry management
- Message parsing
- Error handling

### 12.2 Integration Tests
- Single instance connection
- Multiple instance selection
- Disconnection/reconnection
- Command execution
- State synchronization

### 12.3 End-to-End Tests
- Claude Code → Vim workflow
- Multiple Vim instance workflow
- Crash recovery scenarios
- Performance benchmarks

## 13. Future Considerations

### 13.1 Potential Extensions
- Windows support (named pipes)
- Remote Vim support (TCP sockets)
- Vim plugin marketplace integration
- Custom tool registration from Vim plugins
- Bi-directional Claude Code invocation from Vim

### 13.2 Version 2.0 Considerations
- Binary protocol for performance
- Incremental state updates
- Multiple selection support
- Project-aware instance grouping
- Persistent instance preferences per project

## 14. References

- [Model Context Protocol Specification](https://modelcontextprotocol.io/docs)
- [Vim Channel Documentation](https://vimhelp.org/channel.txt.html)
- [Neovim API Documentation](https://neovim.io/doc/user/api.html)
- [JSON-RPC 2.0 Specification](https://www.jsonrpc.org/specification)

## Appendix A: Complete Message Flow Example

```
User: "What buffers are open in Vim?"

1. Claude Code → vim-mcp-server [MCP]
   {"method": "resources/read", "params": {"uri": "vim://buffers"}}

2. vim-mcp-server: Check selected instance
   (If none selected, initiate selection flow)

3. vim-mcp-server → Vim [Unix Socket]
   {"id": 1, "method": "get_state", "params": {}}

4. Vim → vim-mcp-server [Unix Socket]
   {"id": 1, "result": {"buffers": [...]}}

5. vim-mcp-server → Claude Code [MCP]
   {"result": {"contents": [{"text": "..."}]}}

6. Claude Code → User
   "You have 3 buffers open: main.py, test.py, and README.md"
```

## Appendix B: Status Codes

| Status | Description |
|--------|-------------|
| READY | Server initialized and listening |
| CONNECTED | At least one Vim instance connected |
| WAITING | No Vim instances available |
| ERROR | Unrecoverable error state |

---

**END OF SPECIFICATION**
