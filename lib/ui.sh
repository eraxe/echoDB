#!/bin/bash
# echoDB UI Module
# Handles UI components, dialog, and display functions

# We need to ensure these variables are set for the dialog interface
export TERM=xterm-256color 2>/dev/null

# Ensure COLUMNS is defined for terminal operations
get_terminal_size() {
    debug_log "Getting terminal size"

    # Try different methods to get terminal size
    if [ -z "$COLUMNS" ]; then
        if command -v tput > /dev/null 2>&1; then
            COLUMNS=$(tput cols 2>/dev/null || echo 80)
        else
            COLUMNS=80
        fi
    fi

    if [ -z "$LINES" ]; then
        if command -v tput > /dev/null 2>&1; then
            LINES=$(tput lines 2>/dev/null || echo 24)
        else
            LINES=24
        fi
    fi

    export COLUMNS LINES
    debug_log "Terminal size: ${COLUMNS}x${LINES}"
}

# Enhanced theme settings with retrowave colors
setup_dialog_theme() {
    debug_log "Setting up dialog theme"

    # First verify dialog is available
    if ! command -v dialog > /dev/null 2>&1; then
        echo "ERROR: dialog command not found. Please install dialog package." >&2
        USE_DIALOG=0
        return 1
    fi

    # Try to determine if we can use colors
    if [ "$USE_COLORS" -eq 0 ]; then
        debug_log "Terminal doesn't support colors, skipping dialog theme"
        return 0
    fi

    # Create a unique temporary file for this process
    local dialogrc_file="/tmp/dialogrc_echoDB_$"

    # Create the dialog configuration file with retrowave colors
    # Using more compatible dialog theme settings
    cat > "$dialogrc_file" << 'EOF'
# Dialog configuration with Retrowave theme
# Set aspect-ratio and screen edge
aspect = 0
separate_widget = ""
tab_len = 0
visit_items = OFF
use_shadow = ON
use_colors = ON

# Retrowave color scheme for better compatibility
screen_color = (BLACK,BLACK,OFF)
shadow_color = (BLACK,BLACK,OFF)
dialog_color = (MAGENTA,BLACK,OFF)
title_color = (MAGENTA,BLACK,ON)
border_color = (MAGENTA,BLACK,ON)
button_active_color = (BLACK,MAGENTA,ON)
button_inactive_color = (CYAN,BLACK,OFF)
button_key_active_color = (BLACK,MAGENTA,ON)
button_key_inactive_color = (CYAN,BLACK,OFF)
button_label_active_color = (BLACK,MAGENTA,ON)
button_label_inactive_color = (CYAN,BLACK,OFF)
inputbox_color = (CYAN,BLACK,OFF)
inputbox_border_color = (MAGENTA,BLACK,ON)
searchbox_color = (CYAN,BLACK,OFF)
searchbox_title_color = (MAGENTA,BLACK,ON)
searchbox_border_color = (MAGENTA,BLACK,ON)
position_indicator_color = (YELLOW,BLACK,ON)
menubox_color = (CYAN,BLACK,OFF)
menubox_border_color = (MAGENTA,BLACK,ON)
item_color = (CYAN,BLACK,OFF)
item_selected_color = (BLACK,MAGENTA,ON)
tag_color = (MAGENTA,BLACK,ON)
tag_selected_color = (BLACK,MAGENTA,ON)
tag_key_color = (MAGENTA,BLACK,ON)
tag_key_selected_color = (BLACK,MAGENTA,ON)
check_color = (CYAN,BLACK,OFF)
check_selected_color = (BLACK,MAGENTA,ON)
uarrow_color = (MAGENTA,BLACK,ON)
darrow_color = (MAGENTA,BLACK,ON)
itemhelp_color = (CYAN,BLACK,OFF)
form_active_text_color = (BLACK,MAGENTA,ON)
form_text_color = (CYAN,BLACK,ON)
form_item_readonly_color = (CYAN,BLACK,ON)
gauge_color = (MAGENTA,BLACK,ON)
EOF

    # Set permissions
    chmod 644 "$dialogrc_file"

    # Export the environment variable
    export DIALOGRC="$dialogrc_file"

    # Verify the file exists and is readable
    if [ ! -f "$DIALOGRC" ] || [ ! -r "$DIALOGRC" ]; then
        echo "ERROR: Failed to create or access dialog configuration at $DIALOGRC" >&2
        unset DIALOGRC
        return 1
    fi

    debug_log "Dialog theme configured at $DIALOGRC"
    return 0
}

# Retrowave ANSI color codes for better compatibility
setup_color_variables() {
    if [ "$USE_COLORS" -eq 1 ]; then
        RESET="\033[0m"
        BOLD="\033[1m"
        BLACK="\033[30m"
        RED="\033[31m"
        GREEN="\033[32m"
        YELLOW="\033[33m"
        BLUE="\033[34m"
        MAGENTA="\033[35m"
        CYAN="\033[36m"
        WHITE="\033[37m"
        # Bright colors for retrowave theme
        BRIGHTBLACK="\033[90m"
        BRIGHTRED="\033[91m"
        BRIGHTGREEN="\033[92m"
        BRIGHTYELLOW="\033[93m"
        BRIGHTBLUE="\033[94m"
        BRIGHTMAGENTA="\033[95m"
        BRIGHTCYAN="\033[96m"
        BRIGHTWHITE="\033[97m"
        # Background colors
        BGBLACK="\033[40m"
        BGRED="\033[41m"
        BGGREEN="\033[42m"
        BGYELLOW="\033[43m"
        BGBLUE="\033[44m"
        BGMAGENTA="\033[45m"
        BGCYAN="\033[46m"
        BGWHITE="\033[47m"
        BGBRIGHTBLACK="\033[100m"
        BGBRIGHTMAGENTA="\033[105m"
    else
        # No colors in non-interactive mode or terminals without color support
        RESET=""
        BOLD=""
        BLACK=""
        RED=""
        GREEN=""
        YELLOW=""
        BLUE=""
        MAGENTA=""
        CYAN=""
        WHITE=""
        BRIGHTBLACK=""
        BRIGHTRED=""
        BRIGHTGREEN=""
        BRIGHTYELLOW=""
        BRIGHTBLUE=""
        BRIGHTMAGENTA=""
        BRIGHTCYAN=""
        BRIGHTWHITE=""
        BGBLACK=""
        BGRED=""
        BGGREEN=""
        BGYELLOW=""
        BGBLUE=""
        BGMAGENTA=""
        BGCYAN=""
        BGWHITE=""
        BGBRIGHTBLACK=""
        BGBRIGHTRED=""
        BGBRIGHTGREEN=""
        BGBRIGHTYELLOW=""
        BGBRIGHTBLUE=""
        BGBRIGHTMAGENTA=""
        BGBRIGHTCYAN=""
        BGBRIGHTWHITE=""
    fi

    # Retrowave color presets matching the theme
    RW_PRIMARY="${BRIGHTMAGENTA}"
    RW_SECONDARY="${BRIGHTBLUE}"
    RW_ACCENT="${BRIGHTYELLOW}"
    RW_ALERT="${BRIGHTRED}"
    RW_SUCCESS="${BRIGHTGREEN}"
    RW_WARNING="${YELLOW}"
    RW_BG="${BGBLACK}"
    RW_HEADER="${BRIGHTMAGENTA}${BOLD}"
    RW_TEXT="${BRIGHTBLUE}"
}

# Verify dialog works properly - simplified with better error handling
check_dialog() {
    debug_log "Checking if dialog works properly"

    # Only do this check if we're using dialog
    if [ "$USE_DIALOG" -eq 0 ]; then
        debug_log "Dialog disabled, skipping check"
        return 1
    fi

    # Check for dialog command
    if ! command -v dialog >/dev/null 2>&1; then
        echo "ERROR: Dialog command not found" >&2
        USE_DIALOG=0
        return 1
    fi

    # Test dialog functionality quietly without creating any windows
    if ! dialog --print-version >/dev/null 2>&1; then
        echo "ERROR: Dialog not working properly" >&2
        USE_DIALOG=0
        return 1
    fi

    # Skip interactive checks to avoid issues
    debug_log "Dialog basic check passed"
    return 0
}

# Function to set terminal title and background - simplified for better compatibility
set_term_appearance() {
    debug_log "Setting terminal appearance"

    # Get terminal size
    get_terminal_size

    # Only perform these operations if we're in a terminal that supports colors
    if [ "$USE_COLORS" -eq 1 ]; then
        # Set terminal title
        echo -ne "\033]0;echoDB - Retrowave\007"

        # Simple clear with basic retrowave effect
        clear
        # Top border
        echo -e "${BGBLACK}${BRIGHTMAGENTA}$(printf '%*s' ${COLUMNS} | tr ' ' '═')${RESET}"

        # Empty space with black background
        for i in {1..3}; do
            echo -e "${BGBLACK}$(printf '%*s' ${COLUMNS})${RESET}"
        done

        # Return cursor to top
        tput cup 0 0 2>/dev/null || true
    else
        # Simple fallback for terminals without color support
        clear
    fi

    debug_log "Terminal appearance set"
}

# Display fancy ASCII art header with retrowave colors
show_header() {
    debug_log "Showing header"

    # Initialize colors
    setup_color_variables

    # Return cursor to top (if possible)
    if command -v tput > /dev/null 2>&1; then
        tput cup 0 0 2>/dev/null || true
    fi

    # Using retrowave colors
    if [ "$USE_COLORS" -eq 1 ]; then
        echo -e "${RW_HEADER}"
        cat << "EOF"
 ██████╗██████╗ ██████╗ ████████╗████████╗
██╔════╝██╔══██╗██╔══██╗╚══██╔══╝╚══██╔══╝
╚█████╗ ██║  ██║██████╔╝   ██║      ██║
 ╚═══██╗██║  ██║██╔══██╗   ██║      ██║
██████╔╝██████╔╝██████╔╝   ██║      ██║
╚═════╝ ╚═════╝ ╚═════╝    ╚═╝      ╚═╝
EOF
        echo -e "${BRIGHTCYAN}░▒▓${BRIGHTMAGENTA}█${BRIGHTCYAN}▓▒░${BRIGHTCYAN}░▒▓${BRIGHTMAGENTA}█${BRIGHTCYAN}▓▒░${BRIGHTCYAN}░▒▓${BRIGHTMAGENTA}█${BRIGHTCYAN}▓▒░${BRIGHTCYAN}░▒▓${BRIGHTMAGENTA}█${BRIGHTCYAN}▓▒░"
        echo -e "${RW_HEADER}Simple Database Transfer Tool v$VERSION${RESET}"
        echo -e "${BRIGHTCYAN}░▒▓${BRIGHTBLUE}█${BRIGHTCYAN}▓▒░${BRIGHTCYAN}░▒▓${BRIGHTBLUE}█${BRIGHTCYAN}▓▒░${BRIGHTCYAN}░▒▓${BRIGHTBLUE}█${BRIGHTCYAN}▓▒░${BRIGHTCYAN}░▒▓${BRIGHTBLUE}█${BRIGHTCYAN}▓▒░${RESET}"
    else
        # Plain text version for terminals without color support
        cat << EOF
==================================================
           echoDB: Simple Database Transfer Tool
                     Version $VERSION
==================================================
EOF
    fi

    debug_log "Header displayed"
}

# Display the about information with enhanced colors
show_about() {
    dialog --colors --title "About echoDB" --msgbox "\
\Z5Simple Database Transfer Tool (echoDB) v$VERSION\Z0
\n
A tool for importing and managing MySQL databases with ease.
\n
\Z6Features:\Z0
- Interactive TUI with enhanced Retrowave theme
- Directory navigation and selection
- Secure password management
- Multiple import methods for compatibility
- MySQL database administration
- Auto-update from GitHub
- Transfer and replace databases
- MySQL user management
\n
\Z6GitHub:\Z0 $REPO_URL
\n
\Z5Created by:\Z0 eraxe
" 20 70
}

# Help screen with enhanced theming
show_help() {
    dialog --colors --title "echoDB Help" --msgbox "\
\Z5Simple Database Transfer Tool (echoDB) Help\Z0
------------------------------------

This tool helps you import MySQL databases from SQL files with the following features:

\Z6* Interactive TUI with enhanced Retrowave theme
* Directory navigation and selection
* Configuration management with secure password storage
* Automatic charset conversion and fixing Persian/Arabic text
* Multiple import methods for compatibility
* Prefix replacement
* MySQL administration tools
* MySQL user management
* Database transfer and replacement
* Privilege management\Z0

\Z5How to use this tool:\Z0
1. Configure your MySQL credentials
2. Set the database owner who will receive privileges
3. Browse to the directory containing your SQL files
4. Select which files to import
5. Review and confirm the import plan

\Z5Command-line options:\Z0
--install    Install echoDB to system
--update     Update echoDB from GitHub
--remove     Remove echoDB from system
--help       Show this help message
--debug      Enable debug logging
--no-dialog  Disable dialog UI
--no-color   Disable colored output

\Z5Security features:\Z0
* Passwords are encrypted and stored securely
* Restricted file permissions for sensitive files
* No plaintext passwords in config files

The tool saves your settings for future use and keeps logs of all operations.

\Z5Character Encoding Support:\Z0
* Properly handles UTF-8 and UTF-8MB4 encoding
* Automatically detects and fixes encoding issues
* Ensures proper display of Persian, Arabic, and other non-Latin scripts
" 25 78
}

# Display main menu with enhanced theming
show_main_menu() {
    local choice

    debug_log "Displaying main menu"

    while true; do
        # Try to use a simpler menu format with retrowave colors
        choice=$(dialog --colors --clear --backtitle "\Z6echoDB - Simple Database Transfer Tool v$VERSION\Z0" \
            --title "Main Menu" --menu "Choose an option:" 18 60 12 \
            "1" "\Z6Import Databases\Z0" \
            "2" "\Z6Transfer and Replace Database\Z0" \
            "3" "\Z6Configure Settings\Z0" \
            "4" "\Z6Browse & Select Directories\Z0" \
            "5" "\Z6MySQL Administration\Z0" \
            "6" "\Z6View Logs\Z0" \
            "7" "\Z6Save Current Settings\Z0" \
            "8" "\Z6Load Saved Settings\Z0" \
            "9" "\Z6Check for Updates\Z0" \
            "10" "\Z6About echoDB\Z0" \
            "11" "\Z6Help\Z0" \
            "0" "\Z1Exit\Z0" \
            3>&1 1>&2 2>&3)

        local menu_exit=$?
        debug_log "Menu returned: '$choice' with exit code $menu_exit"

        if [ $menu_exit -ne 0 ]; then
            # Exit code is not 0, check if it's a normal cancel
            if [ $menu_exit -ne 1 ]; then
                debug_log "Dialog menu failed with code $menu_exit"
                echo "ERROR: Dialog menu failed, trying to continue..." >&2
            fi
            choice=""
        fi

        case $choice in
            1) import_databases_menu ;;
            2) transfer_replace_database ;;
            3) configure_settings ;;
            4) browse_directories ;;
            5) enhanced_mysql_admin_menu ;;
            6) view_logs ;;
            7) save_config ;;
            8)
                if load_config; then
                    dialog --colors --title "Configuration Loaded" --msgbox "\Z6Settings have been loaded from $CONFIG_FILE" 8 60
                else
                    dialog --colors --title "Error" --msgbox "\Z1No saved configuration found at $CONFIG_FILE" 8 60
                fi
                ;;
            9) check_for_updates ;;
            10) show_about ;;
            11) show_help ;;
            0)
                # Clean up and reset terminal without showing goodbye message
                rm -f "$DIALOGRC" 2>/dev/null
                clear
                exit 0
                ;;
            *)
                # User pressed Cancel or ESC
                if [ -z "$choice" ]; then
                    dialog --colors --title "Exit Confirmation" --yesno "Are you sure you want to exit?" 8 60
                    if [ $? -eq 0 ]; then
                        # Clean up and reset terminal without showing goodbye message
                        rm -f "$DIALOGRC" 2>/dev/null
                        clear
                        exit 0
                    fi
                fi
                ;;
        esac
    done
}

# View logs menu with enhanced theming
view_logs() {
    local logs=()
    local i=1

    # List log files
    while IFS= read -r log; do
        if [ -f "$log" ]; then
            local log_date=$(basename "$log" | sed 's/echoDB_\(.*\)\.log/\1/')
            logs+=("$log" "[$i] \Z6Log from $log_date\Z0")
            ((i++))
        fi
    done < <(find "$LOG_DIR" -maxdepth 1 -type f -name "echoDB_*.log" | sort -r)

    if [ ${#logs[@]} -eq 0 ]; then
        dialog --colors --title "No Logs Found" --msgbox "\Z1No log files found in $LOG_DIR." 8 60
        return
    fi

    logs+=("BACK" "\Z1⬅️ [ Back to Main Menu ]\Z0")

    local selection
    selection=$(dialog --colors --clear --backtitle "\Z6echoDB - Logs\Z0" \
        --title "View Logs" \
        --menu "Select a log file to view:" 15 76 8 \
        "${logs[@]}" 3>&1 1>&2 2>&3)

    case $selection in
        "BACK"|"")
            return
            ;;
        *)
            # Check file size
            local file_size=$(du -k "$selection" | cut -f1)

            if [ "$file_size" -gt 500 ]; then
                dialog --colors --title "Large File" --yesno "\Z1The log file is quite large (${file_size}KB). Viewing large files may be slow. Continue?" 8 60
                if [ $? -ne 0 ]; then
                    return
                fi
            fi

            # View log file with enhanced formatting
            # Process the log file to add color to key events
            local temp_log="/tmp/echoDB_colored_log_$"
            cat "$selection" |
                sed 's/\[ERROR\]/\\Z1[ERROR]\\Z0/g' |
                sed 's/\[WARNING\]/\\Z3[WARNING]\\Z0/g' |
                sed 's/Creating database:/\\Z5Creating database:\\Z0/g' |
                sed 's/Import successful/\\Z2Import successful\\Z0/g' |
                sed 's/Failed to/\\Z1Failed to\\Z0/g' |
                sed 's/All import methods failed/\\Z1All import methods failed\\Z0/g' |
                sed 's/Flushing privileges/\\Z5Flushing privileges\\Z0/g' |
                sed 's/All databases have been processed/\\Z5All databases have been processed\\Z0/g' > "$temp_log"

            dialog --colors --title "Log File: $(basename "$selection")" --textbox "$temp_log" 25 78

            # Clean up
            rm -f "$temp_log"
            ;;
    esac
}

# Enhanced log message function with timestamp and log levels
enhanced_log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    # Format based on level
    case "$level" in
        "INFO")
            prefix="[INFO]"
            ;;
        "WARNING")
            prefix="[WARNING]"
            ;;
        "ERROR")
            prefix="[ERROR]"
            ;;
        "SUCCESS")
            prefix="[SUCCESS]"
            ;;
        *)
            prefix="[INFO]"
            ;;
    esac

    # Write to main log file
    echo "[$timestamp] $prefix $message" >> "$LOG_FILE"

    # If we have an active display log file, write to it too
    if [ -f "$DISPLAY_LOG_FILE" ]; then
        echo "[$timestamp] $prefix $message" >> "$DISPLAY_LOG_FILE"
    fi
}

# Function to log messages - enhanced to also display to active log screen
log_message() {
    local message="$1"
    enhanced_log_message "INFO" "$message"
}

# Enhanced error handling with dialog support
enhanced_error_exit() {
    enhanced_log_message "ERROR" "$1"
    if command -v dialog &>/dev/null && [ -f "$DIALOGRC" ]; then
        dialog --title "Error" --colors --msgbox "\Z1ERROR: $1\Z0" 8 60
    else
        echo -e "${RW_ALERT}ERROR: $1${RESET}" >&2
    fi
    exit 1
}

# Function to handle errors with themed error messages
error_exit() {
    enhanced_log_message "ERROR" "$1"
    if command -v dialog &>/dev/null && [ -f "$DIALOGRC" ]; then
        dialog --title "Error" --colors --msgbox "\Z1ERROR: $1\Z0" 8 60
    else
        echo -e "${RW_ALERT}ERROR: $1${RESET}" >&2
    fi
    exit 1
}