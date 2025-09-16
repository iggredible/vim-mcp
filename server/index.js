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

    if (isExitCommand) {
      // Handle exit commands with socket closure detection
      return this.executeExitCommand(instanceId, command);
    }

    // For normal commands, use state-based verification
    return this.executeCommandWithStateVerification(instanceId, command);
  }

  async executeExitCommand(instanceId, command) {
    const conn = this.vimConnections.get(instanceId);

    return new Promise((resolve, reject) => {
      const requestId = Date.now();
      const request = JSON.stringify({
        id: requestId,
        method: 'execute_command',
        params: { command: command }
      }) + '\n';

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

      // Timeout for exit commands
      setTimeout(() => {
        conn.socket.removeListener('close', closeHandler);
        conn.socket.removeListener('error', errorHandler);
        this.pendingExits.delete(instanceId);
        reject(new Error('Timeout waiting for Vim to exit'));
      }, 2000);
    });
  }

  async executeCommandWithStateVerification(instanceId, command) {
    const conn = this.vimConnections.get(instanceId);

    // Get state before command execution
    let beforeState;
    try {
      beforeState = await this.requestVimState(instanceId);
    } catch (error) {
      throw new Error(`Failed to get state before command: ${error.message}`);
    }

    // Send command to Vim (fire and forget)
    const requestId = Date.now();
    const request = JSON.stringify({
      id: requestId,
      method: 'execute_command',
      params: { command: command }
    }) + '\n';

    conn.socket.write(request);

    // Wait briefly for command to process, then verify state
    return new Promise((resolve, reject) => {
      setTimeout(async () => {
        try {
          // Get state after command execution
          const afterState = await this.requestVimState(instanceId);

          // Verify the command worked by comparing states
          const verification = this.verifyCommandExecution(command, beforeState, afterState);

          if (verification.success) {
            resolve({
              success: true,
              output: verification.message,
              command: command,
              state_changed: true,
              before_state: beforeState,
              after_state: afterState
            });
          } else {
            reject(new Error(`Command verification failed: ${verification.message}`));
          }
        } catch (error) {
          reject(new Error(`Failed to verify command execution: ${error.message}`));
        }
      }, 500); // Wait 500ms for command to process
    });
  }

  verifyCommandExecution(command, beforeState, afterState) {
    const cmd = command.trim().toLowerCase();

    // Window splitting commands
    if (cmd === 'split' || cmd.startsWith('split ')) {
      const beforeWindows = beforeState.windows ? beforeState.windows.length : 0;
      const afterWindows = afterState.windows ? afterState.windows.length : 0;

      if (afterWindows > beforeWindows) {
        return {
          success: true,
          message: `Window split successful. Windows increased from ${beforeWindows} to ${afterWindows}.`
        };
      }
      return {
        success: false,
        message: `Window split may have failed. Window count unchanged: ${beforeWindows}.`
      };
    }

    if (cmd === 'vsplit' || cmd.startsWith('vsplit ')) {
      const beforeWindows = beforeState.windows ? beforeState.windows.length : 0;
      const afterWindows = afterState.windows ? afterState.windows.length : 0;

      if (afterWindows > beforeWindows) {
        return {
          success: true,
          message: `Vertical split successful. Windows increased from ${beforeWindows} to ${afterWindows}.`
        };
      }
      return {
        success: false,
        message: `Vertical split may have failed. Window count unchanged: ${beforeWindows}.`
      };
    }

    // Tab commands
    if (cmd === 'tabnew' || cmd.startsWith('tabnew ')) {
      const beforeTabs = beforeState.tabs ? beforeState.tabs.length : 0;
      const afterTabs = afterState.tabs ? afterState.tabs.length : 0;

      if (afterTabs > beforeTabs) {
        return {
          success: true,
          message: `New tab created successfully. Tabs increased from ${beforeTabs} to ${afterTabs}.`
        };
      }
      return {
        success: false,
        message: `Tab creation may have failed. Tab count unchanged: ${beforeTabs}.`
      };
    }

    if (cmd === 'tabnext' || cmd === 'tabprevious') {
      const beforeActiveTab = beforeState.tabs ? beforeState.tabs.findIndex(t => t.active) : -1;
      const afterActiveTab = afterState.tabs ? afterState.tabs.findIndex(t => t.active) : -1;

      if (beforeActiveTab !== afterActiveTab) {
        return {
          success: true,
          message: `Tab navigation successful. Active tab changed from ${beforeActiveTab + 1} to ${afterActiveTab + 1}.`
        };
      }
      return {
        success: false,
        message: `Tab navigation may have failed or already at ${cmd === 'tabnext' ? 'last' : 'first'} tab.`
      };
    }

    // File operations
    if (cmd.startsWith('edit ') || cmd.startsWith('e ')) {
      const filename = cmd.split(' ')[1];
      const afterBuffer = afterState.current_buffer;

      if (afterBuffer && (afterBuffer.name.endsWith(filename) || afterBuffer.name.includes(filename))) {
        return {
          success: true,
          message: `File opened successfully: ${afterBuffer.name}`
        };
      }
      return {
        success: false,
        message: `File opening may have failed. Current buffer: ${afterBuffer ? afterBuffer.name : 'unknown'}`
      };
    }

    // Settings commands
    if (cmd.startsWith('set ')) {
      // For settings commands, assume success if no error occurred
      return {
        success: true,
        message: `Setting command executed: ${command}`
      };
    }

    // Window navigation commands
    if (cmd.startsWith('wincmd ')) {
      // Check if current window/cursor changed
      const beforeCursor = beforeState.cursor || [0, 0];
      const afterCursor = afterState.cursor || [0, 0];
      const beforeCurrentBuf = beforeState.current_buffer ? beforeState.current_buffer.id : null;
      const afterCurrentBuf = afterState.current_buffer ? afterState.current_buffer.id : null;

      if (beforeCurrentBuf !== afterCurrentBuf) {
        return {
          success: true,
          message: `Window navigation successful. Moved to buffer ${afterCurrentBuf}.`
        };
      }
      return {
        success: true,
        message: `Window navigation command executed: ${command}`
      };
    }

    // Write/save commands
    if (cmd === 'w' || cmd === 'write') {
      const afterBuffer = afterState.current_buffer;
      if (afterBuffer && !afterBuffer.modified) {
        return {
          success: true,
          message: `File saved successfully: ${afterBuffer.name || '[No Name]'}`
        };
      }
      return {
        success: true,
        message: `Write command executed: ${command}`
      };
    }

    // Generic fallback - assume success if state is retrievable
    return {
      success: true,
      message: `Command executed successfully: ${command}`
    };
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

      if (name === 'vim_search_help') {
        if (!this.selectedInstance) {
          throw new Error('No Vim instance selected. Use select_vim_instance tool first.');
        }

        const query = args.query;
        if (!query) {
          throw new Error('Query parameter is required');
        }

        try {
          const conn = this.vimConnections.get(this.selectedInstance);
          if (!conn || !conn.socket || conn.socket.destroyed) {
            throw new Error(`Instance ${this.selectedInstance} not connected`);
          }

          return new Promise((resolve, reject) => {
            const requestId = Date.now();
            const request = JSON.stringify({
              id: requestId,
              method: 'search_help',
              params: { query: query }
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
                        const result = response.result;
                        if (result.success) {
                          resolve({
                            content: [{
                              type: 'text',
                              text: `Found help for '${query}':\n\nTag: ${result.tag}\nFile: ${result.file}\nLine: ${result.line}\n\nHelp window opened in Vim.`
                            }]
                          });
                        } else {
                          resolve({
                            content: [{
                              type: 'text',
                              text: `No help found for '${query}'. Try:\n- A more specific search term\n- Using :helpgrep in Vim for pattern search\n- Checking available help tags with :help`
                            }]
                          });
                        }
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

            // Timeout after 3 seconds
            setTimeout(() => {
              conn.socket.removeListener('data', responseHandler);
              reject(new Error('Timeout waiting for help search response'));
            }, 3000);
          });
        } catch (error) {
          throw new Error(`Failed to search help: ${error.message}`);
        }
      }

      if (name === 'vim_record_macro') {
        if (!this.selectedInstance) {
          throw new Error('No Vim instance selected. Use select_vim_instance tool first.');
        }

        const macroSequence = args.macro_sequence;
        const register = args.register || 'q';
        const execute = args.execute !== false; // Default true

        if (!macroSequence) {
          throw new Error('macro_sequence parameter is required');
        }

        // Validate register name
        if (!/^[a-z0-9]$/i.test(register)) {
          throw new Error('Register must be a single letter (a-z) or digit (0-9)');
        }

        try {
          const conn = this.vimConnections.get(this.selectedInstance);
          if (!conn || !conn.socket || conn.socket.destroyed) {
            throw new Error(`Instance ${this.selectedInstance} not connected`);
          }

          return new Promise((resolve, reject) => {
            const requestId = Date.now();
            const request = JSON.stringify({
              id: requestId,
              method: 'record_macro',
              params: {
                macro_sequence: macroSequence,
                register: register,
                execute: execute
              }
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
                        const result = response.result;
                        if (result.success) {
                          let message = `Macro recorded in register "${register}"`;
                          if (execute) {
                            message += ' and executed';
                          }
                          message += `\nSequence: ${macroSequence}`;
                          if (result.output) {
                            message += `\n${result.output}`;
                          }
                          resolve({
                            content: [{
                              type: 'text',
                              text: message
                            }]
                          });
                        } else {
                          resolve({
                            content: [{
                              type: 'text',
                              text: `Failed to record macro: ${result.error || 'Unknown error'}`
                            }]
                          });
                        }
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
              reject(new Error('Timeout waiting for macro recording response'));
            }, 2000);
          });
        } catch (error) {
          throw new Error(`Failed to record macro: ${error.message}`);
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
          },
          {
            name: 'vim_search_help',
            description: 'Search Vim help documentation for a topic and open the most relevant help section',
            inputSchema: {
              type: 'object',
              properties: {
                query: {
                  type: 'string',
                  description: 'The help topic to search for (e.g., "channel", "buffers", "windows")'
                }
              },
              required: ['query']
            }
          },
          {
            name: 'vim_record_macro',
            description: 'Record a Vim macro from a sequence of keystrokes. Claude will translate natural language descriptions to Vim commands.',
            inputSchema: {
              type: 'object',
              properties: {
                macro_sequence: {
                  type: 'string',
                  description: 'The Vim keystroke sequence to record as a macro (e.g., "0gUwj2j" to go to start of line, uppercase word, go down 3 lines)'
                },
                register: {
                  type: 'string',
                  description: 'Register to save the macro in (default: "q"). Must be a single letter a-z or digit 0-9'
                },
                execute: {
                  type: 'boolean',
                  description: 'Whether to execute the macro immediately after recording (default: true)'
                }
              },
              required: ['macro_sequence']
            }
          }
        ]
      };
    });
  }

  async start() {
    // Start Unix socket server for Vim connections
    this.startUnixServer();

    // Enhanced cleanup function
    let cleanup = (signal) => {
      console.error(`Received ${signal}, shutting down vim-mcp-server...`);

      // Close all Vim connections
      for (const [instanceId, conn] of this.vimConnections.entries()) {
        if (conn.socket && !conn.socket.destroyed) {
          conn.socket.destroy();
        }
      }
      this.vimConnections.clear();

      // Close Unix server
      if (this.unixServer) {
        this.unixServer.close();
      }

      // Clean up socket file
      if (fs.existsSync(SOCKET_PATH)) {
        fs.unlinkSync(SOCKET_PATH);
      }

      // Clean up registry and preference files
      if (fs.existsSync(REGISTRY_PATH)) {
        fs.unlinkSync(REGISTRY_PATH);
      }
      if (fs.existsSync(PREFERENCE_PATH)) {
        fs.unlinkSync(PREFERENCE_PATH);
      }

      console.error('vim-mcp-server shutdown complete');
      process.exit(0);
    };

    // Handle various exit scenarios
    process.on('SIGINT', () => cleanup('SIGINT'));
    process.on('SIGTERM', () => cleanup('SIGTERM'));
    process.on('SIGHUP', () => cleanup('SIGHUP'));

    // Handle uncaught exceptions and unhandled rejections
    process.on('uncaughtException', (err) => {
      console.error('Uncaught exception:', err);
      cleanup('uncaughtException');
    });

    process.on('unhandledRejection', (reason, promise) => {
      console.error('Unhandled rejection at:', promise, 'reason:', reason);
      cleanup('unhandledRejection');
    });

    // Handle stdin closure (when parent process closes stdio)
    process.stdin.on('end', () => {
      console.error('stdin closed, parent process likely died');
      cleanup('stdin_closed');
    });

    process.stdin.on('error', (err) => {
      console.error('stdin error:', err);
      cleanup('stdin_error');
    });

    // Start MCP server
    const transport = new StdioServerTransport();
    await this.server.connect(transport);
    console.error('Vim MCP Server started');
  }
}

const server = new VimMCPServer();
server.start().catch(console.error);
