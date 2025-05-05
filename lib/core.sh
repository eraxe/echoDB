#!/bin/bash
# echoDB Core Module
# Contains core functionality and initialization

# Version information
VERSION="1.3.0"
REPO_URL="https://github.com/eraxe/echoDB"

# Default configuration
CONFIG_DIR="$HOME/.echoDB"
CONFIG_FILE="$CONFIG_DIR/config.conf"
TEMP_DIR="/tmp/echoDB_$(date +%Y%m%d_%H%M%S)"
LOG_DIR="$CONFIG_DIR/logs"
LOG_FILE="$LOG_DIR/echoDB_$(date +%Y%m%d_%H%M%S).log"
DISPLAY_LOG_FILE="/tmp/echoDB_display_log_$(date +%Y%m%d_%H%M%S)"
PASS_STORE="$CONFIG_DIR/.passstore"

# Default behavior - can be changed by command line arguments
DEBUG=0
USE_DIALOG=1
USE_COLORS=1

# Function to output debug messages
debug_log() {
    if [ "$DEBUG" -eq 1 ]; then
        echo "[DEBUG] $1" >&2
    fi
}

# Ensure required tools are installed
check_dependencies() {
    debug_log "Checking dependencies"

    local missing_deps=()

    for cmd in dialog mysql mysqldump sed awk git openssl curl iconv; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${RW_ALERT}Error: Missing required dependencies: ${missing_deps[*]}${RESET}"
        echo "Please install them before running this script."
        exit 1
    fi

    debug_log "All dependencies found"
}

# Create required directories
initialize_directories() {
    debug_log "Initializing directories"

    mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$TEMP_DIR"
    # Secure the configuration directory
    chmod 700 "$CONFIG_DIR"

    debug_log "Directories initialized"
}

# Process command line arguments
process_arguments() {
    for arg in "$@"; do
        case "$arg" in
            --install)
                install_script
                exit $?
                ;;
            --update)
                update_script
                exit $?
                ;;
            --remove)
                remove_script
                exit $?
                ;;
            --help)
                show_header
                cat << EOF
echoDB: Simple Database Transfer Tool
Usage: $(basename "$0") [OPTION]

Options:
  --install       Install echoDB to system
  --update        Update echoDB from GitHub
  --remove        Remove echoDB from system
  --help          Show this help message
  --debug         Enable debug logging
  --no-dialog     Disable dialog UI (use console mode)
  --no-color      Disable colored output

When run without options, launches the interactive TUI.
EOF
                exit 0
                ;;
            --debug)
                DEBUG=1
                debug_log "Debug mode enabled"
                ;;
            --no-dialog)
                USE_DIALOG=0
                debug_log "Dialog UI disabled"
                ;;
            --no-color)
                USE_COLORS=0
                debug_log "Colors disabled"
                ;;
        esac
    done
}

# Install the script to the system
install_script() {
    local install_dir="/usr/local/bin"
    local conf_dir="/etc/echoDB"
    local script_name="echoDB"
    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)

    # Check if running with sudo/root
    if [ "$(id -u)" -ne 0 ]; then
        dialog --colors --title "Error" --msgbox "\Z1Installation requires root privileges. Please run with sudo." 8 60
        return 1
    fi

    # Create directories
    mkdir -p "$install_dir" "$conf_dir"

    # Install the entire directory structure
    cp -r "$script_dir"/* /usr/local/share/echoDB/

    # Create symlink to executable
    ln -sf /usr/local/share/echoDB/bin/echodb "$install_dir/$script_name"
    chmod 755 "/usr/local/share/echoDB/bin/echodb"

    # Create global config
    if [ ! -f "$conf_dir/config.conf" ]; then
        cat > "$conf_dir/config.conf" << EOF
# echoDB Global Configuration
VERSION="$VERSION"
EOF
    fi

    dialog --colors --title "Installation Complete" --msgbox "\Z6echoDB has been installed to $install_dir/$script_name\n\nYou can now run it by typing 'echoDB' in your terminal." 10 70
    return 0
}

# Remove script from system
remove_script() {
    local install_dir="/usr/local/bin"
    local share_dir="/usr/local/share/echoDB"
    local conf_dir="/etc/echoDB"
    local script_name="echoDB"

    # Check if running with sudo/root
    if [ "$(id -u)" -ne 0 ]; then
        dialog --colors --title "Error" --msgbox "\Z1Removal requires root privileges. Please run with sudo." 8 60
        return 1
    fi

    # Confirm removal
    dialog --colors --title "Confirm Removal" --yesno "\Z1Are you sure you want to remove echoDB from your system?\Z0" 8 60
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Remove files
    rm -f "$install_dir/$script_name"
    rm -rf "$share_dir"

    # Ask about config
    dialog --colors --title "Remove Configuration" --yesno "\Z3Do you want to remove configuration files in $conf_dir?\Z0" 8 70
    if [ $? -eq 0 ]; then
        rm -rf "$conf_dir"
    fi

    dialog --colors --title "Removal Complete" --msgbox "\Z6echoDB has been removed from your system." 8 60
    return 0
}

# Enhanced update function with better UI feedback
update_script() {
    local temp_dir="/tmp/echoDB_update_$(date +%s)"
    local current_dir=$(pwd)
    local update_log="$temp_dir/update.log"
    local script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)

    # Ensure we start with a clean directory
    if [ -d "$temp_dir" ]; then
        rm -rf "$temp_dir"
    fi

    # Create fresh temporary directory
    mkdir -p "$temp_dir"
    local update_log="$temp_dir/update.log"
    echo "[$(date)] Starting update process..." > "$update_log"

    # Create a tailbox for live update progress
    dialog --colors --title "Update Process" --begin 3 10 --tailbox "$update_log" 15 70 &
    local dialog_pid=$!

    # Clone the repository in background and log process
    {
        echo "[$(date)] Checking for updates from $REPO_URL..." >> "$update_log"

        cd "$temp_dir" || {
            echo "[$(date)] ERROR: Failed to create temporary directory" >> "$update_log"
            sleep 2
            kill $dialog_pid 2>/dev/null
            return 1
        }

        echo "[$(date)] Cloning repository..." >> "$update_log"

        # Clone the repository
        if ! git clone "$REPO_URL" repo 2>>$update_log; then
            echo "[$(date)] ERROR: Failed to clone repository. Check your internet connection and try again." >> "$update_log"
            sleep 3
            kill $dialog_pid 2>/dev/null
            cd "$current_dir" || true
            dialog --colors --title "Update Failed" --msgbox "\Z1Failed to clone repository. Check your internet connection and try again." 8 60
            rm -rf "$temp_dir"
            return 1
        fi

        # Change into the cloned repository directory
        cd repo || {
            echo "[$(date)] ERROR: Failed to access repository directory" >> "$update_log"
            sleep 2
            kill $dialog_pid 2>/dev/null
            cd "$current_dir" || true
            dialog --colors --title "Update Failed" --msgbox "\Z1Failed to access cloned repository." 8 60
            rm -rf "$temp_dir"
            return 1
        }

        # Kill tailbox before asking for confirmation
        sleep 1
        kill $dialog_pid 2>/dev/null

        # Confirm update - simplified message
        dialog --colors --title "Update Confirmation" --yesno "\Z6Do you want to update echoDB to the latest version?\n\nThis will replace your current version with the latest from GitHub." 10 60

        if [ $? -eq 0 ]; then
            # User confirmed update
            echo "[$(date)] User confirmed update. Proceeding with installation..." > "$update_log"
            echo "Installing update, please wait..."

            # Check if it's a system installation or local
            local is_system_install=0

            if [ -f "/usr/local/bin/echodb" ] || [ -d "/usr/local/share/echoDB" ]; then
                echo "[$(date)] Detected system installation." >> "$update_log"
                is_system_install=1

                if [ "$(id -u)" -ne 0 ]; then
                    echo "[$(date)] ERROR: Update requires root privileges for system installation." >> "$update_log"
                    cd "$current_dir" || true
                    dialog --title "Error" --msgbox "Update requires root privileges. Please run with sudo." 8 60
                    rm -rf "$temp_dir"
                    return 1
                fi
            fi

            # If system install
            if [ $is_system_install -eq 1 ]; then
                echo "[$(date)] Updating system installation..." >> "$update_log"
                # Copy all files to /usr/local/share/echoDB
                cp -r ./* /usr/local/share/echoDB/ >> "$update_log" 2>&1
                echo "[$(date)] System installation updated successfully." >> "$update_log"
            else
                echo "[$(date)] Updating local installation..." >> "$update_log"
                # Copy all files to the script directory
                cp -r ./* "$script_dir/" >> "$update_log" 2>&1
                echo "[$(date)] Local installation updated successfully." >> "$update_log"
            fi

            dialog --colors --title "Update Successful" --msgbox "\Z6echoDB has been updated to the latest version.\n\nPlease restart the script for changes to take effect." 10 60

            # Cleanup and exit
            rm -rf "$temp_dir"
            cd "$current_dir" || true
            exit 0
        else
            dialog --colors --title "Update Cancelled" --msgbox "\Z6Update cancelled." 8 60
            rm -rf "$temp_dir"
            cd "$current_dir" || true
            return 0
        fi
    } &

    # Wait for background process to complete
    wait

    # Make sure dialog is killed
    kill $dialog_pid 2>/dev/null || true

    # Return to original directory
    cd "$current_dir" || true
    return 0
}

# Simplified check for updates function
check_for_updates() {
    dialog --colors --title "Check for Updates" --yesno "\Z6Would you like to check for and download the latest version of echoDB from GitHub?\n\nThis will replace your current version with the latest available." 10 70

    if [ $? -eq 0 ]; then
        update_script
        return $?
    fi

    return 0
}

# Main function - application entry point
main() {
    # Set DEBUG temporarily to diagnose issues if needed
    DEBUG=${DEBUG:-0}
    debug_log "Starting echoDB v$VERSION"

    # Process command line arguments if any
    if [ $# -gt 0 ]; then
        process_arguments "$@"
    fi

    # Check dependencies before proceeding
    debug_log "Checking dependencies"
    check_dependencies

    # Get terminal size information
    debug_log "Getting terminal size"
    get_terminal_size

    # Simple clearing first
    clear
    debug_log "Terminal cleared"

    # Set up basic terminal appearance
    debug_log "Setting up terminal appearance"
    set_term_appearance

    # Show the header
    debug_log "Showing header"
    show_header

    # Create required directories
    debug_log "Initializing directories"
    initialize_directories

    # Set default values if not loaded from config
    MYSQL_USER=${MYSQL_USER:-"root"}
    SQL_PATTERN=${SQL_PATTERN:-"*.sql"}

    # Try to load config
    debug_log "Loading configuration"
    load_config

    # Try to retrieve password if we have a username
    if [ -n "$MYSQL_USER" ] && [ -z "$MYSQL_PASS" ]; then
        MYSQL_PASS=$(get_password "$MYSQL_USER")
    fi

    # Setup dialog only after other initialization is complete
    debug_log "Dialog setup starting"
    if [ "$USE_DIALOG" -eq 1 ]; then
        # Setup dialog theme
        if ! setup_dialog_theme; then
            debug_log "Dialog theme setup failed, falling back to console mode"
            USE_DIALOG=0
        fi

        # Check if dialog works
        if ! check_dialog; then
            debug_log "Dialog check failed, falling back to console mode"
            USE_DIALOG=0
        fi
    fi

    debug_log "Ready to show main menu"

    # Show main menu without unnecessary dialogs
    if [ "$USE_DIALOG" -eq 1 ]; then
        show_main_menu
    else
        echo "Console mode not implemented in this version." >&2
        echo "Please install dialog or fix terminal settings to use echoDB." >&2
        exit 1
    fi

    # Clean up on exit
    if [ -n "$DIALOGRC" ] && [ -f "$DIALOGRC" ]; then
        rm -f "$DIALOGRC"
    fi

    debug_log "echoDB exiting normally"
}