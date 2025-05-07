#!/bin/bash
# echoDB Charset Module
# Handles character set conversion and fixes

# Improved charset handling function with safety checks
# This fixes the issue with duplicate replacements like utf8mb4mb4
improved_charset_handling() {
    local input_file="$1"
    local output_file="$2"
    local log_file="$3"

    log_message "Applying charset fixes with improved pattern matching..."

    # Create a temporary file for incremental processing
    local temp_file="${output_file}.tmp"

    # First, copy the input file to temporary file
    cp "$input_file" "$temp_file"

    # Apply each replacement carefully to avoid duplication
    # Check if pattern already exists before replacing

    # Process for utf8mb3 first (special case)
    sed -i 's/utf8mb3/utf8mb4/g' "$temp_file"

    # Process main charset replacements with safeguards against duplications
    # The key improvement is using word boundaries and more specific matches
    sed -i \
        -e 's/\bSET NAMES utf8;\b/SET NAMES utf8mb4;/g' \
        -e 's/\bSET character_set_client = utf8;\b/SET character_set_client = utf8mb4;/g' \
        -e 's/\bDEFAULT CHARSET=utf8\b/DEFAULT CHARSET=utf8mb4/g' \
        -e 's/\bCHARSET=utf8\b/CHARSET=utf8mb4/g' \
        -e 's/\bCHARACTER SET utf8\b/CHARACTER SET utf8mb4/g' \
        -e 's/\bCOLLATE=utf8_general_ci\b/COLLATE=utf8mb4_unicode_ci/g' \
        -e 's/\bCOLLATE utf8_general_ci\b/COLLATE utf8mb4_unicode_ci/g' \
        "$temp_file"

    # Safer replacement for utf8 -> utf8mb4 (only where it's still just utf8)
    # This is the most risky replacement and caused the utf8mb4mb4 issues
    # So we'll use a more careful approach
    sed -i \
        -e 's/\butf8\b/utf8mb4/g' \
        -e 's/\bCOLLATE=utf8_/COLLATE=utf8mb4_/g' \
        "$temp_file"

    # Fix other syntax issues unrelated to charset
    sed -i \
        -e 's/^\s*\\-/-- -/g' \
        -e 's/SET @saved_cs_client     = @@character_set_client/SET @saved_cs_client = @@character_set_client/g' \
        "$temp_file"

    # Verify there are no invalid charset specifications
    if grep -q 'utf8mb4mb4\|utf8mb4mb4mb4\|utf8mb4mb4mb4mb4' "$temp_file"; then
        log_message "ERROR: Invalid charset detected after processing. Attempting to fix..."

        # Fix the double/triple/quad replacement errors
        sed -i \
            -e 's/utf8mb4mb4mb4mb4/utf8mb4/g' \
            -e 's/utf8mb4mb4mb4/utf8mb4/g' \
            -e 's/utf8mb4mb4/utf8mb4/g' \
            "$temp_file"

        # Verify again
        if grep -q 'utf8mb4mb4\|utf8mb4mb4mb4\|utf8mb4mb4mb4mb4' "$temp_file"; then
            log_message "ERROR: Critical charset error persists. The SQL file may be corrupted."
            log_message "Rolling back to original file."
            cp "$input_file" "$output_file"
            return 1
        fi
    fi

    # Move temporary file to output if all is well
    mv "$temp_file" "$output_file"

    log_message "Charset conversion completed successfully."
    return 0
}

# Improved function to fix database charset with better error handling
fix_database_charset() {
    local db_name="$1"
    log_message "Fixing character sets and collations for tables and columns in $db_name"

    # Get list of all tables
    local tables
    tables=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "SHOW TABLES FROM \`$db_name\`;" 2>/dev/null)

    if [ -z "$tables" ]; then
        log_message "No tables found in database $db_name"
        return 1
    fi

    # Fix database charset first
    mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "ALTER DATABASE \`$db_name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>> "$LOG_FILE"

    local table_count=$(echo "$tables" | wc -w)
    local i=0

    for table in $tables; do
        ((i++))
        local progress=$((i * 100 / table_count))
        log_message "Fixing charset for table $i of $table_count: $table ($progress%)"

        # Convert table to utf8mb4
        if ! mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "ALTER TABLE \`$db_name\`.\`$table\` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>> "$LOG_FILE"; then
            log_message "Warning: Failed to convert table $table to utf8mb4. Trying individual columns."

            # Get columns for this table
            local columns
            columns=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "SHOW COLUMNS FROM \`$db_name\`.\`$table\`;" 2>/dev/null | awk '{print $1}')

            # For each column of type CHAR, VARCHAR, TEXT, etc., convert to utf8mb4
            for column in $columns; do
                # Check if column is of string type
                local column_type
                column_type=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "SELECT DATA_TYPE FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='$db_name' AND TABLE_NAME='$table' AND COLUMN_NAME='$column';" 2>/dev/null)

                # If column is a string type, modify it to utf8mb4
                if [[ "$column_type" == "char" || "$column_type" == "varchar" || "$column_type" == "text" ||
                      "$column_type" == "tinytext" || "$column_type" == "mediumtext" || "$column_type" == "longtext" ||
                      "$column_type" == "enum" || "$column_type" == "set" ]]; then
                    # Get the column definition
                    local column_def
                    column_def=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "SHOW FULL COLUMNS FROM \`$db_name\`.\`$table\` WHERE Field='$column';" 2>/dev/null | awk '{print $2}')

                    # Modify column to use utf8mb4
                    mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "ALTER TABLE \`$db_name\`.\`$table\` MODIFY COLUMN \`$column\` $column_def CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>> "$LOG_FILE"
                fi
            done
        fi
    done

    log_message "Character set and collation fixes completed for all tables in $db_name"
    return 0
}

# New function to attempt split import for complex SQL files
attempt_split_import() {
    local db_name="$1"
    local sql_file="$2"
    local split_dir="$TEMP_DIR/split_${db_name}"

    mkdir -p "$split_dir"
    log_message "Splitting SQL file for incremental import..."

    # Split file by SQL statements
    awk 'BEGIN{RS=";\n"; i=0} {i++; if(NF>0) print $0 ";" > "'$split_dir'/chunk_" sprintf("%05d", i) ".sql"}' "$sql_file"

    # Count chunks
    local chunk_count=$(ls -1 "$split_dir"/chunk_*.sql 2>/dev/null | wc -l)
    log_message "Split SQL file into $chunk_count chunks"

    if [ "$chunk_count" -eq 0 ]; then
        log_message "ERROR: Failed to split SQL file"
        return 1
    fi

    # Import chunks in order
    local success_count=0
    local error_count=0

    # Initialize database again
    create_database "$db_name"

    # Process chunks with progress updates
    local i=0
    for chunk in $(ls -1 "$split_dir"/chunk_*.sql | sort); do
        ((i++))
        local progress=$((i * 100 / chunk_count))

        log_message "Importing chunk $i of $chunk_count ($progress%)"

        # Try to import the chunk
        if ! mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" --default-character-set=utf8mb4 "$db_name" < "$chunk" 2>> "$LOG_FILE"; then
            log_message "Warning: Chunk $i failed to import. Continuing with next chunk."
            ((error_count++))
        else
            ((success_count++))
        fi
    done

    log_message "Chunk import completed: $success_count succeeded, $error_count failed"

    # Check if we have tables
    local table_count
    table_count=$(mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -N -e "SELECT COUNT(TABLE_NAME) FROM information_schema.tables WHERE table_schema = '$db_name';" 2>/dev/null)

    if [ -n "$table_count" ] && [ "$table_count" -gt 0 ]; then
        log_message "Split import created $table_count tables in $db_name"
        return 0
    else
        log_message "Split import failed to create any tables in $db_name"
        return 1
    fi
}

# Improved import_sql_file function with better error handling and backup/restore
# Import the SQL file using improved version with Gum
improved_import_sql_file() {
    local db_name="$1"
    local sql_file="$2"
    local processed_file="$3"

    log_message "Preparing to import $sql_file into database $db_name"

    # Use Gum spinner for file encoding analysis
    gum_spin "Analyzing file encoding..." "file -bi \"$sql_file\" > /tmp/file_encoding"
    local file_encoding=$(cat /tmp/file_encoding | sed -e 's/.*charset=//')
    log_message "Detected file encoding: $file_encoding"

    # Create a backup of the database if it exists
    local backup_file=""
    if mysql -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "USE \`$db_name\`" 2>/dev/null; then
        log_message "Database $db_name already exists. Creating backup before import."
        backup_file=$(gum_spin "Creating backup..." "backup_database \"$db_name\"")
        if [ $? -ne 0 ]; then
            log_message "WARNING: Failed to create backup of existing database $db_name. Proceeding with caution."
        else
            log_message "Backup created at: $backup_file"
        fi
    fi

    # Process the SQL file with charset handling
    log_message "Converting file to UTF-8 with encoding fixes..."
    gum_spin "Converting file to UTF-8..." "
        # Create a temporary directory for intermediary processed files
        local tmp_process_dir=\"$TEMP_DIR/process_$db_name\"
        mkdir -p \"$tmp_process_dir\"

        # First step: Convert encoding to UTF-8 if needed
        local utf8_file=\"$tmp_process_dir/utf8_converted.sql\"

        if [ \"$file_encoding\" = \"unknown\" ] || [ \"$file_encoding\" = \"utf-8\" ] || [ \"$file_encoding\" = \"us-ascii\" ]; then
            # File is already UTF-8 or ASCII (subset of UTF-8), just copy
            cp \"$sql_file\" \"$utf8_file\"
        else
            # Try to convert to UTF-8
            if command -v iconv >/dev/null 2>&1; then
                iconv -f \"$file_encoding\" -t UTF-8//TRANSLIT \"$sql_file\" > \"$utf8_file\" 2>> \"$LOG_FILE\" || cp \"$sql_file\" \"$utf8_file\"
            else
                # No iconv available, just copy and hope for the best
                cp \"$sql_file\" \"$utf8_file\"
            fi
        fi
    "

    # Apply charset fixes
    if ! gum_spin "Applying charset fixes..." "improved_charset_handling \"$utf8_file\" \"$processed_file\" \"$LOG_FILE\""; then
        log_message "ERROR: Failed to process charset in SQL file."
        if [ -n "$backup_file" ]; then
            gum_spin "Restoring from backup..." "restore_database \"$db_name\" \"$backup_file\""
        fi
        return 1
    fi

    # Create or reset the database
    create_database "$db_name"

    # Try direct import with charset parameters
    log_message "Attempting direct import with charset parameters for $db_name..."
    if ! gum_spin "Importing database..." "mysql --default-character-set=utf8mb4 -u \"$MYSQL_USER\" -p\"$MYSQL_PASS\" \"$db_name\" < \"$processed_file\" 2> \"$TEMP_DIR/${db_name}_import_errors.log\""; then
        # Check the error log
        log_message "Direct import encountered issues. Analyzing errors..."
        cat "$TEMP_DIR/${db_name}_import_errors.log" >> "$LOG_FILE"

        # Try alternative methods...
        log_message "Attempting import with SOURCE command..."
        if ! gum_spin "Trying SOURCE import..." "mysql -u \"$MYSQL_USER\" -p\"$MYSQL_PASS\" --default-character-set=utf8mb4 \"$db_name\" -e \"SOURCE $processed_file;\" 2> \"$TEMP_DIR/${db_name}_source_errors.log\""; then
            # Try split import as last resort
            log_message "Both import methods failed. Trying split SQL import..."
            if ! gum_spin "Attempting split import..." "attempt_split_import \"$db_name\" \"$processed_file\""; then
                # All methods failed, restore from backup
                if [ -n "$backup_file" ]; then
                    gum_spin "Restoring database..." "restore_database \"$db_name\" \"$backup_file\""
                fi
                return 1
            fi
        fi
    fi

    # Fix charset if import succeeded
    gum_spin "Fixing database charset..." "fix_database_charset \"$db_name\""
    return 0
}