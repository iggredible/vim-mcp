#!/usr/bin/env node

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { CallToolRequestSchema, ListResourcesRequestSchema, ReadResourceRequestSchema, ListToolsRequestSchema } from '@modelcontextprotocol/sdk/types.js';
import fs from 'fs';
import path from 'path';

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

  validateInstances(registry) {
    const valid = {};
    for (const [id, info] of Object.entries(registry)) {
      try {
        // Check if process is still running
        process.kill(info.pid, 0);
        valid[id] = info;
      } catch {
        // Process doesn't exist, skip this instance
      }
    }
    return valid;
  }

  async getVimState(instanceId) {
    const registry = this.loadRegistry();
    const instance = registry[instanceId];

    if (!instance) {
      throw new Error(`Instance ${instanceId} not found`);
    }

    // Read state from file instead of socket
    const statePath = `/tmp/vim-mcp-${instanceId}-state.json`;
    
    try {
      if (!fs.existsSync(statePath)) {
        throw new Error(`State file not found: ${statePath}`);
      }
      
      const stateData = fs.readFileSync(statePath, 'utf8');
      return JSON.parse(stateData);
    } catch (error) {
      throw new Error(`Failed to read Vim state: ${error.message}`);
    }
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
          }
        );
      }

      return { resources };
    });

    // Read resource
    this.server.setRequestHandler(ReadResourceRequestSchema, async (request) => {
      const uri = request.params.uri;

      if (uri === 'vim://instances') {
        const registry = this.validateInstances(this.loadRegistry());
        return {
          contents: [{
            uri: uri,
            mimeType: 'application/json',
            text: JSON.stringify(registry, null, 2)
          }]
        };
      }

      if (!this.selectedInstance) {
        throw new Error('No Vim instance selected. Use select_vim_instance tool first.');
      }

      if (uri === 'vim://state' || uri === 'vim://buffers') {
        try {
          const state = await this.getVimState(this.selectedInstance);

          if (uri === 'vim://buffers') {
            return {
              contents: [{
                uri: uri,
                mimeType: 'application/json',
                text: JSON.stringify(state.buffers || [], null, 2)
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
        const registry = this.validateInstances(this.loadRegistry());
        const instances = Object.entries(registry).map(([id, info]) => ({
          id: id,
          pid: info.pid,
          cwd: info.cwd,
          main_file: info.main_file || 'unnamed',
          buffers: info.buffers || []
        }));

        return {
          content: [{
            type: 'text',
            text: instances.length === 0
              ? 'No Vim instances found. Please open Vim with the vim-mcp plugin loaded.'
              : `Found ${instances.length} Vim instance(s):\n${instances.map(i =>
                  `- ${i.id} (PID: ${i.pid})\n  File: ${i.main_file}\n  CWD: ${i.cwd}`
                ).join('\n')}`
          }]
        };
      }

      if (name === 'select_vim_instance') {
        const instanceId = args.instance_id;
        const registry = this.validateInstances(this.loadRegistry());

        if (!registry[instanceId]) {
          const available = Object.keys(registry);
          throw new Error(`Instance '${instanceId}' not found. Available instances: ${available.join(', ') || 'none'}`);
        }

        this.selectedInstance = instanceId;
        this.savePreference(instanceId);

        const info = registry[instanceId];
        return {
          content: [{
            type: 'text',
            text: `Connected to Vim instance: ${instanceId}\nFile: ${info.main_file || 'unnamed'}\nCWD: ${info.cwd}`
          }]
        };
      }

      if (name === 'get_vim_state') {
        if (!this.selectedInstance) {
          throw new Error('No Vim instance selected. Use select_vim_instance tool first.');
        }

        try {
          const state = await this.getVimState(this.selectedInstance);
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
          }
        ]
      };
    });
  }

  async start() {
    // Auto-select instance if there's only one
    const registry = this.validateInstances(this.loadRegistry());
    const instances = Object.keys(registry);

    if (instances.length === 1) {
      this.selectedInstance = instances[0];
      this.savePreference(instances[0]);
      console.error(`Auto-selected single Vim instance: ${instances[0]}`);
    } else if (instances.length > 1) {
      // Try to use preference
      const pref = this.loadPreference();
      if (pref && registry[pref]) {
        this.selectedInstance = pref;
        console.error(`Using preferred Vim instance: ${pref}`);
      }
    }

    const transport = new StdioServerTransport();
    await this.server.connect(transport);
    console.error('Vim MCP Server started');
  }
}

const server = new VimMCPServer();
server.start().catch(console.error);
