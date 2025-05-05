#!/bin/bash
# Complete Uninstall Script for echoDB and echoDB

# Define color codes
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RESET="\033[0m"

echo -e "${YELLOW}Complete Uninstall Script for echoDB and echoDB${RESET}"

# Check if running with sudo/root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}This script requires root privileges. Please run with sudo.${RESET}"
    exit 1
fi

# Define all possible paths
INSTALL_DIRS=(
    "/usr/local/share/echoDB"
    "/usr/local/share/echodb"
)

BIN_LINKS=(
    "/usr/local/bin/echodb"
    "/usr/local/bin/echodb"
)

CONF_DIRS=(
    "/etc/echoDB"
    "/etc/echodb"
)

USER_CONF_DIRS=(
    "$HOME/.echoDB"
    "$HOME/.echodb"
)

# Remove installation directories
for dir in "${INSTALL_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo -e "${YELLOW}Removing installation directory: $dir${RESET}"
        rm -rf "$dir"
        echo -e "${GREEN}✓ Removed $dir${RESET}"
    else
        echo -e "${YELLOW}Directory not found: $dir - skipping${RESET}"
    fi
done

# Remove binary links
for link in "${BIN_LINKS[@]}"; do
    if [ -L "$link" ] || [ -f "$link" ]; then
        echo -e "${YELLOW}Removing binary link: $link${RESET}"
        rm -f "$link"
        echo -e "${GREEN}✓ Removed $link${RESET}"
    else
        echo -e "${YELLOW}Binary link not found: $link - skipping${RESET}"
    fi
done

# Remove configuration directories
for dir in "${CONF_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo -e "${YELLOW}Removing configuration directory: $dir${RESET}"
        rm -rf "$dir"
        echo -e "${GREEN}✓ Removed $dir${RESET}"
    else
        echo -e "${YELLOW}Configuration directory not found: $dir - skipping${RESET}"
    fi
done

# Ask before removing user configuration
echo -e "${YELLOW}Do you want to remove user configuration directories? This will delete all your settings and backups.${RESET}"
read -p "Remove user configuration? (y/n): " confirm
if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
    for dir in "${USER_CONF_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            echo -e "${YELLOW}Removing user configuration directory: $dir${RESET}"
            rm -rf "$dir"
            echo -e "${GREEN}✓ Removed $dir${RESET}"
        else
            echo -e "${YELLOW}User configuration directory not found: $dir - skipping${RESET}"
        fi
    done
else
    echo -e "${YELLOW}Keeping user configuration directories${RESET}"
fi

echo -e "${GREEN}Uninstallation completed successfully!${RESET}"
