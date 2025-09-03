#!/usr/bin/env node

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { CallToolRequestSchema, ListResourcesRequestSchema, ReadResourceRequestSchema, ListToolsRequestSchema } from '@modelcontextprotocol/sdk/types.js';
import net from 'net';
import fs from 'fs';
import path from 'path';

const SOCKET_PATH = '/tmp/vim-mcp-server.sock';
const REGISTRY_PATH = '/tmp/vim-mcp-registry.json';
const PREFERENCE_PATH = '/tmp/vim-mcp-preference.txt';

class VimMCPServer {
  constructor() {
    this.server = new Server({
      name: 'vim-mcp',
      version: '0.1.0',
    }, {
      capabilities: {
        resources: {},
        tools: {},
      },
    });

    this.selectedInstance = null;
    this.vimConnections = new Map(); // Map of instanceId -> {socket, state}
    this.unixServer = null;
    this.pendingExits = new Set(); // Track instances that are in the process of exiting
    this.setupHandlers();
  }

  loadRegistry() {
    try {
      if (fs.existsSync(REGISTRY_PATH)) {
        const data = fs.readFileSync(REGISTRY_PATH, 'utf8');
        return JSON.parse(data);
      }
    } catch (error) {
      console.error('Error loading registry:', error);
    }
    return {};
  }

  saveRegistry() {
    try {
      const registry = {};
      for (const [instanceId, conn] of this.vimConnections.entries()) {
        registry[instanceId] = conn.info || {
          pid: conn.pid,
          cwd: conn.cwd,
          main_file: conn.main_file,
          buffers: conn.buffers,
          started: conn.started,
          last_seen: new Date().toISOString()
        };
      }
      fs.writeFileSync(REGISTRY_PATH, JSON.stringify(registry, null, 2));
    } catch (error) {
      console.error('Error saving registry:', error);
    }
  }

  loadPreference() {
    try {
      if (fs.existsSync(PREFERENCE_PATH)) {
        return fs.readFileSync(PREFERENCE_PATH, 'utf8').trim();
      }
    } catch (error) {
      console.error('Error loading preference:', error);
    }
    return null;
  }

  savePreference(instanceId) {
    try {
      fs.writeFileSync(PREFERENCE_PATH, instanceId);
    } catch (error) {
      console.error('Error saving preference:', error);
    }
  }

  validateInstances() {
    const valid = new Map();
    for (const [id, conn] of this.vimConnections.entries()) {
      if (conn.socket && !conn.socket.destroyed) {
        valid.set(id, conn);
      } else {
        this.vimConnections.delete(id);
      }
    }
    this.vimConnections = valid;
    
    // Clean registry to only contain currently connected instances
    this.saveRegistry();
    
    return valid;
  }

  async requestVimState(instanceId) {
    const conn = this.vimConnections.get(instanceId);
    if (!conn || !conn.socket || conn.socket.destroyed) {
      throw new Error(`Instance ${instanceId} not connected`);
    }

    return new Promise((resolve, reject) => {
      const requestId = Date.now();
      const request = JSON.stringify({
        id: requestId,
        method: 'get_state',
        params: {}
      }) + '\n';

      // Set up one-time listener for this specific request
      const responseHandler = (data) => {
        try {
          const lines = data.toString().split('\n');
          for (const line of lines) {
            if (line.trim()) {
              const response = JSON.parse(line);
              if (response.id === requestId) {
                conn.socket.removeListener('data', responseHandler);
                if (response.error) {
                  reject(new Error(response.error.message));
                } else {
                  // Cache the state
                  conn.state = response.result;
                  resolve(response.result);
                }
                return;
              }
            }
          }
        } catch (e) {
          console.error('Error parsing response:', e);
        }
      };

      conn.socket.on('data', responseHandler);
      conn.socket.write(request);

      // Timeout after 2 seconds
      setTimeout(() => {
        conn.socket.removeListener('data', responseHandler);
        reject(new Error('Timeout waiting for Vim response'));
      }, 2000);
    });
  }

  async executeVimCommand(instanceId, command) {
    const conn = this.vimConnections.get(instanceId);
    if (!conn || !conn.socket || conn.socket.destroyed) {
      throw new Error(`Instance ${instanceId} not connected`);
    }

    // Check if this is an exit command
    const isExitCommand = /^(q|qa|qall|wq|wqa|wqall|q!|qa!|qall!)(\s|$)/.test(command.trim());

    return new Promise((resolve, reject) => {
      const requestId = Date.now();
      const request = JSON.stringify({
        id: requestId,
        method: 'execute_command',
        params: { command: command }
      }) + '\n';

      if (isExitCommand) {
        // Mark this instance as pending exit
        this.pendingExits.add(instanceId);
        
        // For exit commands, listen for socket closure instead of JSON response
        const closeHandler = () => {
          // Socket closed - this indicates successful exit
          conn.socket.removeListener('close', closeHandler);
          conn.socket.removeListener('error', errorHandler);
          this.pendingExits.delete(instanceId);
          resolve({
            success: true,
            output: 'Vim exited successfully',
            command: command
          });
        };

        const errorHandler = (err) => {
          conn.socket.removeListener('close', closeHandler);
          conn.socket.removeListener('error', errorHandler);
          this.pendingExits.delete(instanceId);
          reject(new Error(`Socket error during exit: ${err.message}`));
        };

        conn.socket.once('close', closeHandler);
        conn.socket.once('error', errorHandler);
        conn.socket.write(request);

        // Shorter timeout for exit commands (just waiting for socket close)
        setTimeout(() => {
          conn.socket.removeListener('close', closeHandler);
          conn.socket.removeListener('error', errorHandler);
          this.pendingExits.delete(instanceId);
          reject(new Error('Timeout waiting for Vim to exit'));
        }, 2000);
      } else {
        // Normal command execution - wait for JSON response
        const responseHandler = (data) => {
          try {
            const lines = data.toString().split('\n');
            for (const line of lines) {
              if (line.trim()) {
                const response = JSON.parse(line);
                if (response.id === requestId) {
                  conn.socket.removeListener('data', responseHandler);
                  if (response.error) {
                    reject(new Error(response.error.message));
                  } else {
                    resolve(response.result);
                  }
                  return;
                }
              }
            }
          } catch (e) {
            console.error('Error parsing response:', e);
          }
        };

        conn.socket.on('data', responseHandler);
        conn.socket.write(request);

        // Timeout after 5 seconds for command execution
        setTimeout(() => {
          conn.socket.removeListener('data', responseHandler);
          reject(new Error('Timeout waiting for command execution'));
        }, 5000);
      }
    });
  }

  startUnixServer() {
    // Clean up existing socket file
    if (fs.existsSync(SOCKET_PATH)) {
      fs.unlinkSync(SOCKET_PATH);
    }

    this.unixServer = net.createServer((socket) => {
      let buffer = '';
      let instanceId = null;

      console.error('New Vim connection via Unix socket');

      socket.on('data', (data) => {
        buffer += data.toString();
        const lines = buffer.split('\n');
        buffer = lines.pop() || '';

        for (const line of lines) {
          if (line.trim()) {
            try {
              const message = JSON.parse(line);

              // Handle registration message
              if (message.type === 'register') {
                instanceId = message.instance_id;
                this.vimConnections.set(instanceId, {
                  socket: socket,
                  info: message.info,
                  state: null,
                  pid: message.info.pid,
                  cwd: message.info.cwd,
                  main_file: message.info.main_file,
                  buffers: message.info.buffers || [],
                  started: new Date().toISOString()
                });

                console.error(`Vim instance registered: ${instanceId}`);
                this.saveRegistry();

                // Send acknowledgment
                socket.write(JSON.stringify({
                  type: 'registered',
                  instance_id: instanceId
                }) + '\n');

                // Auto-select if only one instance
                if (this.vimConnections.size === 1) {
                  this.selectedInstance = instanceId;
                  this.savePreference(instanceId);
                  console.error(`Auto-selected single Vim instance: ${instanceId}`);
                }
              }
              // Handle state updates
              else if (message.type === 'state_update' && instanceId) {
                const conn = this.vimConnections.get(instanceId);
                if (conn) {
                  conn.state = message.state;
                }
              }
            } catch (e) {
              console.error('Error parsing message from Vim:', e);
            }
          }
        }
      });

      socket.on('close', () => {
        if (instanceId) {
          const wasExpectedExit = this.pendingExits.has(instanceId);
          console.error(`Vim instance disconnected: ${instanceId}${wasExpectedExit ? ' (expected exit)' : ''}`);
          
          this.vimConnections.delete(instanceId);
          this.pendingExits.delete(instanceId);
          this.saveRegistry();

          // Clear selection if this was the selected instance
          if (this.selectedInstance === instanceId) {
            this.selectedInstance = null;
          }
        }
      });

      socket.on('error', (err) => {
        console.error('Socket error:', err);
      });
    });

    this.unixServer.listen(SOCKET_PATH, () => {
      console.error(`Unix socket server listening at ${SOCKET_PATH}`);
      // Set socket permissions to user-only
      fs.chmodSync(SOCKET_PATH, 0o600);
    });

    this.unixServer.on('error', (err) => {
      console.error('Unix socket server error:', err);
      if (err.code === 'EADDRINUSE') {
        console.error('Socket file already exists. Cleaning up and retrying...');
        if (fs.existsSync(SOCKET_PATH)) {
          fs.unlinkSync(SOCKET_PATH);
        }
        setTimeout(() => this.startUnixServer(), 1000);
      }
    });
  }

  setupHandlers() {
    // List resources
    this.server.setRequestHandler(ListResourcesRequestSchema, async () => {
      const resources = [
        {
          uri: 'vim://instances',
          mimeType: 'application/json',
          name: 'Vim Instances',
          description: 'List of all available Vim instances'
        }
      ];

      if (this.selectedInstance) {
        resources.push(
          {
            uri: 'vim://state',
            mimeType: 'application/json',
            name: 'Vim State',
            description: 'Current state of the selected Vim instance'
          },
          {
            uri: 'vim://buffers',
            mimeType: 'application/json',
            name: 'Vim Buffers',
            description: 'List of all buffers in the selected Vim instance'
          },
          {
            uri: 'vim://tabs',
            mimeType: 'application/json',
            name: 'Vim Tabs',
            description: 'List of all tabs in the selected Vim instance'
          }
        );
      }

      return { resources };
    });

    // Read resource
    this.server.setRequestHandler(ReadResourceRequestSchema, async (request) => {
      const uri = request.params.uri;

      if (uri === 'vim://instances') {
        this.validateInstances();
        const instances = {};
        for (const [id, conn] of this.vimConnections.entries()) {
          instances[id] = {
            pid: conn.pid,
            cwd: conn.cwd,
            main_file: conn.main_file,
            buffers: conn.buffers,
            connected: true
          };
        }
        return {
          contents: [{
            uri: uri,
            mimeType: 'application/json',
            text: JSON.stringify(instances, null, 2)
          }]
        };
      }

      if (!this.selectedInstance) {
        throw new Error('No Vim instance selected. Use select_vim_instance tool first.');
      }

      if (uri === 'vim://state' || uri === 'vim://buffers' || uri === 'vim://tabs') {
        try {
          const state = await this.requestVimState(this.selectedInstance);

          if (uri === 'vim://buffers') {
            return {
              contents: [{
                uri: uri,
                mimeType: 'application/json',
                text: JSON.stringify(state.buffers || [], null, 2)
              }]
            };
          }

          if (uri === 'vim://tabs') {
            return {
              contents: [{
                uri: uri,
                mimeType: 'application/json',
                text: JSON.stringify(state.tabs || [], null, 2)
              }]
            };
          }

          return {
            contents: [{
              uri: uri,
              mimeType: 'application/json',
              text: JSON.stringify(state, null, 2)
            }]
          };
        } catch (error) {
          throw new Error(`Failed to get Vim state: ${error.message}`);
        }
      }

      throw new Error(`Unknown resource: ${uri}`);
    });

    // Handle tools
    this.server.setRequestHandler(CallToolRequestSchema, async (request) => {
      const { name, arguments: args } = request.params;

      if (name === 'list_vim_instances') {
        this.validateInstances();
        const instances = [];
        for (const [id, conn] of this.vimConnections.entries()) {
          instances.push({
            id: id,
            pid: conn.pid,
            cwd: conn.cwd,
            main_file: conn.main_file || 'unnamed',
            buffers: conn.buffers || []
          });
        }

        if (instances.length === 0) {
          return {
            content: [{
              type: 'text',
              text: 'No Vim instances connected. Please open Vim with the vim-mcp plugin loaded, or run :VimMCPReconnect in existing Vim instances.'
            }]
          };
        }

        // If multiple instances, show selection prompt
        if (instances.length > 1 && !this.selectedInstance) {
          const instanceList = instances.map(i => 
            `- ${i.id} (PID: ${i.pid})\n  File: ${i.main_file}\n  CWD: ${i.cwd}`
          ).join('\n');
          
          return {
            content: [{
              type: 'text',
              text: `Found ${instances.length} Vim instance(s):\n${instanceList}\n\nPlease select an instance using select_vim_instance tool with instance_id parameter.`
            }]
          };
        }

        return {
          content: [{
            type: 'text',
            text: `Found ${instances.length} Vim instance(s):\n${instances.map(i =>
                `- ${i.id} (PID: ${i.pid})\n  File: ${i.main_file}\n  CWD: ${i.cwd}`
              ).join('\n')}`
          }]
        };
      }

      if (name === 'select_vim_instance') {
        const instanceId = args.instance_id;
        this.validateInstances();

        if (!this.vimConnections.has(instanceId)) {
          const available = Array.from(this.vimConnections.keys());
          throw new Error(`Instance '${instanceId}' not found. Available instances: ${available.join(', ') || 'none'}`);
        }

        this.selectedInstance = instanceId;
        this.savePreference(instanceId);

        const conn = this.vimConnections.get(instanceId);
        return {
          content: [{
            type: 'text',
            text: `Connected to Vim instance: ${instanceId}\nFile: ${conn.main_file || 'unnamed'}\nCWD: ${conn.cwd}`
          }]
        };
      }

      if (name === 'get_vim_state') {
        if (!this.selectedInstance) {
          throw new Error('No Vim instance selected. Use select_vim_instance tool first.');
        }

        try {
          const state = await this.requestVimState(this.selectedInstance);
          return {
            content: [{
              type: 'text',
              text: JSON.stringify(state, null, 2)
            }]
          };
        } catch (error) {
          throw new Error(`Failed to get Vim state: ${error.message}`);
        }
      }

      if (name === 'vim_execute') {
        if (!this.selectedInstance) {
          throw new Error('No Vim instance selected. Use select_vim_instance tool first.');
        }

        const command = args.command;
        if (!command) {
          throw new Error('Command parameter is required');
        }

        try {
          const result = await this.executeVimCommand(this.selectedInstance, command);
          return {
            content: [{
              type: 'text',
              text: result.output || 'Command executed successfully'
            }]
          };
        } catch (error) {
          throw new Error(`Failed to execute command: ${error.message}`);
        }
      }

      if (name === 'exit_vim') {
        if (!this.selectedInstance) {
          throw new Error('No Vim instance selected. Use select_vim_instance tool first.');
        }

        const action = args.action || 'check';

        try {
          if (action === 'check') {
            // Get current state to check for modified buffers
            const state = await this.requestVimState(this.selectedInstance);
            const modifiedBuffers = state.buffers.filter(buf => buf.modified);

            if (modifiedBuffers.length === 0) {
              // No unsaved changes, safe to exit
              await this.executeVimCommand(this.selectedInstance, 'qall');
              return {
                content: [{
                  type: 'text',
                  text: 'Vim exited successfully (no unsaved changes)'
                }]
              };
            } else {
              // Unsaved changes found
              const bufferList = modifiedBuffers.map(buf => buf.name || '[No Name]').join(', ');
              return {
                content: [{
                  type: 'text',
                  text: `Cannot exit Vim: ${modifiedBuffers.length} buffer(s) have unsaved changes: ${bufferList}\n\nOptions:\n- Save manually in Vim and run exit_vim again\n- Run exit_vim with action='save_and_exit' to save all and exit\n- Run exit_vim with action='force_exit' to exit without saving`
                }]
              };
            }
          } else if (action === 'save_and_exit') {
            await this.executeVimCommand(this.selectedInstance, 'wqall');
            return {
              content: [{
                type: 'text',
                text: 'All changes saved and Vim exited successfully'
              }]
            };
          } else if (action === 'force_exit') {
            await this.executeVimCommand(this.selectedInstance, 'qall!');
            return {
              content: [{
                type: 'text',
                text: 'Vim force exited (unsaved changes discarded)'
              }]
            };
          } else {
            throw new Error('Invalid action. Use: check, save_and_exit, or force_exit');
          }
        } catch (error) {
          throw new Error(`Failed to exit Vim: ${error.message}`);
        }
      }

      throw new Error(`Unknown tool: ${name}`);
    });

    // List tools
    this.server.setRequestHandler(ListToolsRequestSchema, async () => {
      return {
        tools: [
          {
            name: 'list_vim_instances',
            description: 'List all available Vim instances',
            inputSchema: {
              type: 'object',
              properties: {}
            }
          },
          {
            name: 'select_vim_instance',
            description: 'Select a Vim instance to connect to',
            inputSchema: {
              type: 'object',
              properties: {
                instance_id: {
                  type: 'string',
                  description: 'The ID of the Vim instance to select'
                }
              },
              required: ['instance_id']
            }
          },
          {
            name: 'get_vim_state',
            description: 'Get the current state of the selected Vim instance',
            inputSchema: {
              type: 'object',
              properties: {}
            }
          },
          {
            name: 'vim_execute',
            description: 'Execute an Ex command in the selected Vim instance',
            inputSchema: {
              type: 'object',
              properties: {
                command: {
                  type: 'string',
                  description: 'The Ex command to execute (e.g., "w", "q", "set number")'
                }
              },
              required: ['command']
            }
          },
          {
            name: 'exit_vim',
            description: 'Exit the selected Vim instance, with handling for unsaved changes',
            inputSchema: {
              type: 'object',
              properties: {
                action: {
                  type: 'string',
                  description: 'Action to take: "check" (default - check for unsaved changes), "save_and_exit" (save all and exit), "force_exit" (exit without saving)',
                  enum: ['check', 'save_and_exit', 'force_exit']
                }
              }
            }
          }
        ]
      };
    });
  }

  async start() {
    // Start Unix socket server for Vim connections
    this.startUnixServer();

    // Clean up socket on exit
    const cleanup = () => {
      if (fs.existsSync(SOCKET_PATH)) {
        fs.unlinkSync(SOCKET_PATH);
      }
    };

    process.on('SIGINT', cleanup);
    process.on('SIGTERM', cleanup);
    process.on('exit', cleanup);

    // Start MCP server
    const transport = new StdioServerTransport();
    await this.server.connect(transport);
    console.error('Vim MCP Server started');
  }
}

const server = new VimMCPServer();
server.start().catch(console.error);
