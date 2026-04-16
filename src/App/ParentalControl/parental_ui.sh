#!/bin/sh
# ============================================================
# GuardianPlay v1.0 — Main UI
# Parental Control Add-on for Onion OS (Miyoo Mini / Mini+)
# ============================================================
# Usage: ./parental_ui.sh
# Requires: Onion OS 4.3+ | prompt | infoPanel binaries
# ============================================================

APPDIR="$(cd "$(dirname "$0")" && pwd)"
SYSDIR="/mnt/SDCARD/.tmp_update"
DATADIR="$APPDIR/data"
LANGDIR="$APPDIR/lang"
CONFIG="$DATADIR/config.cfg"
STATS_FILE="$DATADIR/stats.csv"
HISTORY_FILE="$DATADIR/history.log"

PROMPT="$SYSDIR/bin/prompt"
INFOPANEL="$SYSDIR/bin/infoPanel"

# Maximum history file size (500 MB = 524288000 bytes)
MAX_HISTORY_BYTES=524288000
# Show at most 50 entries in history view
HISTORY_DISPLAY_MAX=50
# Items per page in history/stats view
PAGE_SIZE=10

# ============================================================
# HELPERS
# ============================================================

log() { echo "[GuardianPlay] $1"; }

# Load language strings based on Onion OS system.json language setting
load_language() {
    local sys_lang="en"
    if [ -f "/mnt/SDCARD/system.json" ]; then
        sys_lang=$(grep -o '"language"[[:space:]]*:[[:space:]]*"[^"]*"' /mnt/SDCARD/system.json \
                   | sed 's/.*"\([^"]*\)"/\1/' | head -1)
    fi
    case "$sys_lang" in
        fr|french|FR) . "$LANGDIR/fr.sh" ;;
        es|spanish|ES) . "$LANGDIR/es.sh" ;;
        *) . "$LANGDIR/en.sh" ;;
    esac
    log "Language loaded: $GP_LANG"
}

# Load config file into variables
load_config() {
    if [ -f "$CONFIG" ]; then
        # shellcheck disable=SC1090
        . "$CONFIG"
    else
        # Defaults
        GP_ENABLED_STATE=0
        GP_PIN="0000"
        GP_TIME_REMAINING=3600
    fi
    # Ensure numeric
    GP_TIME_REMAINING=$(( ${GP_TIME_REMAINING:-3600} + 0 ))
    GP_ENABLED_STATE=$(( ${GP_ENABLED_STATE:-0} + 0 ))
}

# Save config to file
save_config() {
    mkdir -p "$DATADIR"
    cat > "$CONFIG" << EOF
# GuardianPlay Configuration — do not edit while app is running
GP_ENABLED_STATE=${GP_ENABLED_STATE}
GP_PIN=${GP_PIN}
GP_TIME_REMAINING=${GP_TIME_REMAINING}
EOF
    log "Config saved. Enabled=$GP_ENABLED_STATE Time=${GP_TIME_REMAINING}s"
}

# Format seconds as "Xh YYmin" or "YYmin" or "< 1 min"
format_time() {
    local total_secs="$1"
    local h=$(( total_secs / 3600 ))
    local m=$(( (total_secs % 3600) / 60 ))
    local s=$(( total_secs % 60 ))
    if [ "$h" -gt 0 ]; then
        printf "%d%s %02d%s" "$h" "$GP_HOURS" "$m" "$GP_MINUTES"
    elif [ "$m" -gt 0 ]; then
        printf "%d%s" "$m" "$GP_MINUTES"
    elif [ "$total_secs" -gt 0 ]; then
        printf "%d%s" "$s" "$GP_SECONDS"
    else
        printf "0 %s" "$GP_MINUTES"
    fi
}

# Rotate history file if it exceeds 500 MB
rotate_history() {
    if [ -f "$HISTORY_FILE" ]; then
        local size
        size=$(wc -c < "$HISTORY_FILE" 2>/dev/null || echo 0)
        if [ "$size" -gt "$MAX_HISTORY_BYTES" ]; then
            log "History file too large ($size bytes), rotating..."
            # Keep only the last 500 lines
            local tmp="/tmp/gp_history_tmp"
            tail -500 "$HISTORY_FILE" > "$tmp" && mv "$tmp" "$HISTORY_FILE"
        fi
    fi
}

# Add entry to history log: "YYYY-MM-DD HH:MM:SS|game_name"
add_history_entry() {
    local game="$1"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    mkdir -p "$DATADIR"
    echo "${ts}|${game}" >> "$HISTORY_FILE"
    rotate_history
}

# Update stats for a game (increments session seconds)
update_stats() {
    local game="$1"
    local seconds="$2"
    mkdir -p "$DATADIR"
    touch "$STATS_FILE"
    # Check if game already exists in stats
    if grep -q "^${game}," "$STATS_FILE" 2>/dev/null; then
        local current
        current=$(grep "^${game}," "$STATS_FILE" | cut -d',' -f2)
        local new_total=$(( current + seconds ))
        # Replace the line
        local tmpfile="/tmp/gp_stats_tmp"
        grep -v "^${game}," "$STATS_FILE" > "$tmpfile"
        echo "${game},${new_total}" >> "$tmpfile"
        mv "$tmpfile" "$STATS_FILE"
    else
        echo "${game},${seconds}" >> "$STATS_FILE"
    fi
}

# ============================================================
# PIN MANAGEMENT
# ============================================================

# Ask user to enter a single digit (0–9)
# Returns: exit code = the digit entered (0–9), 255 = cancelled
ask_digit() {
    local title="$1"
    local msg="$2"
    "$PROMPT" -t "$title" -m "$msg" \
        "0" "1" "2" "3" "4" "5" "6" "7" "8" "9"
    return $?
}

# Enter a 4-digit PIN interactively
# Sets GP_ENTERED_PIN (as 4-digit string) on success
# Returns 0 on success, 1 if cancelled
enter_pin_interactive() {
    local title="$1"
    local d1 d2 d3 d4

    ask_digit "$title" "$(printf "$GP_PIN_DIGIT" 1)"
    d1=$?
    [ "$d1" -eq 255 ] && return 1

    ask_digit "$title" "$(printf "$GP_PIN_DIGIT" 2)"
    d2=$?
    [ "$d2" -eq 255 ] && return 1

    ask_digit "$title" "$(printf "$GP_PIN_DIGIT" 3)"
    d3=$?
    [ "$d3" -eq 255 ] && return 1

    ask_digit "$title" "$(printf "$GP_PIN_DIGIT" 4)"
    d4=$?
    [ "$d4" -eq 255 ] && return 1

    GP_ENTERED_PIN="${d1}${d2}${d3}${d4}"
    return 0
}

# Verify PIN: returns 0 if correct, 1 if wrong
verify_pin() {
    enter_pin_interactive "$GP_PIN_TITLE" || return 1
    if [ "$GP_ENTERED_PIN" = "$GP_PIN" ]; then
        return 0
    else
        "$INFOPANEL" --title "$GP_ERROR" --message "$GP_PIN_WRONG" --auto
        return 1
    fi
}

# ============================================================
# FIRST-TIME SETUP (PIN initialisation)
# ============================================================

first_time_setup() {
    "$INFOPANEL" --title "$GP_PIN_INIT_TITLE" --message "$GP_PIN_INIT_MSG" --auto

    while true; do
        # New PIN
        enter_pin_interactive "$GP_PIN_TITLE" || return 1
        local new_pin="$GP_ENTERED_PIN"

        # Confirm PIN
        enter_pin_interactive "$GP_PIN_TITLE" || return 1
        local confirm_pin="$GP_ENTERED_PIN"

        if [ "$new_pin" = "$confirm_pin" ]; then
            GP_PIN="$new_pin"
            GP_ENABLED_STATE=1
            save_config
            "$INFOPANEL" --title "$GP_SUCCESS" --message "$GP_ENABLED_MSG" --auto
            return 0
        else
            "$INFOPANEL" --title "$GP_ERROR" --message "$GP_PIN_MISMATCH" --auto
        fi
    done
}

# ============================================================
# CHANGE PIN
# ============================================================

ui_change_pin() {
    # First verify current PIN
    verify_pin || return

    while true; do
        enter_pin_interactive "$GP_PIN_TITLE" || return
        local new_pin="$GP_ENTERED_PIN"

        enter_pin_interactive "$GP_PIN_TITLE" || return
        local confirm_pin="$GP_ENTERED_PIN"

        if [ "$new_pin" = "$confirm_pin" ]; then
            GP_PIN="$new_pin"
            save_config
            "$INFOPANEL" --title "$GP_SUCCESS" --message "$GP_PIN_CHANGED" --auto
            return
        else
            "$INFOPANEL" --title "$GP_ERROR" --message "$GP_PIN_MISMATCH" --auto
        fi
    done
}

# ============================================================
# ENABLE / DISABLE
# ============================================================

ui_toggle_parental() {
    if [ "$GP_ENABLED_STATE" -eq 0 ]; then
        # Enable: needs PIN
        enter_pin_interactive "$GP_ENABLE_TITLE" || return
        if [ "$GP_ENTERED_PIN" = "$GP_PIN" ]; then
            GP_ENABLED_STATE=1
            save_config
            # Notify daemon to reload config
            touch /tmp/gp_config_changed
            "$INFOPANEL" --title "$GP_APP_NAME" --message "$GP_ENABLED_MSG" --auto
        else
            "$INFOPANEL" --title "$GP_ERROR" --message "$GP_PIN_WRONG" --auto
        fi
    else
        # Disable: needs PIN
        enter_pin_interactive "$GP_DISABLE_TITLE" || return
        if [ "$GP_ENTERED_PIN" = "$GP_PIN" ]; then
            GP_ENABLED_STATE=0
            save_config
            touch /tmp/gp_config_changed
            "$INFOPANEL" --title "$GP_APP_NAME" --message "$GP_DISABLED_MSG" --auto
        else
            "$INFOPANEL" --title "$GP_ERROR" --message "$GP_PIN_WRONG" --auto
        fi
    fi
}

# ============================================================
# TIME MANAGEMENT
# ============================================================

ui_add_time() {
    local choice
    "$PROMPT" -t "$GP_TIME_TITLE" \
        -m "$(format_time "$GP_TIME_REMAINING") $GP_TIME_REMAINING" \
        "$GP_ADD_10" \
        "$GP_ADD_60" \
        "$GP_ADD_2H" \
        "$GP_ADD_3H"
    choice=$?
    case "$choice" in
        0) GP_TIME_REMAINING=$(( GP_TIME_REMAINING + 600 )) ;;
        1) GP_TIME_REMAINING=$(( GP_TIME_REMAINING + 3600 )) ;;
        2) GP_TIME_REMAINING=$(( GP_TIME_REMAINING + 7200 )) ;;
        3) GP_TIME_REMAINING=$(( GP_TIME_REMAINING + 10800 )) ;;
        *) return ;;
    esac
    save_config
    touch /tmp/gp_config_changed
    local msg
    msg=$(printf "$GP_TIME_UPDATED" "$(format_time "$GP_TIME_REMAINING")")
    "$INFOPANEL" --title "$GP_TIME_TITLE" --message "$msg" --auto
}

ui_remove_time() {
    local choice
    "$PROMPT" -t "$GP_TIME_TITLE" \
        -m "$(format_time "$GP_TIME_REMAINING")" \
        "$GP_REMOVE_10" \
        "$GP_REMOVE_60" \
        "$GP_REMOVE_2H" \
        "$GP_TIME_SET_TO_ZERO"
    choice=$?
    case "$choice" in
        0) GP_TIME_REMAINING=$(( GP_TIME_REMAINING - 600 )) ;;
        1) GP_TIME_REMAINING=$(( GP_TIME_REMAINING - 3600 )) ;;
        2) GP_TIME_REMAINING=$(( GP_TIME_REMAINING - 7200 )) ;;
        3) GP_TIME_REMAINING=0 ;;
        *) return ;;
    esac
    # Clamp to zero
    [ "$GP_TIME_REMAINING" -lt 0 ] && GP_TIME_REMAINING=0
    save_config
    touch /tmp/gp_config_changed
    local msg
    msg=$(printf "$GP_TIME_UPDATED" "$(format_time "$GP_TIME_REMAINING")")
    "$INFOPANEL" --title "$GP_TIME_TITLE" --message "$msg" --auto
}

# ============================================================
# TAB 1 — SETTINGS
# ============================================================

ui_settings() {
    while true; do
        load_config

        local status_str
        if [ "$GP_ENABLED_STATE" -eq 1 ]; then
            status_str="$GP_STATUS_ON"
        else
            status_str="$GP_STATUS_OFF"
        fi

        local time_str
        time_str=$(format_time "$GP_TIME_REMAINING")

        local toggle_label
        if [ "$GP_ENABLED_STATE" -eq 0 ]; then
            toggle_label="$GP_TOGGLE_ENABLE"
        else
            toggle_label="$GP_TOGGLE_DISABLE"
        fi

        "$PROMPT" -t "$GP_SETTINGS_TITLE" \
            -m "$GP_STATUS: $status_str  |  $GP_TIME_REMAINING: $time_str" \
            "$toggle_label" \
            "$GP_CHANGE_PIN" \
            "$GP_ADD_TIME" \
            "$GP_REMOVE_TIME" \
            "$GP_BACK"
        local choice=$?
        case "$choice" in
            0) ui_toggle_parental ;;
            1) ui_change_pin ;;
            2) ui_add_time ;;
            3) ui_remove_time ;;
            4|255) return ;;
        esac
    done
}

# ============================================================
# TAB 2 — STATISTICS
# ============================================================

ui_stats() {
    if [ ! -f "$STATS_FILE" ] || [ ! -s "$STATS_FILE" ]; then
        "$INFOPANEL" --title "$GP_STATS_TITLE" --message "$GP_STATS_EMPTY" --auto
        return
    fi

    # Sort by total seconds descending, get top 20
    local stats_lines
    stats_lines=$(sort -t',' -k2 -rn "$STATS_FILE" | head -20)

    # Build message string (max ~800 chars for infoPanel)
    local msg=""
    local total_all=0
    local count=0

    while IFS=',' read -r game secs; do
        [ -z "$game" ] && continue
        total_all=$(( total_all + secs ))
        count=$(( count + 1 ))
        if [ "$count" -le 10 ]; then
            # Truncate game name to 22 chars
            local short_name
            short_name=$(echo "$game" | cut -c1-22)
            local t
            t=$(format_time "$secs")
            msg="${msg}\n${count}. ${short_name} — ${t}"
        fi
    done << EOF
$stats_lines
EOF

    local total_str
    total_str=$(format_time "$total_all")
    local full_msg
    full_msg="$GP_STATS_TOTAL $total_str\n\n$GP_STATS_TOP$msg"

    "$PROMPT" -t "$GP_STATS_TITLE" \
        -m "$full_msg" \
        "$GP_STATS_RESET" \
        "$GP_BACK"
    local choice=$?
    if [ "$choice" -eq 0 ]; then
        "$PROMPT" -t "$GP_STATS_TITLE" -m "$GP_STATS_RESET_CONFIRM" \
            "$GP_YES" "$GP_NO"
        local confirm=$?
        if [ "$confirm" -eq 0 ]; then
            rm -f "$STATS_FILE"
            "$INFOPANEL" --title "$GP_STATS_TITLE" --message "$GP_STATS_RESET_DONE" --auto
        fi
    fi
}

# ============================================================
# TAB 3 — HISTORY
# ============================================================

ui_history() {
    if [ ! -f "$HISTORY_FILE" ] || [ ! -s "$HISTORY_FILE" ]; then
        "$INFOPANEL" --title "$GP_HISTORY_TITLE" --message "$GP_HISTORY_EMPTY" --auto
        return
    fi

    # Get last 50 entries in reverse order (newest first)
    local lines
    lines=$(tail -"$HISTORY_DISPLAY_MAX" "$HISTORY_FILE" | sort -r)
    local total
    total=$(echo "$lines" | wc -l)

    local page=1
    local total_pages=$(( (total + PAGE_SIZE - 1) / PAGE_SIZE ))
    [ "$total_pages" -eq 0 ] && total_pages=1

    while true; do
        local start=$(( (page - 1) * PAGE_SIZE + 1 ))
        local end=$(( page * PAGE_SIZE ))
        [ "$end" -gt "$total" ] && end="$total"

        local msg=""
        local n="$start"
        local page_lines
        page_lines=$(echo "$lines" | sed -n "${start},${end}p")

        while IFS='|' read -r ts game; do
            [ -z "$ts" ] && continue
            local short_game
            short_game=$(echo "$game" | cut -c1-20)
            local short_ts
            short_ts=$(echo "$ts" | cut -c1-16)
            msg="${msg}\n${n}. [${short_ts}] ${short_game}"
            n=$(( n + 1 ))
        done << EOF
$page_lines
EOF

        local page_info
        page_info=$(printf "$GP_HISTORY_PAGE" "$page" "$total_pages")

        local nav_prev="< Prev"
        local nav_next="Next >"

        if [ "$total_pages" -gt 1 ]; then
            "$PROMPT" -t "$GP_HISTORY_TITLE" \
                -m "$page_info\n$msg" \
                "$nav_prev" "$nav_next" \
                "$GP_HISTORY_CLEAR" "$GP_BACK"
        else
            "$PROMPT" -t "$GP_HISTORY_TITLE" \
                -m "$msg" \
                "$GP_HISTORY_CLEAR" "$GP_BACK"
        fi
        local choice=$?

        if [ "$total_pages" -gt 1 ]; then
            case "$choice" in
                0)  # Prev
                    page=$(( page - 1 ))
                    [ "$page" -lt 1 ] && page="$total_pages"
                    ;;
                1)  # Next
                    page=$(( page + 1 ))
                    [ "$page" -gt "$total_pages" ] && page=1
                    ;;
                2)  # Clear
                    "$PROMPT" -t "$GP_HISTORY_TITLE" \
                        -m "$GP_HISTORY_CLEAR_CONFIRM" \
                        "$GP_YES" "$GP_NO"
                    local confirm=$?
                    if [ "$confirm" -eq 0 ]; then
                        rm -f "$HISTORY_FILE"
                        "$INFOPANEL" --title "$GP_HISTORY_TITLE" \
                            --message "$GP_HISTORY_CLEAR_DONE" --auto
                        return
                    fi
                    ;;
                3|255) return ;;
            esac
        else
            case "$choice" in
                0)  # Clear
                    "$PROMPT" -t "$GP_HISTORY_TITLE" \
                        -m "$GP_HISTORY_CLEAR_CONFIRM" \
                        "$GP_YES" "$GP_NO"
                    local confirm=$?
                    if [ "$confirm" -eq 0 ]; then
                        rm -f "$HISTORY_FILE"
                        "$INFOPANEL" --title "$GP_HISTORY_TITLE" \
                            --message "$GP_HISTORY_CLEAR_DONE" --auto
                        return
                    fi
                    ;;
                1|255) return ;;
            esac
        fi
    done
}

# ============================================================
# ABOUT
# ============================================================

ui_about() {
    "$INFOPANEL" --title "$GP_ABOUT_TITLE" --message "$GP_ABOUT_MSG" --auto
}

# ============================================================
# MAIN MENU
# ============================================================

ui_main_menu() {
    while true; do
        load_config

        local status_str
        if [ "$GP_ENABLED_STATE" -eq 1 ]; then
            status_str="$GP_STATUS_ON"
        else
            status_str="$GP_STATUS_OFF"
        fi
        local time_str
        time_str=$(format_time "$GP_TIME_REMAINING")

        "$PROMPT" -t "$GP_APP_NAME" \
            -m "$GP_STATUS: $status_str  |  $GP_TIME_REMAINING: $time_str" \
            "$GP_MENU_SETTINGS" \
            "$GP_MENU_STATS" \
            "$GP_MENU_HISTORY" \
            "$GP_MENU_ABOUT"
        local choice=$?
        case "$choice" in
            0) ui_settings ;;
            1) ui_stats ;;
            2) ui_history ;;
            3) ui_about ;;
            255) return ;;
        esac
    done
}

# ============================================================
# ENTRY POINT
# ============================================================

main() {
    mkdir -p "$DATADIR"

    # Check prompt and infoPanel are available
    if [ ! -x "$PROMPT" ]; then
        echo "[GuardianPlay] ERROR: prompt binary not found at $PROMPT"
        exit 1
    fi
    if [ ! -x "$INFOPANEL" ]; then
        echo "[GuardianPlay] ERROR: infoPanel binary not found at $INFOPANEL"
        exit 1
    fi

    load_language
    load_config

    # First-time setup: no PIN configured yet (default 0000 means uninitialized)
    if [ ! -f "$CONFIG" ]; then
        log "First time setup..."
        first_time_setup || exit 0
        load_config
    fi

    ui_main_menu
    exit 0
}

main "$@"
