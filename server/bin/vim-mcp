#!/usr/bin/env node

// vim-mcp MCP server entry point
// This script starts the MCP server for Vim integration

import { spawn } from 'child_process';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

// Get the directory of this script
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Get the absolute path to the index.js file
const indexPath = join(__dirname, '..', 'index.js');

// Forward all arguments to the main script
const args = [indexPath, ...process.argv.slice(2)];

// Spawn the node process with the index.js file
const child = spawn('node', args, {
  stdio: 'inherit',
  env: process.env
});

// Forward exit code
child.on('exit', (code) => {
  process.exit(code || 0);
});

// Handle termination signals
process.on('SIGTERM', () => {
  child.kill('SIGTERM');
});

process.on('SIGINT', () => {
  child.kill('SIGINT');
});