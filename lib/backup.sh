#!/bin/bash
# SDBTT Backup Module
# Handles database backup and restore operations

# Securely store database backup and restore function
backup_database() {
    local db_name="$1"
    local backup_dir="$CONFIG_DIR/backups"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$backup_dir/${db_name}_backup_${timestamp}.sql.gz"

    # Ensure backup directory exists
    mkdir -p "$backup_dir"

    # Check if database exists
    if ! mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "USE \`$db_name\`" 2>/dev/null; then
        log_message "Database $db_name does not exist. No backup needed."
        return 0
    fi

    log_message "Creating backup of database $db_name to $backup_file"

    # Perform the backup with compression to save space
    if mysqldump -u "$MYSQL_USER" -p"$MYSQL_PASS" --skip-extended-insert \
       --default-character-set=utf8mb4 \
       --add-drop-table --add-drop-database --routines --triggers \
       "$db_name" | gzip > "$backup_file"; then

        log_message "Backup of $db_name completed successfully."
        echo "$backup_file"
        return 0
    else
        log_message "ERROR: Backup of $db_name failed."
        return 1
    fi
}

# Restore database from backup
restore_database() {
    local db_name="$1"
    local backup_file="$2"

    if [ ! -f "$backup_file" ]; then
        log_message "ERROR: Backup file $backup_file does not exist."
        return 1
    fi

    log_message "Restoring database $db_name from backup $backup_file"

    # Drop existing database if it exists
    mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "DROP DATABASE IF EXISTS \`$db_name\`;" 2>> "$LOG_FILE"

    # Create fresh database
    mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "CREATE DATABASE \`$db_name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>> "$LOG_FILE"

    # Restore from backup
    if [ "${backup_file##*.}" = "gz" ]; then
        # For gzipped backup
        zcat "$backup_file" | mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" "$db_name" 2>> "$LOG_FILE"
    else
        # For uncompressed backup
        mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" "$db_name" < "$backup_file" 2>> "$LOG_FILE"
    fi

    if [ $? -eq 0 ]; then
        log_message "Database $db_name restored successfully from backup."
        return 0
    else
        log_message "ERROR: Failed to restore database $db_name from backup."
        return 1
    fi
}

# Backup database with progress indicator
backup_database_with_progress() {
    local db_name="$1"

    # Verify database exists
    if ! verify_database_exists "$db_name"; then
        dialog --colors --title "Error" --msgbox "\Z1Database '$db_name' does not exist." 8 60
        return 1
    fi

    # Ask for backup options
    local choice
    choice=$(dialog --colors --clear --backtitle "\Z6SDBTT MySQL Backup\Z0" \
        --title "Backup Options" --menu "Choose backup format:" 15 60 4 \
        "1" "\Z6Compressed SQL backup (gzip)\Z0" \
        "2" "\Z6Plain SQL backup\Z0" \
        "3" "\Z6Custom backup with selected tables\Z0" \
        "4" "\Z1Cancel\Z0" \
        3>&1 1>&2 2>&3)

    case $choice in
        1)
            backup_type="compressed"
            backup_ext=".sql.gz"
            ;;
        2)
            backup_type="plain"
            backup_ext=".sql"
            ;;
        3)
            backup_type="custom"
            backup_ext=".sql.gz"
            select_tables_for_backup "$db_name"
            return $?
            ;;
        4|"")
            return 0
            ;;
    esac

    # Set backup directory and filename
    local backup_dir="$CONFIG_DIR/backups"
    mkdir -p "$backup_dir"

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$backup_dir/${db_name}_backup_${timestamp}${backup_ext}"

    # Create a temporary log file for backup progress
    local backup_log="/tmp/sdbtt_backup_$$.log"
    echo "Starting backup of database '$db_name'" > "$backup_log"

    # Calculate an estimate of the database size for progress
    local db_size=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "
        SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2)
        FROM information_schema.tables
        WHERE table_schema = '$db_name';" 2>/dev/null)

    echo "Estimated database size: ${db_size} MB" >> "$backup_log"

    # Display progress dialog
    dialog --title "Backup Progress" --tailbox "$backup_log" 15 70 &
    local dialog_pid=$!

    # Run the backup process in background
    {
        echo "Beginning backup process... this may take a while" >> "$backup_log"

        # Get the table count for better progress reporting
        local table_count=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "
            SELECT COUNT(*)
            FROM information_schema.tables
            WHERE table_schema = '$db_name';" 2>/dev/null)

        echo "Total tables to backup: $table_count" >> "$backup_log"

        # Create a temporary status file that mysqldump will update
        local status_file="/tmp/sdbtt_dump_status_$$.txt"

        if [ "$backup_type" = "compressed" ]; then
            echo "Creating compressed backup..." >> "$backup_log"

            # Use mysqldump with progress reporting
            if mysqldump -u "$MYSQL_USER" -p"$MYSQL_PASS" \
               --verbose --debug-info \
               --default-character-set=utf8mb4 \
               --add-drop-database --add-drop-table \
               --routines --triggers --events \
               --single-transaction \
               "$db_name" 2> "$status_file" | gzip > "$backup_file"; then
                echo "Backup completed successfully" >> "$backup_log"
                backup_status="success"
            else
                echo "Backup failed" >> "$backup_log"
                cat "$status_file" >> "$backup_log"
                backup_status="failure"
            fi
        else
            echo "Creating plain SQL backup..." >> "$backup_log"

            # Use mysqldump with progress reporting
            if mysqldump -u "$MYSQL_USER" -p"$MYSQL_PASS" \
               --verbose --debug-info \
               --default-character-set=utf8mb4 \
               --add-drop-database --add-drop-table \
               --routines --triggers --events \
               --single-transaction \
               "$db_name" 2> "$status_file" > "$backup_file"; then
                echo "Backup completed successfully" >> "$backup_log"
                backup_status="success"
            else
                echo "Backup failed" >> "$backup_log"
                cat "$status_file" >> "$backup_log"
                backup_status="failure"
            fi
        fi

        # Calculate final backup size
        if [ -f "$backup_file" ]; then
            local final_size=$(du -h "$backup_file" | cut -f1)
            echo "Backup file size: $final_size" >> "$backup_log"
        fi

        # Clean up status file
        rm -f "$status_file"

        # Kill the dialog process
        kill $dialog_pid 2>/dev/null || true

        # Display completion message
        if [ "$backup_status" = "success" ]; then
            dialog --colors --title "Backup Complete" --msgbox "\Z6Backup of database '$db_name' completed successfully.\n\nBackup saved to:\Z0\n$backup_file" 10 70
        else
            dialog --colors --title "Backup Failed" --msgbox "\Z1Backup of database '$db_name' failed.\n\nSee log file for details.\Z0" 8 70

            # Show the backup log
            dialog --colors --title "Backup Log" --textbox "$backup_log" 20 76
        fi

        # Clean up temporary log
        rm -f "$backup_log"

    } &

    # Wait for the background process to complete
    wait
}

# Select tables for custom backup
select_tables_for_backup() {
    local db_name="$1"

    # Get list of tables
    local tables
    tables=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "SHOW TABLES FROM \`$db_name\`;" 2>/dev/null)

    if [ -z "$tables" ]; then
        dialog --colors --title "No Tables" --msgbox "\Z1Database '$db_name' has no tables." 8 60
        return 1
    fi

    # Create options for table selection
    local table_options=()
    for table in $tables; do
        # Get row count and size for each table
        local table_info=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "
        SELECT
            TABLE_ROWS,
            ROUND((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024, 2)
        FROM information_schema.TABLES
        WHERE TABLE_SCHEMA = '$db_name' AND TABLE_NAME = '$table';" 2>/dev/null)

        local rows=$(echo "$table_info" | awk '{print $1}')
        local size=$(echo "$table_info" | awk '{print $2}')

        table_options+=("$table" "Table: $table (Rows: $rows, Size: ${size}MB)" "on")
    done

    # Allow selecting multiple tables
    local selected_tables
    selected_tables=$(dialog --colors --title "Select Tables" --checklist "Select tables to include in backup:" 20 76 15 "${table_options[@]}" 3>&1 1>&2 2>&3)

    if [ -z "$selected_tables" ]; then
        return 1
    fi

    # Remove quotes from the output
    selected_tables=$(echo "$selected_tables" | tr -d '"')

    # Set backup directory and filename
    local backup_dir="$CONFIG_DIR/backups"
    mkdir -p "$backup_dir"

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$backup_dir/${db_name}_custom_backup_${timestamp}.sql.gz"

    # Create a temporary log file for backup progress
    local backup_log="/tmp/sdbtt_backup_$$.log"
    echo "Starting custom backup of selected tables from database '$db_name'" > "$backup_log"
    echo "Selected tables: $selected_tables" >> "$backup_log"

    # Display progress dialog
    dialog --title "Backup Progress" --tailbox "$backup_log" 15 70 &
    local dialog_pid=$!

    # Run the backup process in background
    {
        echo "Beginning backup process..." >> "$backup_log"

        # Create a temporary status file
        local status_file="/tmp/sdbtt_dump_status_$$.txt"

        # Use mysqldump with progress reporting and selected tables
        if mysqldump -u "$MYSQL_USER" -p"$MYSQL_PASS" \
           --verbose --debug-info \
           --default-character-set=utf8mb4 \
           --add-drop-table \
           --routines --triggers \
           --single-transaction \
           "$db_name" $selected_tables 2> "$status_file" | gzip > "$backup_file"; then
            echo "Backup completed successfully" >> "$backup_log"
            backup_status="success"
        else
            echo "Backup failed" >> "$backup_log"
            cat "$status_file" >> "$backup_log"
            backup_status="failure"
        fi

        # Calculate final backup size
        if [ -f "$backup_file" ]; then
            local final_size=$(du -h "$backup_file" | cut -f1)
            echo "Backup file size: $final_size" >> "$backup_log"
        fi

        # Clean up status file
        rm -f "$status_file"

        # Kill the dialog process
        kill $dialog_pid 2>/dev/null || true

        # Display completion message
        if [ "$backup_status" = "success" ]; then
            dialog --colors --title "Backup Complete" --msgbox "\Z6Custom backup of selected tables from database '$db_name' completed successfully.\n\nBackup saved to:\Z0\n$backup_file" 10 70
        else
            dialog --colors --title "Backup Failed" --msgbox "\Z1Custom backup of database '$db_name' failed.\n\nSee log file for details.\Z0" 8 70

            # Show the backup log
            dialog --colors --title "Backup Log" --textbox "$backup_log" 20 76
        fi

        # Clean up temporary log
        rm -f "$backup_log"

    } &

    # Wait for the background process to complete
    wait
}

# Restore database from backup with progress indicator
restore_database_with_progress() {
    # First, check for available backups
    local backup_dir="$CONFIG_DIR/backups"

    if [ ! -d "$backup_dir" ]; then
        dialog --colors --title "No Backups" --msgbox "\Z1No backup directory found at $backup_dir" 8 60
        return 1
    fi

    # Find all SQL and gzipped SQL backups
    local backups=()
    local i=1

    # List backup files
    while IFS= read -r backup; do
        if [ -f "$backup" ]; then
            local backup_date=$(basename "$backup" | grep -oE '[0-9]{8}_[0-9]{6}')
            local formatted_date=$(date -d "${backup_date:0:8} ${backup_date:9:2}:${backup_date:11:2}:${backup_date:13:2}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$backup_date")
            local size=$(du -h "$backup" | cut -f1)
            backups+=("$backup" "[$i] \Z6$(basename "$backup")\Z0 (Date: $formatted_date, Size: $size)")
            ((i++))
        fi
    done < <(find "$backup_dir" -type f \( -name "*.sql" -o -name "*.sql.gz" \) | sort -r)

    if [ ${#backups[@]} -eq 0 ]; then
        dialog --colors --title "No Backups" --msgbox "\Z1No backup files found in $backup_dir" 8 60
        return 1
    fi

    # Add option to cancel
    backups+=("CANCEL" "\Z1Cancel operation\Z0")

    # Select backup file
    local selected_backup
    selected_backup=$(dialog --colors --clear --backtitle "\Z6SDBTT Restore Backup\Z0" \
        --title "Select Backup File" \
        --menu "Choose a backup file to restore:" 20 76 15 \
        "${backups[@]}" 3>&1 1>&2 2>&3)

    if [ "$selected_backup" = "CANCEL" ] || [ -z "$selected_backup" ]; then
        return 0
    fi

    # Determine database name from backup file
    local db_name=$(basename "$selected_backup" | sed -E 's/(.+)_backup_[0-9]{8}_[0-9]{6}(\.sql(\.gz)?)/\1/')

    # Ask for target database name (default to extracted name)
    local target_db
    target_db=$(dialog --colors --title "Target Database" --inputbox "Enter target database name for restore:" 8 60 "$db_name" 3>&1 1>&2 2>&3)

    if [ -z "$target_db" ]; then
        return 0
    fi

    # Check if target database exists
    if verify_database_exists "$target_db"; then
        dialog --colors --title "Warning" --defaultno --yesno "\Z1Database '$target_db' already exists.\n\nThis will DELETE all existing data in this database.\n\nAre you sure you want to continue?\Z0" 10 70

        if [ $? -ne 0 ]; then
            return 0
        fi

        # Create a backup of the existing database before overwriting
        dialog --colors --title "Backup Existing" --yesno "\Z3Would you like to create a backup of the existing database before restoring?\Z0" 8 70

        if [ $? -eq 0 ]; then
            dialog --infobox "Creating backup of existing database '$target_db'..." 5 60
            backup_database "$target_db" > /dev/null
        fi
    fi

    # Create a temporary log file for restore progress
    local restore_log="/tmp/sdbtt_restore_$$.log"
    echo "Starting restoration of database '$target_db' from backup $(basename "$selected_backup")" > "$restore_log"

    # Display progress dialog
    dialog --title "Restore Progress" --tailbox "$restore_log" 15 70 &
    local dialog_pid=$!

    # Run the restore process in background
    {
        echo "Beginning restore process..." >> "$restore_log"

        # Drop existing database if it exists
        echo "Dropping existing database if it exists..." >> "$restore_log"
        mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "DROP DATABASE IF EXISTS \`$target_db\`;" 2>> "$restore_log"

        # Create fresh database
        echo "Creating new database '$target_db'..." >> "$restore_log"
        mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "CREATE DATABASE \`$target_db\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>> "$restore_log"

        # Restore based on file type
        if [[ "$selected_backup" == *.gz ]]; then
            echo "Decompressing and restoring from gzipped backup..." >> "$restore_log"
            if zcat "$selected_backup" | mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" "$target_db" 2>> "$restore_log"; then
                echo "Restoration from gzipped backup completed successfully" >> "$restore_log"
                restore_status="success"
            else
                echo "Restoration from gzipped backup failed" >> "$restore_log"
                restore_status="failure"
            fi
        else
            echo "Restoring from SQL backup..." >> "$restore_log"
            if mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" "$target_db" < "$selected_backup" 2>> "$restore_log"; then
                echo "Restoration from SQL backup completed successfully" >> "$restore_log"
                restore_status="success"
            else
                echo "Restoration from SQL backup failed" >> "$restore_log"
                restore_status="failure"
            fi
        fi

        # Fix character sets
        if [ "$restore_status" = "success" ]; then
            echo "Fixing character sets and collations..." >> "$restore_log"
            fix_database_charset "$target_db" >> "$restore_log" 2>&1
        fi

        # Kill the dialog process
        kill $dialog_pid 2>/dev/null || true

        # Display completion message
        if [ "$restore_status" = "success" ]; then
            dialog --colors --title "Restore Complete" --msgbox "\Z6Restoration of database '$target_db' completed successfully." 8 70
        else
            dialog --colors --title "Restore Failed" --msgbox "\Z1Restoration of database '$target_db' failed.\n\nSee log file for details.\Z0" 8 70

            # Show the restore log
            dialog --colors --title "Restore Log" --textbox "$restore_log" 20 76
        fi

        # Clean up temporary log
        rm -f "$restore_log"

    } &

    # Wait for the background process to complete
    wait
}