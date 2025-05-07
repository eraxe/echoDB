#!/bin/bash
# echoDB Configuration Module
# Handles loading, saving and managing configuration

# Load saved configuration
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
        return 0
    fi
    return 1
}

# Save current configuration
save_config() {
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" << EOF
# echoDB Configuration
# Last updated: $(date)
SQL_DIR="$SQL_DIR"
DB_PREFIX="$DB_PREFIX"
MYSQL_USER="$MYSQL_USER"
DB_OWNER="$DB_OWNER"
SQL_PATTERN="$SQL_PATTERN"
LAST_DIRECTORIES="$LAST_DIRECTORIES"
EOF
    chmod 600 "$CONFIG_FILE"  # Secure permissions for config file
    dialog --colors --title "Configuration Saved" --msgbox "\Z6Settings have been saved to $CONFIG_FILE" 8 60
}

# Securely store MySQL password
store_password() {
    local username="$1"
    local password="$2"

    # Generate a secure key for this user
    local key_file="$CONFIG_DIR/.key_$username"
    if [ ! -f "$key_file" ]; then
        openssl rand -base64 32 > "$key_file"
        chmod 600 "$key_file"
    fi

    # Encrypt the password using the key
    mkdir -p "$(dirname "$PASS_STORE")"
    echo "$password" | openssl enc -aes-256-cbc -salt -pbkdf2 -pass file:"$key_file" -out "$PASS_STORE.$username" 2>/dev/null
    chmod 600 "$PASS_STORE.$username"

    log_message "Password securely stored for user $username"
}

# Retrieve securely stored MySQL password
get_password() {
    local username="$1"
    local password=""

    local key_file="$CONFIG_DIR/.key_$username"
    local pass_file="$PASS_STORE.$username"

    if [ -f "$key_file" ] && [ -f "$pass_file" ]; then
        password=$(openssl enc -aes-256-cbc -d -salt -pbkdf2 -pass file:"$key_file" -in "$pass_file" 2>/dev/null)
    fi

    echo "$password"
}

# Configure settings menu with enhanced theming
# Configure settings menu with Gum
configure_settings() {
    while true; do
        clear
        gum_header

        local choice=$(gum_menu "Configure Settings" \
            "MySQL Username (Current: ${MYSQL_USER:-not set})" \
            "Database Owner (Current: ${DB_OWNER:-not set})" \
            "Database Prefix (Current: ${DB_PREFIX:-not set})" \
            "SQL File Pattern (Current: ${SQL_PATTERN:-*.sql})" \
            "MySQL Password" \
            "Back to Main Menu")

        case "$choice" in
            "MySQL Username"*)
                MYSQL_USER=$(gum_input "Enter MySQL username" "${MYSQL_USER:-root}")
                ;;
            "Database Owner"*)
                DB_OWNER=$(gum_input "Enter database owner username" "${DB_OWNER}")
                ;;
            "Database Prefix"*)
                DB_PREFIX=$(gum_input "Enter database prefix" "${DB_PREFIX}")
                ;;
            "SQL File Pattern"*)
                SQL_PATTERN=$(gum_input "Enter SQL file pattern" "${SQL_PATTERN:-*.sql}")
                ;;
            "MySQL Password")
                local password=$(gum_password "Enter MySQL password for user '${MYSQL_USER:-root}'")

                if [ -n "$password" ]; then
                    # Store the password securely
                    MYSQL_PASS="$password"
                    store_password "${MYSQL_USER:-root}" "$password"

                    # Verify MySQL connection works
                    if ! mysql -u "${MYSQL_USER:-root}" -p"$password" -e "SELECT 1" >/dev/null 2>&1; then
                        gum_message "error" "Failed to connect to MySQL server. Please check credentials."
                    else
                        gum_message "success" "Successfully connected to MySQL server and securely stored password."
                    fi
                fi
                ;;
            "Back to Main Menu"|"")
                break
                ;;
        esac
    done
}

# Browse and select directories with enhanced theming
# Browse and select directories with Gum
browse_directories() {
    local current_dir="${SQL_DIR:-$HOME}"

    while true; {
        clear
        gum_header

        # Show current directory
        gum_info "Directory Browser" "Current" "$current_dir"
        echo ""

        # Create directory options
        local options=("../")

        # Add directories
        while IFS= read -r dir; do
            if [ -d "$dir" ]; then
                options+=("$dir/")
            fi
        done < <(find "$current_dir" -maxdepth 1 -type d -not -path "$current_dir" | sort)

        # Add option to select current directory
        options+=("SELECT_THIS_DIR")
        options+=("BACK_TO_MENU")

        # Format display of options
        local formatted_options=()
        for opt in "${options[@]}"; do
            case "$opt" in
                "../")
                    formatted_options+=("↑ Parent Directory")
                    ;;
                "SELECT_THIS_DIR")
                    formatted_options+=("✓ Select Current Directory")
                    ;;
                "BACK_TO_MENU")
                    formatted_options+=("← Back to Main Menu")
                    ;;
                *)
                    # Format directory name
                    local display_name="${opt##*/}"
                    formatted_options+=("📁 $display_name")
                    ;;
            esac
        done

        # Show menu
        local selection_text=$(gum_menu "Navigate to directory containing SQL files:" "${formatted_options[@]}")

        # Convert selection text back to path
        local selection=""
        case "$selection_text" in
            "↑ Parent Directory")
                selection="../"
                ;;
            "✓ Select Current Directory")
                selection="SELECT_THIS_DIR"
                ;;
            "← Back to Main Menu")
                selection="BACK_TO_MENU"
                ;;
            *)
                # Extract directory name from display format
                local dir_name="${selection_text#📁 }"
                # Find matching directory in options
                for opt in "${options[@]}"; do
                    if [[ "$opt" == *"$dir_name" ]]; then
                        selection="$opt"
                        break
                    fi
                done
                ;;
        esac

        case "$selection" in
            "SELECT_THIS_DIR")
                SQL_DIR="$current_dir"
                gum_message "success" "Selected directory: $SQL_DIR"

                # Add to last directories list (max 5)
                if [ -z "$LAST_DIRECTORIES" ]; then
                    LAST_DIRECTORIES="$SQL_DIR"
                else
                    # Add to beginning of list and keep unique entries
                    LAST_DIRECTORIES="$SQL_DIR:$(echo "$LAST_DIRECTORIES" | sed "s|$SQL_DIR||g" | sed "s|::*|:|g" | sed "s|^:|:|g" | sed "s|:$||g")"
                    # Keep only the 5 most recent directories
                    LAST_DIRECTORIES=$(echo "$LAST_DIRECTORIES" | cut -d: -f1-5)
                fi

                break
                ;;
            "../")
                current_dir="$(dirname "$current_dir")"
                ;;
            "BACK_TO_MENU")
                break
                ;;
            *)
                if [ -d "$selection" ]; then
                    current_dir="$selection"
                fi
                ;;
        esac
    }
}
# Select from previously used directories with enhanced theming
select_from_recent_dirs() {
    if [ -z "$LAST_DIRECTORIES" ]; then
        dialog --colors --title "No Recent Directories" --msgbox "\Z1No recently used directories found." 8 60
        return 1
    fi

    local dirs=()
    local i=1

    # Convert colon-separated list to array
    IFS=':' read -ra dir_array <<< "$LAST_DIRECTORIES"

    for dir in "${dir_array[@]}"; do
        if [ -n "$dir" ] && [ -d "$dir" ]; then
            dirs+=("$dir" "Directory $i: \Z6$dir\Z0")
            ((i++))
        fi
    done

    if [ ${#dirs[@]} -eq 0 ]; then
        dialog --colors --title "No Valid Directories" --msgbox "\Z1No valid directories in recent history." 8 60
        return 1
    fi

    dirs+=("BACK" "\Z1⬅️ [ Back to Main Menu ]\Z0")

    local selection
    selection=$(dialog --colors --clear --backtitle "\Z6echoDB - Recent Directories\Z0" \
        --title "Recent Directories" \
        --menu "Select a recently used directory:" 15 76 8 \
        "${dirs[@]}" 3>&1 1>&2 2>&3)

    case $selection in
        "BACK"|"")
            return 1
            ;;
        *)
            SQL_DIR="$selection"
            dialog --colors --title "Directory Selected" --msgbox "\Z6Selected directory: $SQL_DIR" 8 60
            return 0
            ;;
    esac
}