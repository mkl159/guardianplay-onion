#!/bin/sh
# ============================================================
# GuardianPlay v1.0 — Background Timer Daemon
# ============================================================
# Runs in the background from system startup.
# Tracks play time, shows overlay notifications,
# forces game exit when time runs out.
#
# Started by: /mnt/SDCARD/.tmp_update/startup/guardianplay.sh
# ============================================================

APPDIR="/mnt/SDCARD/App/ParentalControl"
SYSDIR="/mnt/SDCARD/.tmp_update"
DATADIR="$APPDIR/data"
CONFIG="$DATADIR/config.cfg"
STATS_FILE="$DATADIR/stats.dat"
HISTORY_FILE="$DATADIR/history.log"

INFOPANEL="$SYSDIR/bin/infoPanel"
LOGFILE="/tmp/guardianplay_daemon.log"
PIDFILE="/tmp/guardianplay_daemon.pid"

export LD_LIBRARY_PATH="/lib:/config/lib:/mnt/SDCARD/miyoo/lib:$SYSDIR/lib:$SYSDIR/lib/parasyte"
export PATH="$SYSDIR/bin:$PATH"

# ============================================================
# LOGGING
# ============================================================

log() { echo "$(date '+%H:%M:%S') [GP] $1" >> "$LOGFILE"; }

# ============================================================
# CONFIG
# ============================================================

load_config() {
    if [ -f "$CONFIG" ]; then
        . "$CONFIG"
    fi
    GP_ENABLED_STATE=$(( ${GP_ENABLED_STATE:-0} + 0 ))
    GP_TIMER_SECS=$(( ${GP_TIMER_SECS:-0} + 0 ))
}

# Atomic-ish save: write to tmp then mv (safe on FAT32)
save_timer() {
    _tmp="/tmp/gp_cfg_save"
    cat > "$_tmp" << SVEOF
# GuardianPlay Configuration
GP_ENABLED_STATE=${GP_ENABLED_STATE}
GP_PIN=${GP_PIN}
GP_TIMER_SECS=${GP_TIMER_SECS}
SVEOF
    mv "$_tmp" "$CONFIG"
}

# Load language for overlay messages
load_lang() {
    _raw="en"
    if [ -f "/mnt/SDCARD/system.json" ]; then
        _raw=$(grep -o '"language"[[:space:]]*:[[:space:]]*"[^"]*"' \
            /mnt/SDCARD/system.json | sed 's/.*"\([^"]*\)"/\1/' | head -1)
    fi
    _lower=$(echo "$_raw" | tr 'A-Z' 'a-z')
    case "$_lower" in
        fr*) . "$APPDIR/lang/fr.sh" ;;
        es*) . "$APPDIR/lang/es.sh" ;;
        de*) . "$APPDIR/lang/de.sh" ;;
        it*) . "$APPDIR/lang/it.sh" ;;
        pt*) . "$APPDIR/lang/pt.sh" ;;
        *)   . "$APPDIR/lang/en.sh" ;;
    esac
}

# ============================================================
# GAME STATE DETECTION
# ============================================================

# Returns 0 (true) if any game emulator is running
is_game_running() {
    # RetroArch (most systems)
    pgrep -x retroarch > /dev/null 2>&1 && return 0
    # RetroArch 32-bit (Miyoo Mini)
    pgrep -x ra32 > /dev/null 2>&1 && return 0
    # DraStic (Nintendo DS)
    pgrep -x drastic > /dev/null 2>&1 && return 0
    # PPSSPP (PSP)
    pgrep -x PPSSPPSDL > /dev/null 2>&1 && return 0
    return 1
}

# Get game name from cmd_to_run.sh (best effort)
get_game_name() {
    _cmd_file="$SYSDIR/cmd_to_run.sh"
    if [ -f "$_cmd_file" ]; then
        # Extract the last quoted argument (= the ROM path)
        _rompath=$(sed 's/.*"\([^"]*\)"[[:space:]]*$/\1/' "$_cmd_file" 2>/dev/null)
        if [ -n "$_rompath" ]; then
            # Return filename without extension
            _base=$(basename "$_rompath")
            echo "${_base%.*}"
            return
        fi
    fi
    echo "Unknown"
}

# ============================================================
# NOTIFICATIONS
# ============================================================

show_overlay() {
    "$INFOPANEL" --title "$1" --message "$2" --auto &
}

# Kill the currently running game — use same signal pattern as Onion OS
force_stop_game() {
    log "Time is up! Force stopping game..."
    show_overlay "$GP_NOTIF_GAMEOVER_TITLE" "$GP_NOTIF_GAMEOVER_MSG"
    sleep 3

    # Graceful first (same pattern as Onion runtime.sh)
    killall retroarch 2>/dev/null
    killall ra32 2>/dev/null
    killall drastic 2>/dev/null
    killall PPSSPPSDL 2>/dev/null
    sleep 2

    # Force kill if still alive
    killall -9 retroarch 2>/dev/null
    killall -9 ra32 2>/dev/null
    killall -9 drastic 2>/dev/null
    killall -9 PPSSPPSDL 2>/dev/null

    # Remove cmd_to_run.sh so Onion goes back to MainUI
    rm -f "$SYSDIR/cmd_to_run.sh" 2>/dev/null
    log "Game forcibly stopped."
}

# ============================================================
# STATS & HISTORY
# ============================================================

record_session_start() {
    _game="$1"
    _ts=$(date '+%Y-%m-%d %H:%M:%S')
    mkdir -p "$DATADIR"
    echo "${_ts}|${_game}" >> "$HISTORY_FILE"
    log "Session started: $_game"

    # Rotate if history > 500 MB
    _sz=$(wc -c < "$HISTORY_FILE" 2>/dev/null || echo 0)
    if [ "$_sz" -gt 524288000 ]; then
        tail -500 "$HISTORY_FILE" > /tmp/gp_hist_tmp && mv /tmp/gp_hist_tmp "$HISTORY_FILE"
        log "History rotated (was ${_sz} bytes)"
    fi
}

record_session_stop() {
    _game="$1"
    _sess="$2"
    [ "$_sess" -le 0 ] 2>/dev/null && return

    mkdir -p "$DATADIR"
    touch "$STATS_FILE"

    # Use grep -F for fixed string (safe with special chars in ROM names)
    if grep -Fq "${_game}|" "$STATS_FILE" 2>/dev/null; then
        _cur=$(grep -F "${_game}|" "$STATS_FILE" | head -1 | cut -d'|' -f2)
        _cur=$(( ${_cur:-0} + 0 ))
        _new=$(( _cur + _sess ))
        grep -Fv "${_game}|" "$STATS_FILE" > /tmp/gp_stats_tmp
        echo "${_game}|${_new}" >> /tmp/gp_stats_tmp
        mv /tmp/gp_stats_tmp "$STATS_FILE"
    else
        echo "${_game}|${_sess}" >> "$STATS_FILE"
    fi
    log "Session recorded: $_game - ${_sess}s"
}

# ============================================================
# MAIN DAEMON LOOP
# ============================================================

main() {
    # Prevent double-start
    if [ -f "$PIDFILE" ]; then
        _old=$(cat "$PIDFILE")
        if kill -0 "$_old" 2>/dev/null; then
            log "Daemon already running (PID $_old). Exiting."
            exit 0
        fi
    fi
    echo $$ > "$PIDFILE"

    log "GuardianPlay Daemon started (PID $$)"

    load_lang
    load_config

    _was_running=0
    _sess_start=0
    _game=""
    _notif_10=0
    _notif_5=0
    _notif_1=0
    _save_counter=0

    while true; do
        # Reload config if UI changed it
        if [ -f /tmp/gp_config_changed ]; then
            rm -f /tmp/gp_config_changed
            load_config
            log "Config reloaded. Enabled=$GP_ENABLED_STATE Timer=${GP_TIMER_SECS}s"
        fi

        # --- GAME STATE MACHINE ---
        if is_game_running; then
            if [ "$_was_running" -eq 0 ]; then
                # == GAME JUST STARTED ==
                _was_running=1
                _sess_start=$(date +%s)
                _game=$(get_game_name)
                _notif_10=0
                _notif_5=0
                _notif_1=0
                _save_counter=0
                log "Game started: $_game"
                record_session_start "$_game"
            fi

            # Only count down if parental enabled AND no parent bypass
            if [ "$GP_ENABLED_STATE" -eq 1 ] && [ ! -f /tmp/gp_bypass_active ]; then
                GP_TIMER_SECS=$(( GP_TIMER_SECS - 1 ))
                [ "$GP_TIMER_SECS" -lt 0 ] && GP_TIMER_SECS=0

                # Save to SD every 10 seconds (reduce flash wear)
                _save_counter=$(( _save_counter + 1 ))
                if [ "$_save_counter" -ge 10 ]; then
                    _save_counter=0
                    save_timer
                fi

                _mins=$(( GP_TIMER_SECS / 60 ))

                # --- Notifications ---
                if [ "$_mins" -le 10 ] && [ "$_mins" -gt 5 ] && [ "$_notif_10" -eq 0 ]; then
                    _notif_10=1
                    show_overlay "$GP_APP_NAME" "$GP_NOTIF_10MIN"
                    log "Notification: 10 min warning"
                fi

                if [ "$_mins" -le 5 ] && [ "$_mins" -gt 1 ] && [ "$_notif_5" -eq 0 ]; then
                    _notif_5=1
                    show_overlay "$GP_APP_NAME" "$GP_NOTIF_5MIN"
                    log "Notification: 5 min warning"
                fi

                if [ "$_mins" -le 1 ] && [ "$GP_TIMER_SECS" -gt 0 ] && [ "$_notif_1" -eq 0 ]; then
                    _notif_1=1
                    show_overlay "$GP_APP_NAME" "$GP_NOTIF_1MIN"
                    log "Notification: 1 min warning"
                fi

                # --- TIME UP: KILL GAME ---
                if [ "$GP_TIMER_SECS" -le 0 ]; then
                    log "Time is up for: $_game"
                    _elapsed=$(( $(date +%s) - _sess_start ))
                    record_session_stop "$_game" "$_elapsed"
                    GP_TIMER_SECS=0
                    save_timer
                    force_stop_game
                    _was_running=0
                    _game=""
                    rm -f /tmp/gp_bypass_active
                    sleep 3
                    continue
                fi
            fi

        else
            if [ "$_was_running" -eq 1 ]; then
                # == GAME JUST STOPPED ==
                _was_running=0
                _elapsed=$(( $(date +%s) - _sess_start ))
                log "Game stopped: $_game (session: ${_elapsed}s)"
                record_session_stop "$_game" "$_elapsed"
                save_timer
                _game=""
                _notif_10=0
                _notif_5=0
                _notif_1=0
                rm -f /tmp/gp_bypass_active
            fi
        fi

        sleep 1
    done
}

# Trap for clean shutdown
cleanup() {
    log "Daemon stopped."
    rm -f "$PIDFILE"
    exit 0
}
trap cleanup TERM INT

main "$@"
