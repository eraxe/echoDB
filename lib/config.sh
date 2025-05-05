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
configure_settings() {
    local settings_menu

    while true; do
        settings_menu=$(dialog --colors --clear --backtitle "\Z6echoDB - Configuration\Z0" \
            --title "Configure Settings" --menu "Choose a setting to configure:" 15 60 6 \
            "1" "\Z5MySQL Username\Z0 (Current: ${MYSQL_USER:-not set})" \
            "2" "\Z5Database Owner\Z0 (Current: ${DB_OWNER:-not set})" \
            "3" "\Z5Database Prefix\Z0 (Current: ${DB_PREFIX:-not set})" \
            "4" "\Z5SQL File Pattern\Z0 (Current: ${SQL_PATTERN:-*.sql})" \
            "5" "\Z5MySQL Password\Z0" \
            "6" "\Z1Back to Main Menu\Z0" \
            3>&1 1>&2 2>&3)

        case $settings_menu in
            1)
                MYSQL_USER=$(dialog --colors --title "MySQL Username" --inputbox "Enter MySQL username:" 8 60 "${MYSQL_USER:-root}" 3>&1 1>&2 2>&3)
                ;;
            2)
                DB_OWNER=$(dialog --colors --title "Database Owner" --inputbox "Enter database owner username:" 8 60 "${DB_OWNER}" 3>&1 1>&2 2>&3)
                ;;
            3)
                DB_PREFIX=$(dialog --colors --title "Database Prefix" --inputbox "Enter database prefix:" 8 60 "${DB_PREFIX}" 3>&1 1>&2 2>&3)
                ;;
            4)
                SQL_PATTERN=$(dialog --colors --title "SQL File Pattern" --inputbox "Enter SQL file pattern:" 8 60 "${SQL_PATTERN:-*.sql}" 3>&1 1>&2 2>&3)
                ;;
            5)
                local password
                password=$(dialog --colors --title "MySQL Password" --passwordbox "Enter MySQL password for user '${MYSQL_USER:-root}':" 8 60 3>&1 1>&2 2>&3)

                if [ -n "$password" ]; then
                    # Store the password securely
                    MYSQL_PASS="$password"
                    store_password "${MYSQL_USER:-root}" "$password"

                    # Verify MySQL connection works
                    if ! mysql -u "${MYSQL_USER:-root}" -p"$password" -e "SELECT 1" >/dev/null 2>&1; then
                        dialog --colors --title "Connection Error" --msgbox "\Z1Failed to connect to MySQL server. Please check credentials." 8 60
                    else
                        dialog --colors --title "Connection Success" --msgbox "\Z6Successfully connected to MySQL server and securely stored password." 8 60
                    fi
                fi
                ;;
            6|"")
                break
                ;;
        esac
    done
}

# Browse and select directories with enhanced theming
browse_directories() {
    local current_dir="${SQL_DIR:-$HOME}"
    local selection

    while true; do
        # Get directories in current path
        local dirs=()
        local files=()

        # Add parent directory option
        dirs+=("../" "↑ Parent Directory")

        # List directories and SQL files
        while IFS= read -r dir; do
            if [ -d "$dir" ]; then
                # Format for display with better colors
                local display_name="${dir##*/}/"
                dirs+=("$dir/" "\Z6📁 $display_name\Z0")
            fi
        done < <(find "$current_dir" -maxdepth 1 -type d -not -path "$current_dir" | sort)

        # List SQL files if pattern is defined
        if [ -n "$SQL_PATTERN" ]; then
            while IFS= read -r file; do
                if [ -f "$file" ]; then
                    local display_name="${file##*/}"
                    files+=("$file" "\Z6📄 $display_name\Z0")
                fi
            done < <(find "$current_dir" -maxdepth 1 -type f -name "$SQL_PATTERN" | sort)
        fi

        # Combine directories and files
        local options=("${dirs[@]}" "${files[@]}")

        # Add options to select current directory and to go back
        options+=("SELECT_DIR" "\Z2✅ [ Select Current Directory ]\Z0")
        options+=("BACK" "\Z1⬅️ [ Back to Main Menu ]\Z0")

        selection=$(dialog --colors --clear --backtitle "\Z6echoDB - Directory Browser\Z0" \
            --title "Directory Browser" \
            --menu "Current: \Z5$current_dir\Z0\n\nNavigate to directory containing SQL files:" 20 76 12 \
            "${options[@]}" 3>&1 1>&2 2>&3)

        case $selection in
            "SELECT_DIR")
                SQL_DIR="$current_dir"
                dialog --colors --title "Directory Selected" --msgbox "\Z6Selected directory: $SQL_DIR" 8 60

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
            "BACK"|"")
                break
                ;;
            *)
                if [ -d "$selection" ]; then
                    current_dir="$selection"
                elif [ -f "$selection" ]; then
                    dialog --colors --title "File Selected" --msgbox "\Z6Selected file: $selection\n\nThis is a file, not a directory. Please select a directory." 10 60
                fi
                ;;
        esac
    done
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