#!/bin/bash

# vim-mcp installer script
# Automates the installation process for users

set -e

echo "======================================="
echo "       vim-mcp Installer"
echo "======================================="
echo ""

# Check Node.js version
check_node() {
    if ! command -v node &> /dev/null; then
        echo "Error: Node.js is not installed"
        echo "Please install Node.js >= 18.0.0 from https://nodejs.org"
        exit 1
    fi

    NODE_VERSION=$(node -v | cut -d'v' -f2)
    REQUIRED_VERSION="18.0.0"

    if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$NODE_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]; then
        echo "Error: Node.js version $NODE_VERSION is too old"
        echo "Please upgrade to Node.js >= 18.0.0"
        exit 1
    fi

    echo "✓ Node.js $NODE_VERSION detected"
}

# Check Vim/Neovim
check_vim() {
    VIM_FOUND=false

    if command -v vim &> /dev/null; then
        if vim --version | grep -q "+channel"; then
            echo "✓ Vim with +channel support detected"
            VIM_FOUND=true
        else
            echo "Vim found but lacks +channel support"
        fi
    fi

    if command -v nvim &> /dev/null; then
        echo "✓ Neovim detected"
        VIM_FOUND=true
    fi

    if [ "$VIM_FOUND" = false ]; then
        echo "Error: No compatible Vim/Neovim found"
        echo "Please install Vim 8.0+ with +channel or Neovim 0.5+"
        exit 1
    fi
}

# Install server dependencies
install_server() {
    echo ""
    echo "Installing server dependencies..."
    cd server
    npm install
    cd ..
    echo "✓ Server dependencies installed"
}

# Attempt global installation
try_global_install() {
    echo ""
    echo "Attempting global installation..."
    cd server

    if npm link > /dev/null 2>&1; then
        echo "✓ vim-mcp command installed globally"
        GLOBAL_INSTALL_SUCCESS=true
    else
        echo "⚠ Global installation failed (permission denied?)"
        echo "  You can use the full path instead"
        GLOBAL_INSTALL_SUCCESS=false
    fi

    cd ..
}

# Show configuration instructions
show_config() {
    echo ""
    echo "======================================="
    echo "     Installation Complete!"
    echo "======================================="
    echo ""
    echo "Next step: Configure Claude Code MCP settings"
    echo ""

    if [ "$GLOBAL_INSTALL_SUCCESS" = true ]; then
        echo "Use this configuration (recommended):"
        echo '{'
        echo '  "mcpServers": {'
        echo '    "vim-mcp": {'
        echo '      "command": "vim-mcp",'
        echo '      "args": []'
        echo '    }'
        echo '  }'
        echo '}'
    else
        SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
        echo "Use this configuration with full path:"
        echo '{'
        echo '  "mcpServers": {'
        echo '    "vim-mcp": {'
        echo '      "command": "node",'
        echo "      \"args\": [\"$SCRIPT_DIR/server/bin/vim-mcp.js\"]"
        echo '    }'
        echo '  }'
        echo '}'
    fi

    echo ""
    echo "After configuration:"
    echo "1. Restart Claude Code"
    echo "2. Open Vim and run :VimMCPStatus to verify connection"
}

# Main installation
main() {
    echo "Checking prerequisites..."
    check_node
    check_vim

    install_server

    # Make bin executable
    chmod +x server/bin/vim-mcp.js

    try_global_install
    show_config
}

main
