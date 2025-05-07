#!/bin/bash
# echoDB Gum UI Module
# Provides wrappers around Gum for consistent UI experience

# Retrowave theme settings for Gum
GUM_THEME_PRIMARY="#ff00ff"   # Magenta
GUM_THEME_SECONDARY="#00ffff" # Cyan
GUM_THEME_ACCENT="#ffff00"    # Yellow
GUM_THEME_ERROR="#ff0000"     # Red
GUM_THEME_BG="#000000"        # Black
GUM_THEME_SUCCESS="#00ff00"   # Green

# Initialize Gum with retrowave theme
gum_init() {
    # Check if Gum is installed
    if ! command -v gum &> /dev/null; then
        echo "Error: Gum not found. Please install Gum first." >&2
        echo "Visit: https://github.com/charmbracelet/gum" >&2
        return 1
    }

    # Export theme settings for Gum
    export GUM_INPUT_CURSOR_FOREGROUND=$GUM_THEME_PRIMARY
    export GUM_INPUT_PROMPT_FOREGROUND=$GUM_THEME_SECONDARY
    export GUM_CONFIRM_PROMPT_FOREGROUND=$GUM_THEME_PRIMARY
    export GUM_CONFIRM_SELECTED_FOREGROUND=$GUM_THEME_SECONDARY
    export GUM_CONFIRM_UNSELECTED_FOREGROUND=$GUM_THEME_SECONDARY
    export GUM_CHOOSE_CURSOR_FOREGROUND=$GUM_THEME_PRIMARY
    export GUM_CHOOSE_SELECTED_FOREGROUND=$GUM_THEME_SECONDARY
    export GUM_CHOOSE_UNSELECTED_FOREGROUND=$GUM_THEME_SECONDARY
    export GUM_FILTER_INDICATOR_FOREGROUND=$GUM_THEME_PRIMARY
    export GUM_FILTER_SELECTED_PREFIX_FOREGROUND=$GUM_THEME_SECONDARY
    export GUM_FILTER_UNSELECTED_PREFIX_FOREGROUND=$GUM_THEME_SECONDARY
    export GUM_SPIN_SPINNER="dot"
    export GUM_SPIN_FOREGROUND=$GUM_THEME_PRIMARY
}

# Display styled header
gum_header() {
    gum style \
        --foreground $GUM_THEME_PRIMARY \
        --border double \
        --border-foreground $GUM_THEME_SECONDARY \
        --align center \
        --width 50 \
        "echoDB: Simple Database Transfer Tool v$VERSION"

    # Display the ASCII art for retrowave effect
    gum style --foreground $GUM_THEME_PRIMARY --align center '
 ██████╗██████╗ ██████╗ ████████╗████████╗
██╔════╝██╔══██╗██╔══██╗╚══██╔══╝╚══██╔══╝
╚█████╗ ██║  ██║██████╔╝   ██║      ██║
 ╚═══██╗██║  ██║██╔══██╗   ██║      ██║
██████╔╝██████╔╝██████╔╝   ██║      ██║
╚═════╝ ╚═════╝ ╚═════╝    ╚═╝      ╚═╝
'
    gum style --foreground $GUM_THEME_SECONDARY --align center "░▒▓█▓▒░░▒▓█▓▒░░▒▓█▓▒░░▒▓█▓▒░"
}

# Show a menu and return selection
gum_menu() {
    local title="$1"
    shift

    # Display title
    gum style --foreground $GUM_THEME_PRIMARY --bold "$title"

    # Display menu options
    gum choose "$@"
}

# Prompt for text input
gum_input() {
    local prompt="$1"
    local default="${2:-}"

    gum input --prompt "$prompt: " --value "$default"
}

# Prompt for password
gum_password() {
    local prompt="$1"

    gum input --password --prompt "$prompt: "
}

# Confirm dialog (yes/no)
gum_confirm() {
    local prompt="$1"

    gum confirm "$prompt"
    return $?
}

# Show a spinning indicator for long operations
gum_spin() {
    local message="$1"
    local command="$2"

    gum spin --title "$message" -- bash -c "$command"
    return $?
}

# Display formatted message
gum_message() {
    local type="$1"
    local message="$2"

    case "$type" in
        "error")
            gum style --foreground $GUM_THEME_ERROR --bold --border normal --border-foreground $GUM_THEME_ERROR "$message"
            ;;
        "success")
            gum style --foreground $GUM_THEME_SUCCESS --bold --border normal --border-foreground $GUM_THEME_SUCCESS "$message"
            ;;
        "warning")
            gum style --foreground $GUM_THEME_ACCENT --bold --border normal --border-foreground $GUM_THEME_ACCENT "$message"
            ;;
        *)
            gum style --foreground $GUM_THEME_SECONDARY "$message"
            ;;
    esac
}

# Display a formatted list of key-value pairs
gum_info() {
    local title="$1"
    shift

    gum style --foreground $GUM_THEME_PRIMARY --bold --border rounded --border-foreground $GUM_THEME_SECONDARY "$title"

    while [ "$#" -ge 2 ]; do
        echo "$(gum style --foreground $GUM_THEME_SECONDARY "$1"): $(gum style --foreground $GUM_THEME_PRIMARY "$2")"
        shift 2
    done
}

# Multi-select from a list of options
gum_multiselect() {
    local title="$1"
    shift

    gum style --foreground $GUM_THEME_PRIMARY --bold "$title"
    gum choose --multiple "$@"
}

# Display progress for operations
gum_progress() {
    local title="$1"
    local current="$2"
    local total="$3"

    echo "$title ($current/$total)"
    gum style --foreground $GUM_THEME_PRIMARY "[$(for i in $(seq 1 $current); do echo -n "█"; done)$(for i in $(seq $current $((total-1))); do echo -n "░"; done)]"
}

# Show formatted text content (replaces dialog --textbox)
gum_text() {
    local title="$1"
    local content="$2"

    gum style --foreground $GUM_THEME_PRIMARY --bold --border rounded --border-foreground $GUM_THEME_SECONDARY "$title"
    echo "$content" | gum pager
}

# Long-form text editing
gum_edit() {
    local title="$1"
    local initial_content="${2:-}"

    gum style --foreground $GUM_THEME_PRIMARY --bold "$title"
    gum write --value "$initial_content"
}

# File selection (with filtering)
gum_file_select() {
    local title="$1"
    local directory="$2"
    local pattern="${3:-*}"

    gum style --foreground $GUM_THEME_PRIMARY --bold "$title"
    find "$directory" -maxdepth 1 -type f -name "$pattern" | sort | gum filter
}

# Join items with a delimiter for display
gum_join() {
    local delimiter="$1"
    shift

    local result=""
    local first=true

    for item in "$@"; do
        if $first; then
            result="$item"
            first=false
        else
            result="$result$delimiter$item"
        fi
    done

    echo "$result"
}

# Format file listing for display
gum_format_files() {
    local dir="$1"
    local pattern="$2"

    find "$dir" -maxdepth 1 -type f -name "$pattern" | sort | while read -r file; do
        local filename="${file##*/}"
        local size=$(du -h "$file" | cut -f1)
        echo "$(gum style --foreground $GUM_THEME_SECONDARY "📄 $filename") ($(gum style --foreground $GUM_THEME_PRIMARY "$size"))"
    done
}