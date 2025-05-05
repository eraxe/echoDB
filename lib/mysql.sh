#!/bin/bash
# SDBTT MySQL Operations Module
# Handles core MySQL database operations

# Function to check and test MySQL connection
check_mysql_connection() {
    if [ -z "$MYSQL_USER" ] || [ -z "$MYSQL_PASS" ]; then
        return 1
    fi

    if mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SELECT 1" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Verify database exists
verify_database_exists() {
    local db_name="$1"

    local db_exists
    db_exists=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '$db_name';" 2>/dev/null | grep -v "SCHEMA_NAME")

    if [ -n "$db_exists" ]; then
        return 0
    else
        return 1
    fi
}

# Create and initialize the database
create_database() {
    local db_name="$1"
    log_message "Creating database: $db_name with utf8mb4 charset"

    mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "DROP DATABASE IF EXISTS \`$db_name\`;" 2>> "$LOG_FILE" || {
        log_message "Warning: Could not drop database $db_name. Continuing..."
    }

    mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "CREATE DATABASE \`$db_name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>> "$LOG_FILE" || {
        error_exit "Failed to create database $db_name"
    }

    # Set encoding parameters - Make sure to use strict utf8mb4
    mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" "$db_name" -e "
        SET NAMES utf8mb4;
        SET character_set_client = utf8mb4;
        SET character_set_connection = utf8mb4;
        SET character_set_results = utf8mb4;
        SET collation_connection = utf8mb4_unicode_ci;" 2>> "$LOG_FILE"
}

# Main MySQL management menu with enhanced options
enhanced_mysql_admin_menu() {
    if [ -z "$MYSQL_USER" ] || [ -z "$MYSQL_PASS" ]; then
        dialog --colors --title "MySQL Admin" --msgbox "\Z1MySQL credentials not configured.\n\nPlease set your MySQL username and password first." 8 60
        return
    fi

    while true; do
        local choice
        choice=$(dialog --colors --clear --backtitle "\Z6SDBTT MySQL Administration\Z0" \
            --title "MySQL Administration" --menu "Choose an option:" 20 70 18 \
            "1" "\Z6List All Databases\Z0" \
            "2" "\Z6View Database Details\Z0" \
            "3" "\Z6Backup Database\Z0" \
            "4" "\Z6Restore Database from Backup\Z0" \
            "5" "\Z6Rename Database\Z0" \
            "6" "\Z6Remove Database\Z0" \
            "7" "\Z6Manage Database Permissions\Z0" \
            "8" "\Z6Show Database Size\Z0" \
            "9" "\Z6Optimize Tables\Z0" \
            "10" "\Z6Check Database Integrity\Z0" \
            "11" "\Z6MySQL Status\Z0" \
            "12" "\Z6List All Users\Z0" \
            "13" "\Z6Show User Privileges\Z0" \
            "14" "\Z6Create MySQL User\Z0" \
            "15" "\Z6Change User Password\Z0" \
            "16" "\Z6Delete MySQL User\Z0" \
            "17" "\Z6Database-to-User Assignment\Z0" \
            "18" "\Z1Back to Main Menu\Z0" \
            3>&1 1>&2 2>&3)

        case $choice in
            1) list_databases ;;
            2)
                # First get a list of databases to select from
                local db_list=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SHOW DATABASES;" 2>/dev/null | grep -v -E "^(Database|information_schema|performance_schema|mysql|sys)$")
                local db_options=()
                for db in $db_list; do
                    db_options+=("$db" "Database: $db")
                done

                if [ ${#db_options[@]} -eq 0 ]; then
                    dialog --colors --title "No Databases" --msgbox "\Z1No databases found." 8 60
                else
                    local selected_db=$(dialog --colors --title "Select Database" --menu "Select a database to view:" 15 60 10 "${db_options[@]}" 3>&1 1>&2 2>&3)
                    if [ -n "$selected_db" ]; then
                        show_database_details "$selected_db"
                    fi
                fi
                ;;
            3)
                # First get a list of databases to select from
                local db_list=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SHOW DATABASES;" 2>/dev/null | grep -v -E "^(Database|information_schema|performance_schema|mysql|sys)$")
                local db_options=()
                for db in $db_list; do
                    db_options+=("$db" "Database: $db")
                done

                if [ ${#db_options[@]} -eq 0 ]; then
                    dialog --colors --title "No Databases" --msgbox "\Z1No databases found." 8 60
                else
                    local selected_db=$(dialog --colors --title "Select Database" --menu "Select a database to backup:" 15 60 10 "${db_options[@]}" 3>&1 1>&2 2>&3)
                    if [ -n "$selected_db" ]; then
                        backup_database_with_progress "$selected_db"
                    fi
                fi
                ;;
            4) restore_database_with_progress ;;
            5) rename_database ;;
            6) remove_database ;;
            7)
                # First get a list of databases to select from
                local db_list=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SHOW DATABASES;" 2>/dev/null | grep -v -E "^(Database|information_schema|performance_schema|mysql|sys)$")
                local db_options=()
                for db in $db_list; do
                    db_options+=("$db" "Database: $db")
                done

                if [ ${#db_options[@]} -eq 0 ]; then
                    dialog --colors --title "No Databases" --msgbox "\Z1No databases found." 8 60
                else
                    local selected_db=$(dialog --colors --title "Select Database" --menu "Select a database to manage permissions:" 15 60 10 "${db_options[@]}" 3>&1 1>&2 2>&3)
                    if [ -n "$selected_db" ]; then
                        manage_database_permissions "$selected_db"
                    fi
                fi
                ;;
            8) show_database_size ;;
            9) optimize_tables ;;
            10) check_database_integrity ;;
            11) show_mysql_status ;;
            12) list_users ;;
            13) show_user_privileges ;;
            14) create_mysql_user ;;
            15) change_mysql_password ;;
            16) delete_mysql_user ;;
            17) database_user_assignment ;;
            18|"") break ;;
        esac
    done
}

# List all databases with enhanced formatting
list_databases() {
    local result
    result=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SHOW DATABASES;" 2>/dev/null)

    if [ $? -ne 0 ]; then
        dialog --colors --title "Error" --msgbox "\Z1Failed to retrieve databases. Check your MySQL credentials." 8 60
        return
    fi

    # Format the output for display with consistent coloring
    local formatted_result
    formatted_result=$(echo "$result" | sed 's/Database/\\Z5Database\\Z0/g')

    dialog --colors --title "MySQL Databases" --msgbox "$formatted_result" 20 60
}

# Enhanced database information display with more details
show_database_details() {
    local db_name="$1"

    # Verify database exists
    if ! verify_database_exists "$db_name"; then
        dialog --colors --title "Error" --msgbox "\Z1Database '$db_name' does not exist." 8 60
        return 1
    fi

    # Get database statistics
    local result=""

    # General database info
    local charset=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "SELECT DEFAULT_CHARACTER_SET_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = '$db_name';" 2>/dev/null)
    local collation=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "SELECT DEFAULT_COLLATION_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = '$db_name';" 2>/dev/null)
    local creation_time=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "SELECT CREATE_TIME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = '$db_name';" 2>/dev/null)

    # Table statistics
    local tables_count=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = '$db_name';" 2>/dev/null)
    local views_count=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "SELECT COUNT(*) FROM information_schema.VIEWS WHERE TABLE_SCHEMA = '$db_name';" 2>/dev/null)
    local triggers_count=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "SELECT COUNT(*) FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = '$db_name';" 2>/dev/null)
    local routines_count=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = '$db_name';" 2>/dev/null)

    # Size calculations
    local size_info=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "
    SELECT
        ROUND(SUM(data_length) / 1024 / 1024, 2) as data_size,
        ROUND(SUM(index_length) / 1024 / 1024, 2) as index_size,
        ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) as total_size
    FROM information_schema.TABLES
    WHERE table_schema = '$db_name';" 2>/dev/null)

    local data_size=$(echo "$size_info" | awk '{print $1}')
    local index_size=$(echo "$size_info" | awk '{print $2}')
    local total_size=$(echo "$size_info" | awk '{print $3}')

    # Format the output with detailed information
    result="\Z5Database Details: $db_name\Z0\n\n"
    result+="Character Set: \Z6$charset\Z0\n"
    result+="Collation: \Z6$collation\Z0\n"
    result+="Creation Time: \Z6$creation_time\Z0\n\n"

    result+="\Z5Structure:\Z0\n"
    result+="Tables: \Z6$tables_count\Z0\n"
    result+="Views: \Z6$views_count\Z0\n"
    result+="Triggers: \Z6$triggers_count\Z0\n"
    result+="Stored Procedures/Functions: \Z6$routines_count\Z0\n\n"

    result+="\Z5Size Information:\Z0\n"
    result+="Data Size: \Z6${data_size} MB\Z0\n"
    result+="Index Size: \Z6${index_size} MB\Z0\n"
    result+="Total Size: \Z6${total_size} MB\Z0\n\n"

    # Get table list with row counts and sizes
    local tables_info=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "
    SELECT
        t.TABLE_NAME AS 'Table Name',
        t.TABLE_ROWS AS 'Approx. Rows',
        t.ENGINE AS 'Engine',
        ROUND((t.DATA_LENGTH + t.INDEX_LENGTH) / 1024 / 1024, 2) AS 'Size (MB)'
    FROM information_schema.TABLES t
    WHERE t.TABLE_SCHEMA = '$db_name'
    ORDER BY (t.DATA_LENGTH + t.INDEX_LENGTH) DESC;" 2>/dev/null)

    if [ -n "$tables_info" ]; then
        result+="\Z5Table Information:\Z0\n$tables_info\n\n"
    fi

    # Get users with privileges on this database
    local users_info=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "
    SELECT
        User,
        Host,
        SUBSTRING_INDEX(GROUP_CONCAT(PRIVILEGE_TYPE), ',', 3) AS 'Sample Privileges'
    FROM information_schema.USER_PRIVILEGES
    WHERE GRANTEE LIKE '%@%'
    GROUP BY User, Host
    ORDER BY User;" 2>/dev/null)

    if [ -n "$users_info" ]; then
        result+="\Z5User Access:\Z0\n$users_info\n"
    fi

    # Display the formatted output
    dialog --colors --title "Database Information: $db_name" --msgbox "$result" 30 80
}

# Show database sizes with enhanced formatting
show_database_size() {
    local result
    result=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "
    SELECT
        table_schema AS 'Database',
        ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)'
    FROM information_schema.tables
    GROUP BY table_schema
    ORDER BY SUM(data_length + index_length) DESC;" 2>/dev/null)

    if [ $? -ne 0 ]; then
        dialog --colors --title "Error" --msgbox "\Z1Failed to retrieve database sizes." 8 60
        return
    fi

    # Format the output with enhanced coloring
    local formatted_result
    formatted_result=$(echo "$result" | sed 's/Database/\\Z5Database\\Z0/g' | sed 's/Size (MB)/\\Z5Size (MB)\\Z0/g')

    dialog --colors --title "Database Sizes" --msgbox "$formatted_result" 20 70
}

# Check database integrity with enhanced UI
check_database_integrity() {
    local db_name
    db_name=$(dialog --colors --title "Check Database Integrity" --inputbox "Enter database name:" 8 60 3>&1 1>&2 2>&3)

    if [ -z "$db_name" ]; then
        return
    fi

    # Check if database exists
    local db_exists
    db_exists=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SHOW DATABASES LIKE '$db_name';" 2>/dev/null)

    if [ -z "$db_exists" ]; then
        dialog --colors --title "Error" --msgbox "\Z1Database '$db_name' does not exist." 8 60
        return
    fi

    # Get all tables in the database
    local tables
    tables=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SHOW TABLES FROM \`$db_name\`;" 2>/dev/null | tail -n +2)

    if [ -z "$tables" ]; then
        dialog --colors --title "No Tables" --msgbox "\Z1Database '$db_name' has no tables to check." 8 60
        return
    fi

    # Create a temporary log file for check progress
    local check_log_file="/tmp/sdbtt_check_$.log"
    echo "Starting integrity check for database '$db_name'" > "$check_log_file"

    # Calculate total tables for progress
    local total=$(echo "$tables" | wc -l)

    # Use a split display - progress gauge on top, log tail at bottom
    dialog --colors --title "Checking Database Integrity" \
           --mixedgauge "Preparing to check tables in $db_name..." 0 70 0 \
           "Progress" "0%" "Remaining" "100%" 2>/dev/null &
    local dialog_pid=$!

    # Open a tail dialog for the log
    dialog --colors --title "Check Log" --begin 10 5 --tailbox "$check_log_file" 15 70 &
    local tail_pid=$!

    {
        local i=0
        for table in $tables; do
            i=$((i + 1))
            progress=$((i * 100 / total))
            remaining=$((100 - progress))

            # Update the log file
            echo "[$i/$total] Checking table: $table" >> "$check_log_file"

            # Update the progress gauge
            dialog --colors --title "Checking Database Integrity" \
                   --mixedgauge "Checking tables in $db_name..." 0 70 $progress \
                   "Progress" "$progress%" "Remaining" "$remaining%" 2>/dev/null

            # Perform the check
            result=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "CHECK TABLE \`$db_name\`.\`$table\`;" 2>&1)
            echo "Result: " >> "$check_log_file"
            echo "$result" >> "$check_log_file"
            echo "----------------------------------------" >> "$check_log_file"

            # Small delay for visibility
            sleep 0.1
        done

        # Mark as complete
        echo "Integrity check complete for all $total tables in $db_name" >> "$check_log_file"

        # Final progress update - 100%
        dialog --colors --title "Checking Database Integrity" \
               --mixedgauge "Checking tables in $db_name..." 0 70 100 \
               "Progress" "100%" "Remaining" "0%" 2>/dev/null

        # Give time to see the final state
        sleep 2

        # Kill the dialog processes
        kill $dialog_pid 2>/dev/null || true
        kill $tail_pid 2>/dev/null || true

        # Show completion dialog
        dialog --colors --title "Integrity Check Complete" --msgbox "\Z6All tables in database '$db_name' have been checked.\n\nSee full details in the check log." 8 70

        # Display the log in a scrollable viewer
        dialog --colors --title "Integrity Check Results" --textbox "$check_log_file" 20 76

        # Clean up
        rm -f "$check_log_file"

    } &

    # Wait for the background process to complete
    wait
}

# Optimize tables in a database with progress bar and log display
optimize_tables() {
    local db_name
    db_name=$(dialog --colors --title "Optimize Tables" --inputbox "Enter database name:" 8 60 3>&1 1>&2 2>&3)

    if [ -z "$db_name" ]; then
        return
    fi

    # Check if database exists
    local db_exists
    db_exists=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SHOW DATABASES LIKE '$db_name';" 2>/dev/null)

    if [ -z "$db_exists" ]; then
        dialog --colors --title "Error" --msgbox "\Z1Database '$db_name' does not exist." 8 60
        return
    fi

    # Get all tables in the database
    local tables
    tables=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SHOW TABLES FROM \`$db_name\`;" 2>/dev/null | tail -n +2)

    if [ -z "$tables" ]; then
        dialog --colors --title "No Tables" --msgbox "\Z6Database '$db_name' has no tables to optimize." 8 60
        return
    fi

    # Create a temporary log file for optimization progress
    local opt_log_file="/tmp/sdbtt_optimize_$.log"
    echo "Starting optimization for database '$db_name'" > "$opt_log_file"

    # Calculate total tables for progress
    local total=$(echo "$tables" | wc -l)

    # Use a split display - progress gauge on top, log tail at bottom
    dialog --colors --title "Optimizing Database" \
           --mixedgauge "Preparing to optimize tables in $db_name..." 0 70 0 \
           "Progress" "0%" "Remaining" "100%" 2>/dev/null &
    local dialog_pid=$!

    # Open a tail dialog for the log
    dialog --colors --title "Optimization Log" --begin 10 5 --tailbox "$opt_log_file" 15 70 &
    local tail_pid=$!

    {
        local i=0
        for table in $tables; do
            i=$((i + 1))
            progress=$((i * 100 / total))
            remaining=$((100 - progress))

            # Update the log file
            echo "[$i/$total] Optimizing table: $table" >> "$opt_log_file"

            # Update the progress gauge
            dialog --colors --title "Optimizing Database" \
                   --mixedgauge "Optimizing tables in $db_name..." 0 70 $progress \
                   "Progress" "$progress%" "Remaining" "$remaining%" 2>/dev/null

            # Perform the optimization
            result=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "OPTIMIZE TABLE \`$db_name\`.\`$table\`;" 2>&1)
            echo "Result: $result" >> "$opt_log_file"
            echo "----------------------------------------" >> "$opt_log_file"

            # Small delay for visibility
            sleep 0.1
        done

        # Mark as complete
        echo "Optimization complete for all $total tables in $db_name" >> "$opt_log_file"

        # Final progress update - 100%
        dialog --colors --title "Optimizing Database" \
               --mixedgauge "Optimizing tables in $db_name..." 0 70 100 \
               "Progress" "100%" "Remaining" "0%" 2>/dev/null

        # Give time to see the final state
        sleep 2

        # Kill the dialog processes
        kill $dialog_pid 2>/dev/null || true
        kill $tail_pid 2>/dev/null || true

        # Show completion dialog
        dialog --colors --title "Optimization Complete" --msgbox "\Z6All tables in database '$db_name' have been optimized.\n\nSee full details in the optimization log." 8 70

        # Display the log in a scrollable viewer
        dialog --colors --title "Optimization Results" --textbox "$opt_log_file" 20 76

        # Clean up
        rm -f "$opt_log_file"

    } &

    # Wait for the background process to complete
    wait
}

# Show MySQL server status with enhanced formatting
show_mysql_status() {
    local result
    result=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SHOW STATUS;" 2>/dev/null)

    if [ $? -ne 0 ]; then
        dialog --colors --title "Error" --msgbox "\Z1Failed to retrieve MySQL status." 8 60
        return
    fi

    # Format important status variables with enhanced coloring
    local formatted_result
    formatted_result=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "
    SHOW GLOBAL STATUS WHERE
    Variable_name = 'Uptime' OR
    Variable_name = 'Threads_connected' OR
    Variable_name = 'Queries' OR
    Variable_name = 'Connections' OR
    Variable_name = 'Aborted_connects' OR
    Variable_name = 'Created_tmp_tables' OR
    Variable_name = 'Innodb_buffer_pool_reads' OR
    Variable_name = 'Innodb_buffer_pool_read_requests' OR
    Variable_name = 'Bytes_received' OR
    Variable_name = 'Bytes_sent';" 2>/dev/null)

    # Format MySQL version with enhanced coloring
    local version
    version=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SELECT VERSION();" 2>/dev/null)

    # Format the output with enhanced theming
    formatted_result=$(echo -e "\Z5MySQL Version:\Z0\n$version\n\n\Z5Status Variables:\Z0\n$formatted_result" |
                      sed 's/Variable_name/\\Z6Variable_name\\Z0/g' |
                      sed 's/Value/\\Z6Value\\Z0/g')

    dialog --colors --title "MySQL Server Status" --msgbox "$formatted_result" 20 70
}

# Remove database with safety checks
remove_database() {
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
        # Get database size
        local size=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "
            SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2)
            FROM information_schema.tables
            WHERE table_schema = '$db';" 2>/dev/null)

        # Get table count
        local tables=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "
            SELECT COUNT(*)
            FROM information_schema.tables
            WHERE table_schema = '$db';" 2>/dev/null)

        db_options+=("$db" "Database: $db (Size: ${size}MB, Tables: $tables)")
    done

    # Select database to remove
    local selected_db
    selected_db=$(dialog --colors --title "Select Database" --menu "Select database to remove:" 15 70 10 "${db_options[@]}" 3>&1 1>&2 2>&3)

    if [ -z "$selected_db" ]; then
        return 0
    fi

    # First confirmation with warning
    dialog --colors --title "Warning" --defaultno --yesno "\Z1WARNING: You are about to permanently delete the database '$selected_db'.\n\nThis action CANNOT be undone.\n\nAre you sure you want to continue?\Z0" 10 70

    if [ $? -ne 0 ]; then
        return 0
    fi

    # Ask if user wants to backup before deletion
    dialog --colors --title "Backup Before Deletion" --yesno "\Z3Would you like to create a backup of the database before deleting it?\Z0" 8 70

    if [ $? -eq 0 ]; then
        # Create backup
        dialog --infobox "Creating backup of database '$selected_db' before deletion..." 5 60
        local backup_file=$(backup_database "$selected_db")

        if [ -n "$backup_file" ] && [ -f "$backup_file" ]; then
            dialog --colors --title "Backup Created" --msgbox "\Z6Backup of database '$selected_db' created successfully at:\n\n$backup_file\Z0" 8 70
        else
            dialog --colors --title "Backup Failed" --yesno "\Z1Failed to create backup of database '$selected_db'.\n\nDo you still want to proceed with deletion?\Z0" 8 70

            if [ $? -ne 0 ]; then
                return 0
            fi
        fi
    fi

    # Second confirmation with database name verification
    local verification
    verification=$(dialog --colors --title "Verification Required" --inputbox "\Z1DANGER: To confirm deletion, please type the database name '$selected_db' exactly:\Z0" 8 70 3>&1 1>&2 2>&3)

    if [ "$verification" != "$selected_db" ]; then
        dialog --colors --title "Deletion Cancelled" --msgbox "\Z6Database name verification failed. Deletion cancelled." 8 60
        return 0
    fi

    # Perform the deletion
    dialog --infobox "Deleting database '$selected_db'..." 5 60

    if mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "DROP DATABASE \`$selected_db\`;" 2>/dev/null; then
        dialog --colors --title "Deletion Complete" --msgbox "\Z6Database '$selected_db' has been permanently deleted." 8 60
        return 0
    else
        dialog --colors --title "Deletion Failed" --msgbox "\Z1Failed to delete database '$selected_db'.\n\nCheck MySQL permissions and try again." 8 70
        return 1
    fi
}

# Rename database with safety checks
rename_database() {
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

    # Select source database
    local source_db
    source_db=$(dialog --colors --title "Select Database" --menu "Select database to rename:" 15 60 10 "${db_options[@]}" 3>&1 1>&2 2>&3)

    if [ -z "$source_db" ]; then
        return 0
    fi

    # Ask for new name
    local target_db
    target_db=$(dialog --colors --title "New Database Name" --inputbox "Enter new name for database '$source_db':" 8 60 3>&1 1>&2 2>&3)

    if [ -z "$target_db" ]; then
        return 0
    fi

    # Check if target name already exists
    if verify_database_exists "$target_db"; then
        dialog --colors --title "Error" --msgbox "\Z1A database with the name '$target_db' already exists.\n\nPlease choose a different name." 8 70
        return 1
    fi

    # Confirm operation
    dialog --colors --title "Confirm Rename" --yesno "\Z3Are you sure you want to rename database '$source_db' to '$target_db'?\Z0" 8 70

    if [ $? -ne 0 ]; then
        return 0
    fi

    # Create a temporary log file for rename progress
    local rename_log="/tmp/sdbtt_rename_$$.log"
    echo "Starting rename of database '$source_db' to '$target_db'" > "$rename_log"

    # Display progress dialog
    dialog --title "Rename Progress" --tailbox "$rename_log" 15 70 &
    local dialog_pid=$!

    # Run the rename process in background
    {
        echo "Beginning rename process..." >> "$rename_log"

        # MySQL doesn't have a direct RENAME DATABASE command, so we need to:
        # 1. Create a new database
        # 2. Copy all tables and objects
        # 3. Drop the old database

        # Create new database
        echo "Creating new database '$target_db'..." >> "$rename_log"
        if ! mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "CREATE DATABASE \`$target_db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>> "$rename_log"; then
            echo "Failed to create target database '$target_db'" >> "$rename_log"
            rename_status="failure"
            kill $dialog_pid 2>/dev/null || true
            dialog --colors --title "Rename Failed" --msgbox "\Z1Failed to create target database '$target_db'.\Z0" 8 70
            return 1
        fi

        # Get list of tables
        local tables
        tables=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "SHOW TABLES FROM \`$source_db\`;" 2>/dev/null)

        local total_tables=$(echo "$tables" | wc -w)
        echo "Total tables to move: $total_tables" >> "$rename_log"

        if [ -z "$tables" ]; then
            echo "No tables found in source database" >> "$rename_log"
        else
            local i=0
            for table in $tables; do
                ((i++))
                local progress=$((i * 100 / total_tables))

                echo "[$i/$total_tables] Moving table: $table ($progress%)" >> "$rename_log"

                # Move each table to the new database
                if ! mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "RENAME TABLE \`$source_db\`.\`$table\` TO \`$target_db\`.\`$table\`;" 2>> "$rename_log"; then
                    echo "Warning: Failed to move table $table. Will try alternative approach." >> "$rename_log"

                    # Alternative approach - create table with same structure and copy data
                    if mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "CREATE TABLE \`$target_db\`.\`$table\` LIKE \`$source_db\`.\`$table\`;" 2>> "$rename_log"; then
                        mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "INSERT INTO \`$target_db\`.\`$table\` SELECT * FROM \`$source_db\`.\`$table\`;" 2>> "$rename_log"
                    else
                        echo "Error: Failed to move table $table using alternative approach" >> "$rename_log"
                    fi
                fi
            done
        fi

        # Copy routines (stored procedures and functions)
        echo "Copying stored procedures and functions..." >> "$rename_log"
        local routines
        routines=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "
            SELECT ROUTINE_NAME, ROUTINE_TYPE
            FROM information_schema.ROUTINES
            WHERE ROUTINE_SCHEMA = '$source_db';" 2>/dev/null)

        if [ -n "$routines" ]; then
            while read -r name type; do
                echo "Copying $type: $name" >> "$rename_log"

                # Get routine definition
                local definition
                definition=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "
                    SHOW CREATE $type \`$source_db\`.\`$name\`;" 2>/dev/null | sed -e '1d')

                # Create in new database
                if [ -n "$definition" ]; then
                    # Replace the database name in the definition
                    definition=$(echo "$definition" | sed "s/\`$source_db\`/\`$target_db\`/g")

                    # Create the routine in the new database
                    mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" "$target_db" -e "
                        DELIMITER //
                        $definition
                        DELIMITER ;" 2>> "$rename_log"
                fi
            done <<< "$routines"
        fi

        # Copy triggers
        echo "Copying triggers..." >> "$rename_log"
        local triggers
        triggers=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "
            SHOW TRIGGERS FROM \`$source_db\`;" 2>/dev/null)

        if [ -n "$triggers" ]; then
            local trigger_names=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "
                SELECT TRIGGER_NAME
                FROM information_schema.TRIGGERS
                WHERE EVENT_OBJECT_SCHEMA = '$source_db';" 2>/dev/null)

            for trigger in $trigger_names; do
                echo "Copying trigger: $trigger" >> "$rename_log"

                # Get trigger definition
                local trigger_def
                trigger_def=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "
                    SHOW CREATE TRIGGER \`$source_db\`.\`$trigger\`;" 2>/dev/null | sed -e '1d')

                # Create in new database
                if [ -n "$trigger_def" ]; then
                    # Replace the database name in the definition
                    trigger_def=$(echo "$trigger_def" | sed "s/\`$source_db\`/\`$target_db\`/g")

                    # Create the trigger in the new database
                    mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" "$target_db" -e "
                        DELIMITER //
                        $trigger_def
                        DELIMITER ;" 2>> "$rename_log"
                fi
            done
        fi

        # Copy views
        echo "Copying views..." >> "$rename_log"
        local views
        views=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "
            SELECT TABLE_NAME
            FROM information_schema.VIEWS
            WHERE TABLE_SCHEMA = '$source_db';" 2>/dev/null)

        if [ -n "$views" ]; then
            for view in $views; do
                echo "Copying view: $view" >> "$rename_log"

                # Get view definition
                local view_def
                view_def=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "
                    SHOW CREATE VIEW \`$source_db\`.\`$view\`;" 2>/dev/null |
                    awk 'NR==1 {for (i=1; i<=NF; i++) if ($i == "View") col=i+2} NR==1 {print $col}')

                # Create in new database
                if [ -n "$view_def" ]; then
                    # Replace the database name in the definition
                    view_def=$(echo "$view_def" | sed "s/\`$source_db\`/\`$target_db\`/g")

                    # Create the view in the new database
                    mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" "$target_db" -e "
                        CREATE VIEW \`$view\` AS $view_def;" 2>> "$rename_log"
                fi
            done
        fi

        # Copy grants from old database to new database
        echo "Copying user permissions..." >> "$rename_log"
        local grants
        grants=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "
            SELECT CONCAT('GRANT ', privilege_type, ' ON ', table_schema, '.', table_name, ' TO ''', grantee, ''';')
            FROM information_schema.table_privileges
            WHERE table_schema = '$source_db';" 2>/dev/null)

        if [ -n "$grants" ]; then
            while read -r grant; do
                # Replace old database name with new database name
                local new_grant=$(echo "$grant" | sed "s/ON $source_db\./ON $target_db\./g")
                echo "Applying grant: $new_grant" >> "$rename_log"

                # Apply the grant
                mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "$new_grant" 2>> "$rename_log"
            done <<< "$grants"
        fi

        # Verify new database has all tables
        local new_tables_count
        new_tables_count=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "
            SELECT COUNT(*) FROM information_schema.tables
            WHERE table_schema = '$target_db';" 2>/dev/null)

        echo "Tables in new database: $new_tables_count" >> "$rename_log"

        # Ask before dropping old database
        kill $dialog_pid 2>/dev/null || true

        dialog --colors --title "Drop Old Database" --yesno "\Z3Rename operation completed.\n\nDo you want to drop the original database '$source_db'?\Z0" 8 70

        if [ $? -eq 0 ]; then
            dialog --colors --title "Confirm Drop" --defaultno --yesno "\Z1WARNING: This will permanently delete the original database '$source_db'.\n\nAre you absolutely sure?\Z0" 10 70

            if [ $? -eq 0 ]; then
                dialog --infobox "Dropping database '$source_db'..." 5 60
                mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "DROP DATABASE \`$source_db\`;" 2>/dev/null
                dialog --colors --title "Rename Complete" --msgbox "\Z6Database renamed from '$source_db' to '$target_db' and original database dropped." 8 70
            else
                dialog --colors --title "Rename Complete" --msgbox "\Z6Database renamed from '$source_db' to '$target_db'.\n\nOriginal database was kept for safety." 8 70
            fi
        else
            dialog --colors --title "Rename Complete" --msgbox "\Z6Database renamed from '$source_db' to '$target_db'.\n\nOriginal database was kept for safety." 8 70
        fi

        # Clean up temporary log
        rm -f "$rename_log"

    } &

    # Wait for the background process to complete
    wait
}

# Import databases menu with enhanced theming
import_databases_menu() {
    if [ -z "$SQL_DIR" ] || [ ! -d "$SQL_DIR" ]; then
        dialog --colors --title "No Directory Selected" \
            --menu "No valid directory selected. Choose an option:" 10 60 3 \
            "1" "\Z6Browse for Directory\Z0" \
            "2" "\Z6Select from Recent Directories\Z0" \
            "3" "\Z1Back to Main Menu\Z0" \
            2>/tmp/menu_choice

        local choice
        choice=$(<"/tmp/menu_choice")

        case $choice in
            1) browse_directories ;;
            2) select_from_recent_dirs ;;
            *) return ;;
        esac

        # If still no directory, return to main menu
        if [ -z "$SQL_DIR" ] || [ ! -d "$SQL_DIR" ]; then
            return
        fi
    fi

    # Check for missing required settings
    local missing=()
    [ -z "$MYSQL_USER" ] && missing+=("MySQL Username")
    [ -z "$DB_OWNER" ] && missing+=("Database Owner")
    [ -z "$DB_PREFIX" ] && missing+=("Database Prefix")

    # Retrieve password if we have a username but no password
    if [ -n "$MYSQL_USER" ] && [ -z "$MYSQL_PASS" ]; then
        MYSQL_PASS=$(get_password "$MYSQL_USER")

        # If still no password, add to missing list
        [ -z "$MYSQL_PASS" ] && missing+=("MySQL Password")
    fi

    if [ ${#missing[@]} -ne 0 ]; then
        dialog --colors --title "Missing Settings" --msgbox "\Z1The following required settings are missing:\n\n${missing[*]}\n\nPlease configure them before proceeding." 12 60
        configure_settings
        return
    fi

    # List SQL files in the directory
    local sql_files=()
    local i=1

    while IFS= read -r file; do
        if [ -f "$file" ]; then
            local filename="${file##*/}"
            local base_filename="${filename%.sql}"

            # Extract existing prefix if any
            # This assumes prefixes are followed by an underscore
            local existing_prefix=""
            if [[ "$base_filename" == *"_"* ]]; then
                existing_prefix=$(echo "$base_filename" | sed -E 's/^([^_]+)_.*/\1/')
                base_db_name=$(echo "$base_filename" | sed -E 's/^[^_]+_(.*)$/\1/')
            else
                base_db_name="$base_filename"
            fi

            # Apply the new prefix
            local db_name="${DB_PREFIX}${base_db_name}"

            # Show original name → new name with enhanced colors
            if [ -n "$existing_prefix" ]; then
                sql_files+=("$file" "[$i] \Z6$filename\Z0 → \Z5$db_name\Z0 (replacing prefix '\Z3$existing_prefix\Z0')")
            else
                sql_files+=("$file" "[$i] \Z6$filename\Z0 → \Z5$db_name\Z0")
            fi

            ((i++))
        fi
    done < <(find "$SQL_DIR" -maxdepth 1 -type f -name "$SQL_PATTERN" | sort)

    if [ ${#sql_files[@]} -eq 0 ]; then
        dialog --colors --title "No SQL Files Found" --msgbox "\Z1No SQL files matching pattern '$SQL_PATTERN' found in $SQL_DIR." 8 60
        return
    fi

    # Options for how to process the files
    local process_choice
    process_choice=$(dialog --colors --clear --backtitle "\Z6SDBTT - Import\Z0" \
        --title "Process SQL Files" \
        --menu "Found \Z5${#sql_files[@]}\Z0 SQL files. Choose an option:" 15 76 4 \
        "1" "\Z6List and select individual files to import\Z0" \
        "2" "\Z6Import all files\Z0" \
        "3" "\Z6Verify settings and show import plan\Z0" \
        "4" "\Z1Back to Main Menu\Z0" \
        3>&1 1>&2 2>&3)

    case $process_choice in
        1)
            # Multi-select dialog for individual files
            local selected_files
            selected_files=$(dialog --colors --clear --backtitle "\Z6SDBTT - Import\Z0" \
                --title "Select SQL Files to Import" \
                --checklist "Select files to import:" 20 76 12 \
                "${sql_files[@]}" 3>&1 1>&2 2>&3)

            if [ -n "$selected_files" ]; then
                # Remove quotes from the output
                selected_files=$(echo "$selected_files" | tr -d '"')
                start_import_process "$selected_files"
            fi
            ;;
        2)
            # Extract just the filenames from sql_files array
            local all_files=""
            for ((i=0; i<${#sql_files[@]}; i+=2)); do
                all_files="$all_files ${sql_files[i]}"
            done
            start_import_process "$all_files"
            ;;
        3)
            show_import_plan
            ;;
        4|"")
            return
            ;;
    esac
}

# Transfer and replace a single database
transfer_replace_database() {
    if [ -z "$MYSQL_USER" ] || [ -z "$MYSQL_PASS" ]; then
        dialog --colors --title "Missing Credentials" --msgbox "\Z1MySQL credentials not configured.\n\nPlease set your MySQL username and password first." 8 60
        configure_settings
        return
    fi

    # Step 1: Select the source SQL file
    if [ -z "$SQL_DIR" ] || [ ! -d "$SQL_DIR" ]; then
        dialog --colors --title "No Directory Selected" --msgbox "\Z1No SQL directory selected. Please select a directory first." 8 60
        browse_directories

        if [ -z "$SQL_DIR" ] || [ ! -d "$SQL_DIR" ]; then
            return
        fi
    fi

    # Get list of SQL files in the directory
    local sql_files=()
    local i=1

    while IFS= read -r file; do
        if [ -f "$file" ]; then
            local filename="${file##*/}"
            sql_files+=("$file" "[$i] \Z6$filename\Z0")
            ((i++))
        fi
    done < <(find "$SQL_DIR" -maxdepth 1 -type f -name "$SQL_PATTERN" | sort)

    if [ ${#sql_files[@]} -eq 0 ]; then
        dialog --colors --title "No SQL Files Found" --msgbox "\Z1No SQL files matching pattern '$SQL_PATTERN' found in $SQL_DIR." 8 60
        return
    fi

    # Select a single SQL file
    local selected_file
    selected_file=$(dialog --colors --clear --backtitle "\Z6SDBTT - Transfer Database\Z0" \
        --title "Select Source SQL File" \
        --menu "Select the SQL file to import:" 20 76 12 \
        "${sql_files[@]}" 3>&1 1>&2 2>&3)

    if [ -z "$selected_file" ]; then
        return
    fi

    # Extract original database name from filename
    local filename=$(basename "$selected_file")
    local base_filename="${filename%.sql}"

    # Step 2: Select MySQL user to own the database
    # Get list of MySQL users
    local users
    users=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SELECT User FROM mysql.user WHERE User NOT IN ('root', 'debian-sys-maint', 'mysql.sys', 'mysql.session', 'mysql.infoschema');" 2>/dev/null | grep -v "User")

    if [ -z "$users" ]; then
        dialog --colors --title "No MySQL Users" --msgbox "\Z1No MySQL users found. Would you like to create a MySQL user first?" 8 60
        local create_user_choice
        create_user_choice=$(dialog --colors --title "Create MySQL User" --yesno "Would you like to create a new MySQL user first?" 8 60)

        if [ $? -eq 0 ]; then
            create_mysql_user
            # Try again to get users
            users=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SELECT User FROM mysql.user WHERE User NOT IN ('root', 'debian-sys-maint', 'mysql.sys', 'mysql.session', 'mysql.infoschema');" 2>/dev/null | grep -v "User")

            if [ -z "$users" ]; then
                dialog --colors --title "Error" --msgbox "\Z1Still no MySQL users found. Using root as owner." 8 60
                DB_OWNER="root"
            fi
        else
            dialog --colors --title "Using Root" --msgbox "\Z1Using root as the database owner." 8 60
            DB_OWNER="root"
        fi
    fi

    if [ -n "$users" ]; then
        # Create options for user selection
        local user_options=()
        for user in $users; do
            user_options+=("$user" "MySQL user: $user")
        done

        # Add root as an option
        user_options+=("root" "MySQL user: root (system administrator)")

        # Select user
        local selected_user
        selected_user=$(dialog --colors --title "Select MySQL User" --menu "Select MySQL user to own the database:" 15 60 8 "${user_options[@]}" 3>&1 1>&2 2>&3)

        if [ -z "$selected_user" ]; then
            return
        fi

        DB_OWNER="$selected_user"
    fi

    # Step 3: Choose whether to create a new database or replace existing one
    local db_options=()

    # Add option for new database with generated name
    local suggested_name="${DB_PREFIX}${base_filename}"
    db_options+=("new" "Create new database: \Z5$suggested_name\Z0")

    # Get list of existing databases
    local databases
    databases=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "SHOW DATABASES;" 2>/dev/null | grep -v -E "^(Database|information_schema|performance_schema|mysql|sys)$")

    if [ -n "$databases" ]; then
        # Add option to select existing database to replace
        db_options+=("replace" "Replace an existing database")
    fi

    # Add option for custom name
    db_options+=("custom" "Use a custom database name")

    # Select database option
    local db_option
    db_option=$(dialog --colors --title "Database Operation" --menu "Choose database operation:" 15 60 8 "${db_options[@]}" 3>&1 1>&2 2>&3)

    if [ -z "$db_option" ]; then
        return
    fi

    local target_db_name=""

    case $db_option in
        "new")
            target_db_name="$suggested_name"
            ;;
        "replace")
            # Create options for database selection
            local existing_db_options=()
            for db in $databases; do
                existing_db_options+=("$db" "Database: $db")
            done

            # Select database
            local selected_db
            selected_db=$(dialog --colors --title "Select Database to Replace" --menu "Select database to replace:" 15 60 8 "${existing_db_options[@]}" 3>&1 1>&2 2>&3)

            if [ -z "$selected_db" ]; then
                return
            fi

            # Confirm replacement
            dialog --colors --title "Confirm Database Replacement" --yesno "\Z1Are you sure you want to replace the database '$selected_db'?\n\nThis will DELETE all data in this database and replace it with the content from $filename.\n\nThis action cannot be undone!" 12 70

            if [ $? -ne 0 ]; then
                return
            fi

            target_db_name="$selected_db"
            ;;
        "custom")
            # Get custom database name
            target_db_name=$(dialog --colors --title "Custom Database Name" --inputbox "Enter custom database name:" 8 60 "$suggested_name" 3>&1 1>&2 2>&3)

            if [ -z "$target_db_name" ]; then
                return
            fi
            ;;
    esac

    # Show transfer plan
    local plan="\Z5Transfer Plan Summary:\Z0\n\n"
    plan+="Source SQL file: \Z6$filename\Z0\n"
    plan+="Target database: \Z6$target_db_name\Z0\n"
    plan+="Database owner: \Z6$DB_OWNER\Z0\n\n"

    if [ "$db_option" = "replace" ]; then
        plan+="\Z1WARNING: The existing database '$target_db_name' will be dropped and replaced!\Z0\n\n"
    fi

    plan+="\Z6The transfer process will:\Z0\n"
    plan+="1. Drop the target database if it exists\n"
    plan+="2. Create a new database with utf8mb4 charset\n"
    plan+="3. Import data from the SQL file\n"
    plan+="4. Fix character encoding issues\n"
    plan+="5. Grant privileges to \Z5$DB_OWNER\Z0 user\n\n"
    plan+="Logs will be saved to \Z6$LOG_FILE\Z0"

    dialog --colors --title "Transfer Plan" --yesno "$plan\n\nProceed with transfer?" 20 76

    if [ $? -ne 0 ]; then
        return
    fi

    # Initialize log files
    echo "Starting database transfer process at $(date)" > "$LOG_FILE"
    echo "MySQL user: $MYSQL_USER" >> "$LOG_FILE"
    echo "Database owner: $DB_OWNER" >> "$LOG_FILE"
    echo "Source SQL file: $filename" >> "$LOG_FILE"
    echo "Target database: $target_db_name" >> "$LOG_FILE"
    echo "----------------------------------------" >> "$LOG_FILE"

    # Create a display log file for the UI
    echo "Starting database transfer process at $(date)" > "$DISPLAY_LOG_FILE"
    echo "----------------------------------------" >> "$DISPLAY_LOG_FILE"

    # Create temp directory if it doesn't exist
    mkdir -p "$TEMP_DIR"

    # Show progress
    dialog --title "Transfer Progress" --gauge "Preparing to transfer database..." 10 70 0 &
    local gauge_pid=$!

    # Background process for the actual transfer
    {
        # Update progress - 10%
        echo 10 | dialog --title "Transfer Progress" \
               --gauge "Creating target database..." 10 70 10 \
               2>/dev/null

        # Create the database
        log_message "Creating target database: $target_db_name with utf8mb4 charset"
        create_database "$target_db_name"

        # Update progress - 30%
        echo 30 | dialog --title "Transfer Progress" \
               --gauge "Importing database content..." 10 70 30 \
               2>/dev/null

        # Create a processed version with standardized charset
        local processed_file="$TEMP_DIR/processed_$filename"

        # Import the SQL file using improved version
        if improved_import_sql_file "$target_db_name" "$selected_file" "$processed_file"; then
            # Update progress - 70%
            echo 70 | dialog --title "Transfer Progress" \
                   --gauge "Granting privileges to $DB_OWNER..." 10 70 70 \
                   2>/dev/null

            # Grant privileges
            improved_grant_privileges "$target_db_name" "$DB_OWNER"

            # Update progress - 90%
            echo 90 | dialog --title "Transfer Progress" \
                   --gauge "Finalizing transfer..." 10 70 90 \
                   2>/dev/null

            # Flush privileges
            log_message "Flushing privileges..."
            mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "FLUSH PRIVILEGES;" 2>> "$LOG_FILE"

            # Clean up temporary files
            log_message "Cleaning up temporary files..."
            rm -rf "$TEMP_DIR"

            log_message "Database transfer completed successfully"
            log_message "------------------------"

            # Final progress update - 100%
            echo 100 | dialog --title "Transfer Progress" \
                   --gauge "Transfer completed!" 10 70 100 \
                   2>/dev/null

            # Give time to see the final state
            sleep 2

            # Kill the dialog process
            kill $gauge_pid 2>/dev/null || true

            # Show the result summary
            dialog --colors --title "Transfer Complete" --msgbox "\Z6Database transfer completed successfully.\n\nSource SQL file: \Z5$filename\Z0\nTarget database: \Z5$target_db_name\Z0\nDatabase owner: \Z5$DB_OWNER\Z0\n\nLog file saved to: \Z5$LOG_FILE\Z0" 12 70
        else
            # Update progress - error state
            echo 100 | dialog --title "Transfer Progress" \
                   --gauge "Transfer failed!" 10 70 100 \
                   2>/dev/null

            # Clean up temporary files
            log_message "Cleaning up temporary files..."
            rm -rf "$TEMP_DIR"

            log_message "Database transfer failed"
            log_message "------------------------"

            # Give time to see the final state
            sleep 2

            # Kill the dialog process
            kill $gauge_pid 2>/dev/null || true

            # Show error message
            dialog --colors --title "Transfer Failed" --msgbox "\Z1Database transfer failed.\n\nPlease check the log file for more details: \Z5$LOG_FILE\Z0" 8 70

            # Show the log
            dialog --colors --title "Transfer Log" --textbox "$LOG_FILE" 20 76
        fi

        # Clean up
        rm -f "$DISPLAY_LOG_FILE"

    } &

    # Wait for the background process to complete
    wait
}

# Show import plan with enhanced formatting
show_import_plan() {
    local plan="\Z5Import Plan Summary:\Z0\n\n"
    plan+="MySQL User: \Z6$MYSQL_USER\Z0\n"
    plan+="Database Owner: \Z6$DB_OWNER\Z0\n"
    plan+="Source Directory: \Z6$SQL_DIR\Z0\n"
    plan+="SQL Pattern: \Z6$SQL_PATTERN\Z0\n"
    plan+="Database Prefix: \Z6$DB_PREFIX\Z0\n\n"
    plan+="\Z5Files to be imported:\Z0\n"

    local count=0
    local file_list=""

    while IFS= read -r file; do
        if [ -f "$file" ]; then
            local filename="${file##*/}"
            local base_filename="${filename%.sql}"

            # Extract existing prefix if any
            local existing_prefix=""
            if [[ "$base_filename" == *"_"* ]]; then
                existing_prefix=$(echo "$base_filename" | sed -E 's/^([^_]+)_.*/\1/')
                base_db_name=$(echo "$base_filename" | sed -E 's/^[^_]+_(.*)$/\1/')
            else
                base_db_name="$base_filename"
            fi

            # Apply the new prefix
            local db_name="${DB_PREFIX}${base_db_name}"

            # Show original name → new name with enhanced colors
            if [ -n "$existing_prefix" ]; then
                file_list+="\Z6$filename\Z0 → \Z5$db_name\Z0 (replacing prefix '\Z3$existing_prefix\Z0')\n"
            else
                file_list+="\Z6$filename\Z0 → \Z5$db_name\Z0\n"
            fi

            ((count++))
        fi
    done < <(find "$SQL_DIR" -maxdepth 1 -type f -name "$SQL_PATTERN" | sort)

    plan+="$file_list\n"
    plan+="Total: \Z5$count files\Z0\n\n"
    plan+="\Z6The import process will:\Z0\n"
    plan+="1. Drop existing databases with the same name\n"
    plan+="2. Create new databases with utf8mb4 charset\n"
    plan+="3. Import data from SQL files\n"
    plan+="4. Grant privileges to \Z5$DB_OWNER\Z0 user\n\n"
    plan+="Logs will be saved to \Z6$LOG_FILE\Z0"

    dialog --colors --title "Import Plan" --yesno "$plan\n\nProceed with import?" 25 76

    if [ $? -eq 0 ]; then
        # Get all files
        local all_files=""
        while IFS= read -r file; do
            if [ -f "$file" ]; then
                all_files="$all_files $file"
            fi
        done < <(find "$SQL_DIR" -maxdepth 1 -type f -name "$SQL_PATTERN" | sort)

        start_import_process "$all_files"
    fi
}

# Enhanced import process with better progress display and log viewing
start_import_process() {
    local file_list="$1"
    local db_count=0
    local success_count=0
    local failure_count=0

    # Create temp directory if it doesn't exist
    mkdir -p "$TEMP_DIR"

    # Initialize log files
    echo "Starting database import process at $(date)" > "$LOG_FILE"
    echo "MySQL user: $MYSQL_USER" >> "$LOG_FILE"
    echo "Database owner: $DB_OWNER" >> "$LOG_FILE"
    echo "Database prefix: $DB_PREFIX" >> "$LOG_FILE"
    echo "SQL file pattern: $SQL_PATTERN" >> "$LOG_FILE"
    echo "----------------------------------------" >> "$LOG_FILE"

    # Create a display log file for the UI
    echo "Starting database import process at $(date)" > "$DISPLAY_LOG_FILE"
    echo "----------------------------------------" >> "$DISPLAY_LOG_FILE"

    # Check MySQL server's default charset
    local default_charset=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "SHOW VARIABLES LIKE 'character_set_server';" | awk '{print $2}')
    local default_collation=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "SHOW VARIABLES LIKE 'collation_server';" | awk '{print $2}')
    log_message "MySQL server default charset: $default_charset, collation: $default_collation"

    # Calculate total files
    local total_files=$(echo "$file_list" | wc -w)

    # Create a temporary file for progress calculation
    local progress_file=$(mktemp)
    echo "0" > "$progress_file"

    # Create initial log display and progress display - simpler setup
    touch "$DISPLAY_LOG_FILE" # Ensure the file exists
    log_message "Starting import process..."
    log_message "Found $total_files files to import"

    # Use a simpler progress display to avoid dialog issues
    dialog --title "Import Progress" --gauge "Preparing to import databases..." 10 70 0 &
    local gauge_pid=$!

    # Wait briefly to ensure dialog is running
    sleep 1

    # Background process for the actual import
    {
        # Process each file
        for sql_file in $file_list; do
            # Extract database name from filename
            local filename=$(basename "$sql_file")
            local base_filename="${filename%.sql}"

            # Extract existing prefix if any
            if [[ "$base_filename" == *"_"* ]]; then
                local existing_prefix=$(echo "$base_filename" | sed -E 's/^([^_]+)_.*/\1/')
                local base_db_name=$(echo "$base_filename" | sed -E 's/^[^_]+_(.*)$/\1/')
            else
                local base_db_name="$base_filename"
            fi

            # Apply the new prefix
            local db_name="${DB_PREFIX}${base_db_name}"

            ((db_count++))
            log_message "Processing database: $db_name from file $filename"

            # Update progress display
            local progress=$((db_count * 100 / total_files))

            # Update the progress gauge - simpler version without colors
            echo $progress | dialog --title "Import Progress" \
                   --gauge "Importing database $db_count of $total_files: $db_name" 10 70 $progress \
                   2>/dev/null

            # Create a processed version with standardized charset
            local processed_file="$TEMP_DIR/processed_$filename"

            # Create the database
            create_database "$db_name"

            # Import the SQL file using improved version
            if improved_import_sql_file "$db_name" "$sql_file" "$processed_file"; then
                # Grant privileges if import was successful
                improved_grant_privileges "$db_name" "$DB_OWNER"
                ((success_count++))
            else
                ((failure_count++))
            fi

            log_message "Done with $db_name"
            log_message "------------------------"

            # Small delay for readability
            sleep 0.2
        done

        # Apply privileges
        log_message "Flushing privileges..."
        mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "FLUSH PRIVILEGES;" 2>> "$LOG_FILE"

        # Clean up temporary files
        log_message "Cleaning up temporary files..."
        rm -rf "$TEMP_DIR"

        log_message "All databases have been processed"
        log_message "------------------------"
        log_message "Summary:"
        log_message "Total databases processed: $db_count"
        log_message "Successful imports: $success_count"
        log_message "Failed imports: $failure_count"

        # Final progress update - 100%
        echo 100 | dialog --title "Import Progress" \
               --gauge "Import completed!" 10 70 100 \
               2>/dev/null

        # Give time to see the final state
        sleep 2

        # Kill the dialog process
        kill $gauge_pid 2>/dev/null || true

        # Show the result summary
        dialog --colors --title "Import Complete" --msgbox "\Z6Import process complete.\n\nTotal databases processed: \Z5$db_count\Z0\nSuccessful imports: \Z5$success_count\Z0\nFailed imports: \Z1$failure_count\Z0\n\nLog file saved to: \Z5$LOG_FILE\Z0" 12 70

        # Show the complete log if there were failures
        if [ $failure_count -gt 0 ]; then
            dialog --colors --title "Import Log" --yesno "\Z1Some imports failed. Would you like to view the complete log?\Z0" 8 60
            if [ $? -eq 0 ]; then
                dialog --colors --title "Complete Import Log" --textbox "$LOG_FILE" 25 78
            fi
        fi

        # Clean up
        rm -f "$progress_file"
        rm -f "$DISPLAY_LOG_FILE"

    } &

    # Wait for the background process to complete
    wait
}