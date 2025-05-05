#!/bin/bash
# SDBTT User Management Module
# Handles MySQL user creation, privileges, and management

# List all MySQL users with enhanced formatting
list_users() {
    local result
    result=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SELECT User, Host FROM mysql.user;" 2>/dev/null)

    if [ $? -ne 0 ]; then
        dialog --colors --title "Error" --msgbox "\Z1Failed to retrieve users. Check your MySQL credentials." 8 60
        return
    fi

    # Format the output for display with enhanced coloring
    local formatted_result
    formatted_result=$(echo "$result" | sed 's/User/\\Z5User\\Z0/g' | sed 's/Host/\\Z5Host\\Z0/g')

    dialog --colors --title "MySQL Users" --msgbox "$formatted_result" 20 60
}

# Show privileges for a specific user with enhanced formatting
show_user_privileges() {
    local username
    username=$(dialog --colors --title "User Privileges" --inputbox "Enter MySQL username:" 8 60 3>&1 1>&2 2>&3)

    if [ -z "$username" ]; then
        return
    fi

    local result
    result=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SHOW GRANTS FOR '$username'@'localhost';" 2>/dev/null)

    if [ $? -ne 0 ]; then
        dialog --colors --title "Error" --msgbox "\Z1Failed to retrieve privileges for user $username.\nThe user may not exist." 8 60
        return
    fi

    # Format with consistent coloring
    local formatted_result
    formatted_result=$(echo "$result" | sed 's/Grants for/\\Z5Grants for\\Z0/g')

    dialog --colors --title "Privileges for $username" --msgbox "$formatted_result" 20 70
}

# Create MySQL user with enhanced UI
create_mysql_user() {
    # Get system/DirectAdmin users if available
    local system_users=()

    if command -v getent >/dev/null 2>&1; then
        # Get real system users with UID >= 1000
        while IFS=: read -r user _ uid _; do
            if [ "$uid" -ge 1000 ] && [ "$uid" -ne 65534 ]; then
                system_users+=("$user")
            fi
        done < <(getent passwd)
    fi

    # If DirectAdmin environment
    if [ -d "/usr/local/directadmin" ]; then
        if [ -f "/usr/local/directadmin/data/users/users.list" ]; then
            while IFS= read -r user; do
                # Add only if not already in the list
                if ! [[ " ${system_users[@]} " =~ " ${user} " ]]; then
                    system_users+=("$user")
                fi
            done < <(cat "/usr/local/directadmin/data/users/users.list")
        fi
    fi

    # If no system users found, allow manual entry
    local system_user
    if [ ${#system_users[@]} -eq 0 ]; then
        system_user=$(dialog --colors --title "System User" --inputbox "Enter system/DirectAdmin username this MySQL user belongs to:" 8 60 3>&1 1>&2 2>&3)
        if [ -z "$system_user" ]; then
            return
        fi
    else
        # Create a menu to select from available system users
        local options=()
        for user in "${system_users[@]}"; do
            options+=("$user" "System user: $user")
        done
        options+=("manual" "Enter a different username")

        system_user=$(dialog --colors --title "Select System User" --menu "Select the system user this MySQL user belongs to:" 15 60 8 "${options[@]}" 3>&1 1>&2 2>&3)

        if [ -z "$system_user" ]; then
            return
        fi

        if [ "$system_user" = "manual" ]; then
            system_user=$(dialog --colors --title "System User" --inputbox "Enter system/DirectAdmin username this MySQL user belongs to:" 8 60 3>&1 1>&2 2>&3)
            if [ -z "$system_user" ]; then
                return
            fi
        fi
    fi

    # Get MySQL username
    local mysql_user
    mysql_user=$(dialog --colors --title "MySQL Username" --inputbox "Enter new MySQL username (or press Enter to use default format ${system_user}_user):" 8 70 3>&1 1>&2 2>&3)

    if [ -z "$mysql_user" ]; then
        mysql_user="${system_user}_user"
    fi

    # Check if user already exists
    local user_exists
    user_exists=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SELECT User FROM mysql.user WHERE User='$mysql_user';" 2>/dev/null | grep -c "$mysql_user")

    if [ "$user_exists" -gt 0 ]; then
        dialog --colors --title "Error" --msgbox "\Z1MySQL user '$mysql_user' already exists." 8 60
        return
    fi

    # Get password
    local password
    password=$(dialog --colors --title "MySQL Password" --passwordbox "Enter password for '$mysql_user':" 8 60 3>&1 1>&2 2>&3)

    if [ -z "$password" ]; then
        dialog --colors --title "Error" --msgbox "\Z1Password cannot be empty." 8 60
        return
    fi

    # Confirm password
    local confirm_password
    confirm_password=$(dialog --colors --title "Confirm Password" --passwordbox "Confirm password for '$mysql_user':" 8 60 3>&1 1>&2 2>&3)

    if [ "$password" != "$confirm_password" ]; then
        dialog --colors --title "Error" --msgbox "\Z1Passwords do not match." 8 60
        return
    fi

    # Create the user
    local create_result
    create_result=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "CREATE USER '$mysql_user'@'localhost' IDENTIFIED BY '$password';" 2>&1)

    if [ $? -ne 0 ]; then
        dialog --colors --title "Error" --msgbox "\Z1Failed to create MySQL user '$mysql_user'.\n\nError: $create_result" 10 60
        return
    fi

    # Ask if user wants to grant privileges to any database
    dialog --colors --title "Grant Privileges" --yesno "Do you want to grant privileges to '$mysql_user' on any database?" 8 60

    if [ $? -eq 0 ]; then
        # Get list of databases
        local databases
        databases=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SHOW DATABASES;" 2>/dev/null | grep -v -E "^(Database|information_schema|performance_schema|mysql|sys)$")

        if [ -z "$databases" ]; then
            dialog --colors --title "No Databases" --msgbox "\Z1No user databases found." 8 60
            return
        fi

        # Create options for database selection
        local db_options=()
        for db in $databases; do
            db_options+=("$db" "Database: $db")
        done

        # Allow selecting multiple databases
        local selected_dbs
        selected_dbs=$(dialog --colors --title "Select Databases" --checklist "Select databases to grant privileges to '$mysql_user':" 15 60 8 "${db_options[@]}" 3>&1 1>&2 2>&3)

        if [ -n "$selected_dbs" ]; then
            # Remove quotes from the output
            selected_dbs=$(echo "$selected_dbs" | tr -d '"')

            for db in $selected_dbs; do
                mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "GRANT ALL PRIVILEGES ON \`$db\`.* TO '$mysql_user'@'localhost';" 2>/dev/null

                if [ $? -ne 0 ]; then
                    dialog --colors --title "Warning" --msgbox "\Z3Warning: Failed to grant privileges on database '$db' to user '$mysql_user'." 8 70
                fi
            done

            # Flush privileges
            mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "FLUSH PRIVILEGES;" 2>/dev/null

            dialog --colors --title "Success" --msgbox "\Z6MySQL user '$mysql_user' created successfully and granted privileges on selected databases." 8 70
        else
            dialog --colors --title "Success" --msgbox "\Z6MySQL user '$mysql_user' created successfully without any database privileges." 8 70
        fi
    else
        dialog --colors --title "Success" --msgbox "\Z6MySQL user '$mysql_user' created successfully." 8 70
    fi
}

# Change MySQL user password
change_mysql_password() {
    # Get list of MySQL users
    local users
    users=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SELECT User FROM mysql.user WHERE User NOT IN ('root', 'debian-sys-maint', 'mysql.sys', 'mysql.session', 'mysql.infoschema');" 2>/dev/null | grep -v "User")

    if [ -z "$users" ]; then
        dialog --colors --title "No Users" --msgbox "\Z1No MySQL users found." 8 60
        return
    fi

    # Create options for user selection
    local user_options=()
    for user in $users; do
        user_options+=("$user" "MySQL user: $user")
    done

    # Select user
    local selected_user
    selected_user=$(dialog --colors --title "Select User" --menu "Select MySQL user to change password:" 15 60 8 "${user_options[@]}" 3>&1 1>&2 2>&3)

    if [ -z "$selected_user" ]; then
        return
    fi

    # Get new password
    local password
    password=$(dialog --colors --title "New Password" --passwordbox "Enter new password for '$selected_user':" 8 60 3>&1 1>&2 2>&3)

    if [ -z "$password" ]; then
        dialog --colors --title "Error" --msgbox "\Z1Password cannot be empty." 8 60
        return
    fi

    # Confirm password
    local confirm_password
    confirm_password=$(dialog --colors --title "Confirm Password" --passwordbox "Confirm new password for '$selected_user':" 8 60 3>&1 1>&2 2>&3)

    if [ "$password" != "$confirm_password" ]; then
        dialog --colors --title "Error" --msgbox "\Z1Passwords do not match." 8 60
        return
    fi

    # Change password
    local result
    result=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "ALTER USER '$selected_user'@'localhost' IDENTIFIED BY '$password';" 2>&1)

    if [ $? -ne 0 ]; then
        dialog --colors --title "Error" --msgbox "\Z1Failed to change password for '$selected_user'.\n\nError: $result" 10 60
        return
    fi

    # Flush privileges
    mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "FLUSH PRIVILEGES;" 2>/dev/null

    dialog --colors --title "Success" --msgbox "\Z6Password for MySQL user '$selected_user' changed successfully." 8 70
}

# Delete MySQL user
delete_mysql_user() {
    # Get list of MySQL users
    local users
    users=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SELECT User FROM mysql.user WHERE User NOT IN ('root', 'debian-sys-maint', 'mysql.sys', 'mysql.session', 'mysql.infoschema');" 2>/dev/null | grep -v "User")

    if [ -z "$users" ]; then
        dialog --colors --title "No Users" --msgbox "\Z1No MySQL users found." 8 60
        return
    fi

    # Create options for user selection
    local user_options=()
    for user in $users; do
        user_options+=("$user" "MySQL user: $user")
    done

    # Select user
    local selected_user
    selected_user=$(dialog --colors --title "Select User" --menu "Select MySQL user to delete:" 15 60 8 "${user_options[@]}" 3>&1 1>&2 2>&3)

    if [ -z "$selected_user" ]; then
        return
    fi

    # Confirm deletion
    dialog --colors --title "Confirm Deletion" --yesno "\Z1Are you sure you want to delete MySQL user '$selected_user'?\n\nThis action cannot be undone." 8 70

    if [ $? -ne 0 ]; then
        return
    fi

    # Delete user
    local result
    result=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "DROP USER '$selected_user'@'localhost';" 2>&1)

    if [ $? -ne 0 ]; then
        dialog --colors --title "Error" --msgbox "\Z1Failed to delete MySQL user '$selected_user'.\n\nError: $result" 10 60
        return
    fi

    # Flush privileges
    mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "FLUSH PRIVILEGES;" 2>/dev/null

    dialog --colors --title "Success" --msgbox "\Z6MySQL user '$selected_user' deleted successfully." 8 70
}

# Improved grant privileges with user checking
improved_grant_privileges() {
    local db_name="$1"
    local db_owner="$2"

    log_message "Verifying user '$db_owner' exists before granting privileges..."

    # Check if the user exists
    local user_exists
    user_exists=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "SELECT COUNT(*) FROM mysql.user WHERE User='$db_owner';" 2>/dev/null)

    if [ -z "$user_exists" ] || [ "$user_exists" -eq 0 ]; then
        log_message "User '$db_owner' doesn't exist. Creating user..."

        # Generate a secure random password
        local password
        password=$(openssl rand -base64 12)

        # Create the user
        if mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "CREATE USER '$db_owner'@'localhost' IDENTIFIED BY '$password';" 2>> "$LOG_FILE"; then
            log_message "User '$db_owner' created successfully with password: $password"
            log_message "IMPORTANT: Save this password securely!"
        else
            log_message "Failed to create user '$db_owner'"
            return 1
        fi
    fi

    log_message "Granting privileges on $db_name to user '$db_owner'..."
    if mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "GRANT ALL PRIVILEGES ON \`$db_name\`.* TO '$db_owner'@'localhost';" 2>> "$LOG_FILE"; then
        log_message "Privileges granted successfully to $db_owner on database $db_name"

        # Flush privileges to ensure changes take effect
        mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "FLUSH PRIVILEGES;" 2>> "$LOG_FILE"
        return 0
    else
        log_message "Failed to grant privileges on $db_name to $db_owner"
        return 1
    fi
}

# Manage database permissions
manage_database_permissions() {
    local db_name="$1"

    # Get list of databases
    local databases
    databases=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SHOW DATABASES;" 2>/dev/null | grep -v -E "^(Database|information_schema|performance_schema|mysql|sys)$")

    if [ -z "$databases" ]; then
        dialog --colors --title "No Databases" --msgbox "\Z1No user databases found." 8 60
        return 1
    fi

    # Create options for database selection
    local db_options=()
    for db in $databases; do
        db_options+=("$db" "Database: $db")
    done

    # Select database
    local selected_db
    selected_db=$(dialog --colors --title "Select Database" --menu "Select database to manage permissions:" 15 60 10 "${db_options[@]}" 3>&1 1>&2 2>&3)

    if [ -z "$selected_db" ]; then
        return 0
    fi

    # Get list of MySQL users
    local users
    users=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SELECT User FROM mysql.user WHERE User NOT IN ('root', 'debian-sys-maint', 'mysql.sys', 'mysql.session', 'mysql.infoschema');" 2>/dev/null | grep -v "User")

    if [ -z "$users" ]; then
        dialog --colors --title "No MySQL Users" --msgbox "\Z1No MySQL users found. Create users first." 8 60
        return 1
    fi

    # Show current permissions for this database
    local current_permissions
    current_permissions=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "
    SELECT
        User,
        Host,
        GROUP_CONCAT(DISTINCT PRIVILEGE_TYPE SEPARATOR ', ') AS 'Privileges'
    FROM information_schema.SCHEMA_PRIVILEGES
    WHERE TABLE_SCHEMA = '$selected_db'
    GROUP BY User, Host
    ORDER BY User;" 2>/dev/null)

    dialog --colors --title "Current Permissions" --msgbox "\Z5Current permissions for database '$selected_db':\Z0\n\n$current_permissions" 15 70

    # Permissions management menu
    local choice
    choice=$(dialog --colors --clear --backtitle "\Z6SDBTT Permission Management\Z0" \
        --title "Permissions for $selected_db" --menu "Choose an option:" 15 60 5 \
        "1" "\Z6Grant permissions to a user\Z0" \
        "2" "\Z6Revoke permissions from a user\Z0" \
        "3" "\Z6View detailed user permissions\Z0" \
        "4" "\Z6Transfer ownership\Z0" \
        "5" "\Z1Back\Z0" \
        3>&1 1>&2 2>&3)

    case $choice in
        1)
            grant_permissions_to_user "$selected_db"
            ;;
        2)
            revoke_permissions_from_user "$selected_db"
            ;;
        3)
            view_detailed_permissions "$selected_db"
            ;;
        4)
            transfer_database_ownership "$selected_db"
            ;;
        5|"")
            return 0
            ;;
    esac
}

# Grant permissions to a user for a specific database
grant_permissions_to_user() {
    local db_name="$1"

    # Get list of MySQL users
    local users
    users=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SELECT User FROM mysql.user WHERE User NOT IN ('root', 'debian-sys-maint', 'mysql.sys', 'mysql.session', 'mysql.infoschema');" 2>/dev/null | grep -v "User")

    if [ -z "$users" ]; then
        dialog --colors --title "No MySQL Users" --yesno "\Z1No MySQL users found. Would you like to create a new user?\Z0" 8 60

        if [ $? -eq 0 ]; then
            create_mysql_user
            # Refresh user list
            users=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SELECT User FROM mysql.user WHERE User NOT IN ('root', 'debian-sys-maint', 'mysql.sys', 'mysql.session', 'mysql.infoschema');" 2>/dev/null | grep -v "User")

            if [ -z "$users" ]; then
                return 1
            fi
        else
            return 1
        fi
    fi

    # Create options for user selection
    local user_options=()
    for user in $users; do
        user_options+=("$user" "MySQL user: $user")
    done

    # Add root as an option
    user_options+=("root" "MySQL user: root (system administrator)")

    # Select user
    local selected_user
    selected_user=$(dialog --colors --title "Select MySQL User" --menu "Select user to grant permissions:" 15 60 10 "${user_options[@]}" 3>&1 1>&2 2>&3)

    if [ -z "$selected_user" ]; then
        return 0
    fi

    # Choose privilege type
    local privilege_type
    privilege_type=$(dialog --colors --title "Privilege Type" --menu "Select type of privileges to grant:" 15 70 5 \
        "ALL" "All privileges (SELECT, INSERT, UPDATE, DELETE, etc.)" \
        "READONLY" "Read-only privileges (SELECT)" \
        "READWRITE" "Read-write privileges (SELECT, INSERT, UPDATE, DELETE)" \
        "CUSTOM" "Select custom privileges" \
        "CANCEL" "Cancel operation" \
        3>&1 1>&2 2>&3)

    if [ "$privilege_type" = "CANCEL" ] || [ -z "$privilege_type" ]; then
        return 0
    fi

    # For custom privileges, show a checklist
    local privileges=""

    if [ "$privilege_type" = "CUSTOM" ]; then
        local privilege_options=(
            "SELECT" "Read data from tables" "on"
            "INSERT" "Add new data to tables" "off"
            "UPDATE" "Modify existing data" "off"
            "DELETE" "Remove data from tables" "off"
            "CREATE" "Create new tables" "off"
            "DROP" "Delete tables" "off"
            "REFERENCES" "Create foreign keys" "off"
            "INDEX" "Create or drop indexes" "off"
            "ALTER" "Modify table structures" "off"
            "CREATE_TMP_TABLE" "Create temporary tables" "off"
            "LOCK_TABLES" "Lock tables" "off"
            "EXECUTE" "Execute stored procedures" "off"
            "CREATE_VIEW" "Create views" "off"
            "SHOW_VIEW" "View definitions" "off"
            "CREATE_ROUTINE" "Create stored procedures" "off"
            "ALTER_ROUTINE" "Modify stored procedures" "off"
            "TRIGGER" "Create triggers" "off"
            "EVENT" "Create events" "off"
        )

        local selected_privileges
        selected_privileges=$(dialog --colors --title "Select Privileges" --checklist "Select privileges to grant:" 20 70 15 "${privilege_options[@]}" 3>&1 1>&2 2>&3)

        if [ -z "$selected_privileges" ]; then
            return 0
        fi

        # Remove quotes from the output
        privileges=$(echo "$selected_privileges" | tr -d '"')
        privileges=$(echo "$privileges" | tr ' ' ',')
    else
        case $privilege_type in
            "ALL")
                privileges="ALL PRIVILEGES"
                ;;
            "READONLY")
                privileges="SELECT"
                ;;
            "READWRITE")
                privileges="SELECT,INSERT,UPDATE,DELETE"
                ;;
        esac
    fi

    # Specify grant scope
    local grant_scope
    grant_scope=$(dialog --colors --title "Grant Scope" --menu "Select the scope of the grant:" 15 70 3 \
        "DATABASE" "Grant on the entire database" \
        "TABLES" "Grant on specific tables" \
        "CANCEL" "Cancel operation" \
        3>&1 1>&2 2>&3)

    if [ "$grant_scope" = "CANCEL" ] || [ -z "$grant_scope" ]; then
        return 0
    fi

    # For specific tables, show a table selection dialog
    local tables_clause="*"

    if [ "$grant_scope" = "TABLES" ]; then
        # Get list of tables
        local tables
        tables=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "SHOW TABLES FROM \`$db_name\`;" 2>/dev/null)

        if [ -z "$tables" ]; then
            dialog --colors --title "No Tables" --msgbox "\Z1No tables found in database '$db_name'." 8 60
            return 1
        fi

        # Create options for table selection
        local table_options=()
        for table in $tables; do
            table_options+=("$table" "Table: $table" "off")
        done

        # Allow selecting multiple tables
        local selected_tables
        selected_tables=$(dialog --colors --title "Select Tables" --checklist "Select tables to grant privileges on:" 20 70 15 "${table_options[@]}" 3>&1 1>&2 2>&3)

        if [ -z "$selected_tables" ]; then
            return 0
        fi

        # Remove quotes from the output
        selected_tables=$(echo "$selected_tables" | tr -d '"')

        # For each selected table, create a grant statement
        for table in $selected_tables; do
            # Grant privileges to the specified user on the specified table
            mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "GRANT $privileges ON \`$db_name\`.\`$table\` TO '$selected_user'@'localhost';" 2>/dev/null
        done

        # Flush privileges
        mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "FLUSH PRIVILEGES;" 2>/dev/null

        dialog --colors --title "Privileges Granted" --msgbox "\Z6Privileges ($privileges) granted to user '$selected_user' on selected tables in database '$db_name'." 8 70
    else
        # Grant privileges to the entire database
        mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "GRANT $privileges ON \`$db_name\`.* TO '$selected_user'@'localhost';" 2>/dev/null

        # Flush privileges
        mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "FLUSH PRIVILEGES;" 2>/dev/null

        dialog --colors --title "Privileges Granted" --msgbox "\Z6Privileges ($privileges) granted to user '$selected_user' on database '$db_name'." 8 70
    fi
}

# Revoke permissions from a user for a specific database
revoke_permissions_from_user() {
    local db_name="$1"

    # Get users with permissions on this database
    local users_with_permissions
    users_with_permissions=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "
    SELECT DISTINCT User
    FROM information_schema.SCHEMA_PRIVILEGES
    WHERE TABLE_SCHEMA = '$db_name'
    ORDER BY User;" 2>/dev/null | grep -v "User")

    if [ -z "$users_with_permissions" ]; then
        dialog --colors --title "No Permissions" --msgbox "\Z1No users with specific permissions found for database '$db_name'." 8 70
        return 1
    fi

    # Create options for user selection
    local user_options=()
    for user in $users_with_permissions; do
        # Get privileges for this user
        local user_privileges
        user_privileges=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "
        SELECT GROUP_CONCAT(DISTINCT PRIVILEGE_TYPE SEPARATOR ', ')
        FROM information_schema.SCHEMA_PRIVILEGES
        WHERE TABLE_SCHEMA = '$db_name' AND GRANTEE LIKE '%''$user''%';" 2>/dev/null | grep -v "GROUP_CONCAT")

        user_options+=("$user" "MySQL user: $user (Privileges: $user_privileges)")
    done

    # Select user
    local selected_user
    selected_user=$(dialog --colors --title "Select MySQL User" --menu "Select user to revoke permissions from:" 15 70 10 "${user_options[@]}" 3>&1 1>&2 2>&3)

    if [ -z "$selected_user" ]; then
        return 0
    fi

    # Confirm revocation
    dialog --colors --title "Confirm Revocation" --yesno "\Z3Are you sure you want to revoke ALL privileges for user '$selected_user' on database '$db_name'?\Z0" 8 70

    if [ $? -ne 0 ]; then
        return 0
    fi

    # Revoke privileges
    mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "REVOKE ALL PRIVILEGES ON \`$db_name\`.* FROM '$selected_user'@'localhost';" 2>/dev/null

    # Flush privileges
    mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "FLUSH PRIVILEGES;" 2>/dev/null

    dialog --colors --title "Privileges Revoked" --msgbox "\Z6All privileges revoked from user '$selected_user' on database '$db_name'." 8 70
}

# View detailed permissions for a database
view_detailed_permissions() {
    local db_name="$1"

    # Get detailed privileges
    local detailed_permissions
    detailed_permissions=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "
    SELECT
        GRANTEE AS 'User',
        PRIVILEGE_TYPE AS 'Privilege',
        IS_GRANTABLE AS 'Can Grant',
        TABLE_NAME AS 'Table'
    FROM information_schema.TABLE_PRIVILEGES
    WHERE TABLE_SCHEMA = '$db_name'
    ORDER BY GRANTEE, TABLE_NAME, PRIVILEGE_TYPE;" 2>/dev/null)

    if [ -z "$detailed_permissions" ] || [ "$(echo "$detailed_permissions" | wc -l)" -le 1 ]; then
        # Try schema privileges if no table privileges
        detailed_permissions=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "
        SELECT
            GRANTEE AS 'User',
            PRIVILEGE_TYPE AS 'Privilege',
            IS_GRANTABLE AS 'Can Grant',
            'ALL TABLES' AS 'Table'
        FROM information_schema.SCHEMA_PRIVILEGES
        WHERE TABLE_SCHEMA = '$db_name'
        ORDER BY GRANTEE, PRIVILEGE_TYPE;" 2>/dev/null)

        if [ -z "$detailed_permissions" ] || [ "$(echo "$detailed_permissions" | wc -l)" -le 1 ]; then
            dialog --colors --title "No Permissions" --msgbox "\Z1No detailed permissions found for database '$db_name'." 8 70
            return 1
        fi
    fi

    # Format the output
    local formatted_permissions
    formatted_permissions=$(echo "$detailed_permissions" | sed 's/User/\\Z5User\\Z0/g' | sed 's/Privilege/\\Z5Privilege\\Z0/g' | sed 's/Can Grant/\\Z5Can Grant\\Z0/g' | sed 's/Table/\\Z5Table\\Z0/g')

    dialog --colors --title "Detailed Permissions for $db_name" --msgbox "$formatted_permissions" 25 80
}

# Transfer database ownership
transfer_database_ownership() {
    local db_name="$1"

    # Get list of MySQL users
    local users
    users=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SELECT User FROM mysql.user WHERE User NOT IN ('root', 'debian-sys-maint', 'mysql.sys', 'mysql.session', 'mysql.infoschema');" 2>/dev/null | grep -v "User")

    if [ -z "$users" ]; then
        dialog --colors --title "No MySQL Users" --yesno "\Z1No MySQL users found. Would you like to create a new user?\Z0" 8 60

        if [ $? -eq 0 ]; then
            create_mysql_user
            # Refresh user list
            users=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SELECT User FROM mysql.user WHERE User NOT IN ('root', 'debian-sys-maint', 'mysql.sys', 'mysql.session', 'mysql.infoschema');" 2>/dev/null | grep -v "User")

            if [ -z "$users" ]; then
                return 1
            fi
        else
            return 1
        fi
    fi

    # Create options for user selection
    local user_options=()
    for user in $users; do
        user_options+=("$user" "MySQL user: $user")
    done

    # Add root as an option
    user_options+=("root" "MySQL user: root (system administrator)")

    # Select new owner
    local new_owner
    new_owner=$(dialog --colors --title "Select New Owner" --menu "Select new owner for database '$db_name':" 15 60 10 "${user_options[@]}" 3>&1 1>&2 2>&3)

    if [ -z "$new_owner" ]; then
        return 0
    fi

    # Confirm transfer
    dialog --colors --title "Confirm Transfer" --yesno "\Z3Are you sure you want to transfer ownership of database '$db_name' to user '$new_owner'?\n\nThis will revoke privileges from other users and grant ALL privileges to the new owner.\Z0" 10 70

    if [ $? -ne 0 ]; then
        return 0
    fi

    # Transfer ownership by granting all privileges to the new owner
    mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "GRANT ALL PRIVILEGES ON \`$db_name\`.* TO '$new_owner'@'localhost';" 2>/dev/null

    # Update database owner in configuration
    DB_OWNER="$new_owner"

    # Flush privileges
    mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "FLUSH PRIVILEGES;" 2>/dev/null

    dialog --colors --title "Ownership Transferred" --msgbox "\Z6Ownership of database '$db_name' transferred to user '$new_owner'." 8 70
}

# Assign multiple databases to a user
database_user_assignment() {
    # Get list of MySQL users
    local users
    users=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SELECT User FROM mysql.user WHERE User NOT IN ('root', 'debian-sys-maint', 'mysql.sys', 'mysql.session', 'mysql.infoschema');" 2>/dev/null | grep -v "User")

    if [ -z "$users" ]; then
        dialog --colors --title "No MySQL Users" --yesno "\Z1No MySQL users found. Would you like to create a new user?\Z0" 8 60

        if [ $? -eq 0 ]; then
            create_mysql_user
            # Refresh user list
            users=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SELECT User FROM mysql.user WHERE User NOT IN ('root', 'debian-sys-maint', 'mysql.sys', 'mysql.session', 'mysql.infoschema');" 2>/dev/null | grep -v "User")

            if [ -z "$users" ]; then
                return 1
            fi
        else
            return 1
        fi
    fi

    # Create options for user selection
    local user_options=()
    for user in $users; do
        user_options+=("$user" "MySQL user: $user")
    done

    # Select user
    local selected_user
    selected_user=$(dialog --colors --title "Select MySQL User" --menu "Select user to assign databases to:" 15 60 10 "${user_options[@]}" 3>&1 1>&2 2>&3)

    if [ -z "$selected_user" ]; then
        return 0
    fi

    # Get list of databases
    local databases
    databases=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SHOW DATABASES;" 2>/dev/null | grep -v -E "^(Database|information_schema|performance_schema|mysql|sys)$")

    if [ -z "$databases" ]; then
        dialog --colors --title "No Databases" --msgbox "\Z1No user databases found." 8 60
        return 1
    fi

    # Get databases this user already has access to
    local user_dbs
    user_dbs=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "
    SELECT DISTINCT TABLE_SCHEMA
    FROM information_schema.SCHEMA_PRIVILEGES
    WHERE GRANTEE LIKE '%''$selected_user''%'
    ORDER BY TABLE_SCHEMA;" 2>/dev/null | grep -v "TABLE_SCHEMA")

    # Create options for database selection
    local db_options=()
    for db in $databases; do
        local is_assigned="off"
        # Check if this database is already assigned to the user
        if echo "$user_dbs" | grep -q "^$db$"; then
            is_assigned="on"
        fi

        db_options+=("$db" "Database: $db" "$is_assigned")
    done

    # Select databases
    local selected_dbs
    selected_dbs=$(dialog --colors --title "Select Databases" --checklist "Select databases to assign to user '$selected_user':" 20 70 15 "${db_options[@]}" 3>&1 1>&2 2>&3)

    if [ -z "$selected_dbs" ]; then
        return 0
    fi

    # Remove quotes from the output
    selected_dbs=$(echo "$selected_dbs" | tr -d '"')

    # Choose privilege type
    local privilege_type
    privilege_type=$(dialog --colors --title "Privilege Type" --menu "Select type of privileges to grant:" 15 70 5 \
        "ALL" "All privileges (SELECT, INSERT, UPDATE, DELETE, etc.)" \
        "READONLY" "Read-only privileges (SELECT)" \
        "READWRITE" "Read-write privileges (SELECT, INSERT, UPDATE, DELETE)" \
        "CUSTOM" "Select custom privileges" \
        "CANCEL" "Cancel operation" \
        3>&1 1>&2 2>&3)

    if [ "$privilege_type" = "CANCEL" ] || [ -z "$privilege_type" ]; then
        return 0
    fi

    # For custom privileges, show a checklist
    local privileges=""

    if [ "$privilege_type" = "CUSTOM" ]; then
        local privilege_options=(
            "SELECT" "Read data from tables" "on"
            "INSERT" "Add new data to tables" "off"
            "UPDATE" "Modify existing data" "off"
            "DELETE" "Remove data from tables" "off"
            "CREATE" "Create new tables" "off"
            "DROP" "Delete tables" "off"
            "REFERENCES" "Create foreign keys" "off"
            "INDEX" "Create or drop indexes" "off"
            "ALTER" "Modify table structures" "off"
            "CREATE_TMP_TABLE" "Create temporary tables" "off"
            "LOCK_TABLES" "Lock tables" "off"
            "EXECUTE" "Execute stored procedures" "off"
            "CREATE_VIEW" "Create views" "off"
            "SHOW_VIEW" "View definitions" "off"
            "CREATE_ROUTINE" "Create stored procedures" "off"
            "ALTER_ROUTINE" "Modify stored procedures" "off"
            "TRIGGER" "Create triggers" "off"
            "EVENT" "Create events" "off"
        )

        local selected_privileges
        selected_privileges=$(dialog --colors --title "Select Privileges" --checklist "Select privileges to grant:" 20 70 15 "${privilege_options[@]}" 3>&1 1>&2 2>&3)

        if [ -z "$selected_privileges" ]; then
            return 0
        fi

        # Remove quotes from the output
        privileges=$(echo "$selected_privileges" | tr -d '"')
        privileges=$(echo "$privileges" | tr ' ' ',')
    else
        case $privilege_type in
            "ALL")
                privileges="ALL PRIVILEGES"
                ;;
            "READONLY")
                privileges="SELECT"
                ;;
            "READWRITE")
                privileges="SELECT,INSERT,UPDATE,DELETE"
                ;;
        esac
    fi

    # Create a temporary log file for grant progress
    local grant_log="/tmp/sdbtt_grant_$.log"
    echo "Starting grant of privileges for user '$selected_user'" > "$grant_log"

    # Display progress dialog
    dialog --title "Grant Progress" --tailbox "$grant_log" 15 70 &
    local dialog_pid=$!

    # Run the grant process in background
    {
        # First, revoke existing privileges to set a clean slate for selected DBs
        for db in $selected_dbs; do
            echo "Revoking existing privileges on $db..." >> "$grant_log"
            mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "REVOKE ALL PRIVILEGES ON \`$db\`.* FROM '$selected_user'@'localhost';" 2>/dev/null
        done

        # Now grant the new privileges to each database
        for db in $selected_dbs; do
            echo "Granting $privileges on $db..." >> "$grant_log"
            if mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "GRANT $privileges ON \`$db\`.* TO '$selected_user'@'localhost';" 2>/dev/null; then
                echo "Successfully granted privileges on $db" >> "$grant_log"
            else
                echo "Failed to grant privileges on $db" >> "$grant_log"
            fi
        done

        # Flush privileges to ensure changes take effect
        echo "Flushing privileges..." >> "$grant_log"
        mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "FLUSH PRIVILEGES;" 2>/dev/null

        echo "Grant operation completed" >> "$grant_log"

        # Kill the dialog process
        kill $dialog_pid 2>/dev/null || true

        # Display completion message
        dialog --colors --title "Privileges Granted" --msgbox "\Z6Privileges ($privileges) granted to user '$selected_user' on selected databases." 8 70

        # Clean up temporary log
        rm -f "$grant_log"

    } &

    # Wait for the background process to complete
    wait
}