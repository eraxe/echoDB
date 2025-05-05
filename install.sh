#!/bin/bash
# echoDB Installation Script
# Installs the Simple Database Transfer Tool system-wide

# Define colors for output
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
MAGENTA="\033[0;35m"
CYAN="\033[0;36m"
RESET="\033[0m"

# Check if running with sudo/root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Installation requires root privileges. Please run with sudo.${RESET}"
    exit 1
fi

# Set installation paths
INSTALL_DIR="/usr/local/share/echoDB"
BIN_LINK="/usr/local/bin/echodb"
CONF_DIR="/etc/echoDB"

# Get script directory
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

echo -e "${MAGENTA}Installing echoDB - Simple Database Transfer Tool${RESET}"

# Create installation directories
echo -e "${CYAN}Creating installation directories...${RESET}"
mkdir -p "$INSTALL_DIR"
mkdir -p "$CONF_DIR"

# Copy files
echo -e "${CYAN}Copying application files...${RESET}"
cp -r "$SCRIPT_DIR"/* "$INSTALL_DIR/"

# Set permissions
echo -e "${CYAN}Setting file permissions...${RESET}"
chmod 755 "$INSTALL_DIR/bin/echodb"
chmod 755 "$INSTALL_DIR/install.sh"

# Create symlink
echo -e "${CYAN}Creating executable symlink...${RESET}"
ln -sf "$INSTALL_DIR/bin/echodb" "$BIN_LINK"

# Create global configuration
if [ ! -f "$CONF_DIR/config.conf" ]; then
    echo -e "${CYAN}Creating global configuration...${RESET}"
    cp "$INSTALL_DIR/config/default.conf" "$CONF_DIR/config.conf"
fi

echo -e "${GREEN}Installation complete!${RESET}"
echo -e "${YELLOW}You can now run echoDB by typing ${CYAN}echoDB${YELLOW} in your terminal.${RESET}"