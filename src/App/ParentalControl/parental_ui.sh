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
STATS_FILE="$DATADIR/stats.dat"
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

# Detect Onion OS language from system.json
# Handles: "en", "English", "english", "fr", "French", etc.
detect_system_lang() {
    if [ -f "/mnt/SDCARD/system.json" ]; then
        _raw=$(grep -o '"language"[[:space:]]*:[[:space:]]*"[^"]*"' \
               /mnt/SDCARD/system.json | sed 's/.*"\([^"]*\)"/\1/' | head -1)
        # Normalise to lowercase
        echo "$_raw" | tr 'A-Z' 'a-z'
    else
        echo "en"
    fi
}

load_language() {
    _lang=$(detect_system_lang)
    case "$_lang" in
        fr*) . "$LANGDIR/fr.sh" ;;
        es*) . "$LANGDIR/es.sh" ;;
        de*) . "$LANGDIR/de.sh" ;;
        it*) . "$LANGDIR/it.sh" ;;
        pt*) . "$LANGDIR/pt.sh" ;;
        *)   . "$LANGDIR/en.sh" ;;
    esac
    log "Language loaded: $GP_LANG"
}

# Load config — uses GP_TIMER_SECS (not GP_TIME_REMAINING which is a lang label)
load_config() {
    if [ -f "$CONFIG" ]; then
        . "$CONFIG"
    else
        GP_ENABLED_STATE=0
        GP_PIN="0000"
        GP_TIMER_SECS=3600
    fi
    GP_TIMER_SECS=$(( ${GP_TIMER_SECS:-3600} + 0 ))
    GP_ENABLED_STATE=$(( ${GP_ENABLED_STATE:-0} + 0 ))
}

save_config() {
    mkdir -p "$DATADIR"
    cat > "$CONFIG" << CFGEOF
# GuardianPlay Configuration
# PIN is in plaintext so parents can recover it from a PC
GP_ENABLED_STATE=${GP_ENABLED_STATE}
GP_PIN=${GP_PIN}
GP_TIMER_SECS=${GP_TIMER_SECS}
CFGEOF
    sync
    log "Config saved. Enabled=$GP_ENABLED_STATE Time=${GP_TIMER_SECS}s"
}

# Format seconds as "Xh YYmin" or "YYmin" or "< 1 min"
format_time() {
    _ts="$1"
    _h=$(( _ts / 3600 ))
    _m=$(( (_ts % 3600) / 60 ))
    _s=$(( _ts % 60 ))
    if [ "$_h" -gt 0 ]; then
        printf "%d%s %02d%s" "$_h" "$GP_HOURS" "$_m" "$GP_MINUTES"
    elif [ "$_m" -gt 0 ]; then
        printf "%d%s" "$_m" "$GP_MINUTES"
    elif [ "$_ts" -gt 0 ]; then
        printf "%d%s" "$_s" "$GP_SECONDS"
    else
        printf "0 %s" "$GP_MINUTES"
    fi
}

# Rotate history file if it exceeds 500 MB
rotate_history() {
    if [ -f "$HISTORY_FILE" ]; then
        _sz=$(wc -c < "$HISTORY_FILE" 2>/dev/null || echo 0)
        if [ "$_sz" -gt "$MAX_HISTORY_BYTES" ]; then
            log "History file too large ($_sz bytes), rotating..."
            tail -500 "$HISTORY_FILE" > /tmp/gp_history_tmp && mv /tmp/gp_history_tmp "$HISTORY_FILE"
        fi
    fi
}

# ============================================================
# PIN MANAGEMENT
# ============================================================

# Ask user to enter a single digit — phone keypad layout (1-9 then 0)
# Returns 0-9 as the digit typed, or 10+/255 if cancelled.
# Note: prompt returns 0-indexed button position, so we map it back to a digit.
ask_digit() {
    "$PROMPT" -t "$1" -m "$2" \
        "1" "2" "3" \
        "4" "5" "6" \
        "7" "8" "9" \
        "0"
    _rc=$?
    # Cancelled / out of range
    [ "$_rc" -ge 10 ] && return "$_rc"
    # Map button index -> digit (last button = 0, others = index+1)
    if [ "$_rc" -eq 9 ]; then
        return 0
    fi
    return $(( _rc + 1 ))
}

# Build a progress string like "* * _ _" from entered digit count (0-4)
_pin_progress() {
    case "$1" in
        0) echo "_ _ _ _" ;;
        1) echo "* _ _ _" ;;
        2) echo "* * _ _" ;;
        3) echo "* * * _" ;;
        4) echo "* * * *" ;;
    esac
}

# Enter a 4-digit PIN interactively
# Sets GP_ENTERED_PIN on success — returns 0=ok, 1=cancelled
enter_pin_interactive() {
    _pin_title="$1"
    for _slot in 1 2 3 4; do
        _label=$(printf "$GP_PIN_DIGIT" "$_slot")
        _bar=$(_pin_progress $(( _slot - 1 )))
        ask_digit "$_pin_title" "${_label}\n\n${_bar}"
        _rc=$?
        [ "$_rc" -ge 10 ] && return 1
        eval "_d${_slot}=$_rc"
    done

    GP_ENTERED_PIN="${_d1}${_d2}${_d3}${_d4}"
    return 0
}

# Verify PIN: returns 0 if correct, 1 if wrong/cancelled
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
# FIRST-TIME SETUP
# ============================================================

first_time_setup() {
    "$INFOPANEL" --title "$GP_PIN_INIT_TITLE" --message "$GP_PIN_INIT_MSG" --auto

    while true; do
        enter_pin_interactive "$GP_PIN_NEW" || return 1
        _new_pin="$GP_ENTERED_PIN"

        enter_pin_interactive "$GP_PIN_CONFIRM_NEW" || return 1
        _confirm_pin="$GP_ENTERED_PIN"

        if [ "$_new_pin" = "$_confirm_pin" ]; then
            GP_PIN="$_new_pin"
            GP_ENABLED_STATE=1
            GP_TIMER_SECS=3600
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
    verify_pin || return

    while true; do
        enter_pin_interactive "$GP_PIN_NEW" || return
        _new_pin="$GP_ENTERED_PIN"

        enter_pin_interactive "$GP_PIN_CONFIRM_NEW" || return
        _confirm_pin="$GP_ENTERED_PIN"

        if [ "$_new_pin" = "$_confirm_pin" ]; then
            GP_PIN="$_new_pin"
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
        enter_pin_interactive "$GP_ENABLE_TITLE" || return
        if [ "$GP_ENTERED_PIN" = "$GP_PIN" ]; then
            GP_ENABLED_STATE=1
            save_config
            touch /tmp/gp_config_changed
            "$INFOPANEL" --title "$GP_APP_NAME" --message "$GP_ENABLED_MSG" --auto
        else
            "$INFOPANEL" --title "$GP_ERROR" --message "$GP_PIN_WRONG" --auto
        fi
    else
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
    _time_str=$(format_time "$GP_TIMER_SECS")
    "$PROMPT" -t "$GP_TIME_TITLE" \
        -m "$GP_TIME_REMAINING: $_time_str" \
        "$GP_ADD_1" \
        "$GP_ADD_10" \
        "$GP_ADD_60" \
        "$GP_ADD_2H" \
        "$GP_ADD_3H"
    _ch=$?
    case "$_ch" in
        0) GP_TIMER_SECS=$(( GP_TIMER_SECS + 60 )) ;;
        1) GP_TIMER_SECS=$(( GP_TIMER_SECS + 600 )) ;;
        2) GP_TIMER_SECS=$(( GP_TIMER_SECS + 3600 )) ;;
        3) GP_TIMER_SECS=$(( GP_TIMER_SECS + 7200 )) ;;
        4) GP_TIMER_SECS=$(( GP_TIMER_SECS + 10800 )) ;;
        *) return ;;
    esac
    save_config
    touch /tmp/gp_config_changed
    _msg=$(printf "$GP_TIME_UPDATED" "$(format_time "$GP_TIMER_SECS")")
    "$INFOPANEL" --title "$GP_TIME_TITLE" --message "$_msg" --auto
}

ui_remove_time() {
    _time_str=$(format_time "$GP_TIMER_SECS")
    "$PROMPT" -t "$GP_TIME_TITLE" \
        -m "$GP_TIME_REMAINING: $_time_str" \
        "$GP_REMOVE_10" \
        "$GP_REMOVE_60" \
        "$GP_REMOVE_2H" \
        "$GP_TIME_SET_TO_ZERO"
    _ch=$?
    case "$_ch" in
        0) GP_TIMER_SECS=$(( GP_TIMER_SECS - 600 )) ;;
        1) GP_TIMER_SECS=$(( GP_TIMER_SECS - 3600 )) ;;
        2) GP_TIMER_SECS=$(( GP_TIMER_SECS - 7200 )) ;;
        3) GP_TIMER_SECS=0 ;;
        *) return ;;
    esac
    [ "$GP_TIMER_SECS" -lt 0 ] && GP_TIMER_SECS=0
    save_config
    touch /tmp/gp_config_changed
    _msg=$(printf "$GP_TIME_UPDATED" "$(format_time "$GP_TIMER_SECS")")
    "$INFOPANEL" --title "$GP_TIME_TITLE" --message "$_msg" --auto
}

# ============================================================
# TAB 1 — SETTINGS
# ============================================================

ui_settings() {
    while true; do
        load_config

        if [ "$GP_ENABLED_STATE" -eq 1 ]; then
            _status="$GP_STATUS_ON"
            _toggle="$GP_TOGGLE_DISABLE"
        else
            _status="$GP_STATUS_OFF"
            _toggle="$GP_TOGGLE_ENABLE"
        fi
        _time_str=$(format_time "$GP_TIMER_SECS")

        "$PROMPT" -t "$GP_SETTINGS_TITLE" \
            -m "$GP_STATUS: $_status  |  $GP_TIME_REMAINING: $_time_str" \
            "$_toggle" \
            "$GP_CHANGE_PIN" \
            "$GP_ADD_TIME" \
            "$GP_REMOVE_TIME" \
            "$GP_BACK"
        _ch=$?
        case "$_ch" in
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
    # Stats format: game_name|seconds
    _stats=$(sort -t'|' -k2 -rn "$STATS_FILE" | head -20)
    _msg=""
    _total=0
    _count=0

    _oldIFS="$IFS"
    IFS='
'
    for _line in $_stats; do
        _game=$(echo "$_line" | cut -d'|' -f1)
        _secs=$(echo "$_line" | cut -d'|' -f2)
        [ -z "$_game" ] && continue
        _total=$(( _total + _secs ))
        _count=$(( _count + 1 ))
        if [ "$_count" -le 10 ]; then
            _short=$(echo "$_game" | cut -c1-22)
            _t=$(format_time "$_secs")
            _msg="${_msg}\n${_count}. ${_short} - ${_t}"
        fi
    done
    IFS="$_oldIFS"

    _total_str=$(format_time "$_total")
    _full="$GP_STATS_TOTAL $_total_str\n\n$GP_STATS_TOP$_msg"

    "$PROMPT" -t "$GP_STATS_TITLE" \
        -m "$_full" \
        "$GP_STATS_RESET" \
        "$GP_BACK"
    _ch=$?
    if [ "$_ch" -eq 0 ]; then
        "$PROMPT" -t "$GP_STATS_TITLE" -m "$GP_STATS_RESET_CONFIRM" \
            "$GP_YES" "$GP_NO"
        _confirm=$?
        if [ "$_confirm" -eq 0 ]; then
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

    # Get last 50 entries (already chronological — reverse for display)
    _lines=$(tail -"$HISTORY_DISPLAY_MAX" "$HISTORY_FILE" | sort -r)
    _total=$(echo "$_lines" | wc -l)
    _page=1
    _pages=$(( (_total + PAGE_SIZE - 1) / PAGE_SIZE ))
    [ "$_pages" -eq 0 ] && _pages=1

    while true; do
        _start=$(( (_page - 1) * PAGE_SIZE + 1 ))
        _end=$(( _page * PAGE_SIZE ))
        [ "$_end" -gt "$_total" ] && _end="$_total"

        _msg=""
        _n="$_start"
        _plines=$(echo "$_lines" | sed -n "${_start},${_end}p")

        _oldIFS="$IFS"
        IFS='
'
        for _entry in $_plines; do
            _ts=$(echo "$_entry" | cut -d'|' -f1 | cut -c1-16)
            _game=$(echo "$_entry" | cut -d'|' -f2 | cut -c1-20)
            [ -z "$_ts" ] && continue
            _msg="${_msg}\n${_n}. [${_ts}] ${_game}"
            _n=$(( _n + 1 ))
        done
        IFS="$_oldIFS"

        _pinfo=$(printf "$GP_HISTORY_PAGE" "$_page" "$_pages")

        if [ "$_pages" -gt 1 ]; then
            "$PROMPT" -t "$GP_HISTORY_TITLE" \
                -m "${_pinfo}\n${_msg}" \
                "< Prev" "Next >" \
                "$GP_HISTORY_CLEAR" "$GP_BACK"
            _ch=$?
            case "$_ch" in
                0)  _page=$(( _page - 1 )); [ "$_page" -lt 1 ] && _page="$_pages" ;;
                1)  _page=$(( _page + 1 )); [ "$_page" -gt "$_pages" ] && _page=1 ;;
                2)  _confirm_clear_history ;;
                3|255) return ;;
            esac
        else
            "$PROMPT" -t "$GP_HISTORY_TITLE" \
                -m "$_msg" \
                "$GP_HISTORY_CLEAR" "$GP_BACK"
            _ch=$?
            case "$_ch" in
                0) _confirm_clear_history ;;
                1|255) return ;;
            esac
        fi
    done
}

_confirm_clear_history() {
    "$PROMPT" -t "$GP_HISTORY_TITLE" -m "$GP_HISTORY_CLEAR_CONFIRM" \
        "$GP_YES" "$GP_NO"
    if [ $? -eq 0 ]; then
        rm -f "$HISTORY_FILE"
        "$INFOPANEL" --title "$GP_HISTORY_TITLE" --message "$GP_HISTORY_CLEAR_DONE" --auto
        return 1  # signal caller to exit history view
    fi
    return 0
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

        if [ "$GP_ENABLED_STATE" -eq 1 ]; then
            _status="$GP_STATUS_ON"
        else
            _status="$GP_STATUS_OFF"
        fi
        _time_str=$(format_time "$GP_TIMER_SECS")

        "$PROMPT" -t "$GP_APP_NAME" \
            -m "$GP_STATUS: $_status  |  $GP_TIME_REMAINING: $_time_str" \
            "$GP_MENU_SETTINGS" \
            "$GP_MENU_STATS" \
            "$GP_MENU_HISTORY" \
            "$GP_MENU_ABOUT"
        _ch=$?
        case "$_ch" in
            0)  if [ "$GP_ENABLED_STATE" -eq 1 ]; then
                    verify_pin || continue
                fi
                ui_settings ;;
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

    if [ ! -f "$CONFIG" ]; then
        log "First time setup..."
        first_time_setup || exit 0
        load_config
    fi

    ui_main_menu
    exit 0
}

main "$@"
