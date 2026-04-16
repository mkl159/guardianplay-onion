#!/bin/sh
# ============================================================
# GuardianPlay v1.0 — Background Timer Daemon
# ============================================================
# This daemon runs in the background from system startup.
# It tracks play time, shows overlay notifications, and
# forces game exit when time runs out.
#
# Started by: /mnt/SDCARD/.tmp_update/startup/guardianplay.sh
# ============================================================

APPDIR="/mnt/SDCARD/App/ParentalControl"
SYSDIR="/mnt/SDCARD/.tmp_update"
DATADIR="$APPDIR/data"
CONFIG="$DATADIR/config.cfg"
STATS_FILE="$DATADIR/stats.csv"
HISTORY_FILE="$DATADIR/history.log"

INFOPANEL="$SYSDIR/bin/infoPanel"
LOGFILE="/tmp/guardianplay_daemon.log"

export LD_LIBRARY_PATH="/lib:/config/lib:/mnt/SDCARD/miyoo/lib:$SYSDIR/lib:$SYSDIR/lib/parasyte"
export PATH="$SYSDIR/bin:$PATH"

# ============================================================
# LOGGING
# ============================================================

log() { echo "$(date '+%H:%M:%S') [GP-Daemon] $1" >> "$LOGFILE"; }
log_err() { echo "$(date '+%H:%M:%S') [GP-Daemon][ERROR] $1" >> "$LOGFILE"; }

# ============================================================
# CONFIG
# ============================================================

load_config() {
    if [ -f "$CONFIG" ]; then
        # shellcheck disable=SC1090
        . "$CONFIG"
    fi
    GP_ENABLED_STATE=$(( ${GP_ENABLED_STATE:-0} + 0 ))
    GP_TIME_REMAINING=$(( ${GP_TIME_REMAINING:-0} + 0 ))
}

save_time() {
    if [ -f "$CONFIG" ]; then
        # Update only GP_TIME_REMAINING in the config file
        local tmpfile="/tmp/gp_cfg_tmp"
        grep -v "^GP_TIME_REMAINING=" "$CONFIG" > "$tmpfile"
        echo "GP_TIME_REMAINING=${GP_TIME_REMAINING}" >> "$tmpfile"
        mv "$tmpfile" "$CONFIG"
    fi
}

# Load language for overlay messages
load_lang() {
    local sys_lang="en"
    if [ -f "/mnt/SDCARD/system.json" ]; then
        sys_lang=$(grep -o '"language"[[:space:]]*:[[:space:]]*"[^"]*"' \
            /mnt/SDCARD/system.json | sed 's/.*"\([^"]*\)"/\1/' | head -1)
    fi
    case "$sys_lang" in
        fr|french|FR) . "$APPDIR/lang/fr.sh" ;;
        es|spanish|ES) . "$APPDIR/lang/es.sh" ;;
        *) . "$APPDIR/lang/en.sh" ;;
    esac
}

# ============================================================
# GAME STATE DETECTION
# ============================================================

# Returns 0 (true) if RetroArch or a game process is running
is_game_running() {
    pgrep -x retroarch > /dev/null 2>&1 && return 0
    pgrep -x ra32 > /dev/null 2>&1 && return 0
    return 1
}

# Get current ROM path from cmd_to_run.sh
get_rom_path() {
    local cmd_file="$SYSDIR/cmd_to_run.sh"
    if [ -f "$cmd_file" ]; then
        # Extract the last quoted argument (the rom path)
        local rompath
        rompath=$(cat "$cmd_file" | awk '{ st = index($0,"\" \""); print substr($0,st+3,length($0)-st-3)}' | tr -d '"')
        echo "$rompath"
    fi
}

# Get game name from ROM path (filename without extension)
get_game_name() {
    local rompath="$1"
    if [ -n "$rompath" ]; then
        basename "$rompath" | sed 's/\.[^.]*$//'
    else
        echo "Unknown"
    fi
}

# ============================================================
# NOTIFICATIONS
# ============================================================

show_overlay() {
    local title="$1"
    local msg="$2"
    "$INFOPANEL" --title "$title" --message "$msg" --auto &
}

# Kill the currently running game and return to MainUI
force_stop_game() {
    log "Time is up! Force stopping game..."
    show_overlay "$GP_NOTIF_GAMEOVER_TITLE" "$GP_NOTIF_GAMEOVER_MSG"
    sleep 3

    # Kill RetroArch
    killall -SIGTERM retroarch 2>/dev/null
    killall -SIGTERM ra32 2>/dev/null
    sleep 2
    killall -SIGKILL retroarch 2>/dev/null
    killall -SIGKILL ra32 2>/dev/null

    # Remove cmd_to_run.sh so Onion goes back to MainUI
    rm -f "$SYSDIR/cmd_to_run.sh" 2>/dev/null

    log "Game forcibly stopped."
}

# ============================================================
# STATS & HISTORY
# ============================================================

record_session_start() {
    local game="$1"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    mkdir -p "$DATADIR"
    echo "${ts}|${game}" >> "$HISTORY_FILE"
    log "Session started: $game"

    # Rotate if history > 500 MB
    local size
    size=$(wc -c < "$HISTORY_FILE" 2>/dev/null || echo 0)
    if [ "$size" -gt 524288000 ]; then
        local tmp="/tmp/gp_history_tmp"
        tail -500 "$HISTORY_FILE" > "$tmp" && mv "$tmp" "$HISTORY_FILE"
        log "History rotated (was ${size} bytes)"
    fi
}

record_session_stop() {
    local game="$1"
    local session_secs="$2"
    [ "$session_secs" -le 0 ] && return

    mkdir -p "$DATADIR"
    touch "$STATS_FILE"

    if grep -q "^${game}," "$STATS_FILE" 2>/dev/null; then
        local current
        current=$(grep "^${game}," "$STATS_FILE" | cut -d',' -f2)
        local new_total=$(( current + session_secs ))
        local tmpfile="/tmp/gp_stats_tmp"
        grep -v "^${game}," "$STATS_FILE" > "$tmpfile"
        echo "${game},${new_total}" >> "$tmpfile"
        mv "$tmpfile" "$STATS_FILE"
    else
        echo "${game},${session_secs}" >> "$STATS_FILE"
    fi
    log "Session recorded: $game — ${session_secs}s (new total)"
}

# ============================================================
# MAIN DAEMON LOOP
# ============================================================

main() {
    # Prevent double-start
    local pid_file="/tmp/guardianplay_daemon.pid"
    if [ -f "$pid_file" ]; then
        local old_pid
        old_pid=$(cat "$pid_file")
        if kill -0 "$old_pid" 2>/dev/null; then
            log "Daemon already running (PID $old_pid). Exiting."
            exit 0
        fi
    fi
    echo $$ > "$pid_file"

    log "GuardianPlay Daemon started (PID $$)"

    load_lang
    load_config

    local was_game_running=0
    local session_start_secs=0
    local current_rom=""
    local current_game=""

    # Notification sentinels (reset each game session)
    local notif_10=0
    local notif_5=0
    local notif_1=0

    while true; do
        # Reload config if it changed (e.g., UI updated time or toggled state)
        if [ -f /tmp/gp_config_changed ]; then
            rm -f /tmp/gp_config_changed
            load_config
            log "Config reloaded. Enabled=$GP_ENABLED_STATE Time=${GP_TIME_REMAINING}s"
        fi

        # --- GAME STATE MACHINE ---
        if is_game_running; then
            if [ "$was_game_running" -eq 0 ]; then
                # Game just STARTED
                was_game_running=1
                session_start_secs=$(date +%s)
                current_rom=$(get_rom_path)
                current_game=$(get_game_name "$current_rom")
                notif_10=0
                notif_5=0
                notif_1=0
                log "Game started: $current_game"
                record_session_start "$current_game"
            fi

            # Only count down if parental control is enabled AND no parent bypass
            # /tmp/gp_bypass_active is set by parental_hook.sh when correct PIN entered
            if [ "$GP_ENABLED_STATE" -eq 1 ] && [ ! -f /tmp/gp_bypass_active ]; then
                # Decrement 1 second
                GP_TIME_REMAINING=$(( GP_TIME_REMAINING - 1 ))
                [ "$GP_TIME_REMAINING" -lt 0 ] && GP_TIME_REMAINING=0

                # Save time every 10 seconds to SD card
                now=$(date +%s)
                elapsed=$(( now - session_start_secs ))
                if [ $(( elapsed % 10 )) -eq 0 ]; then
                    save_time
                fi

                mins_remaining=$(( GP_TIME_REMAINING / 60 ))

                # --- Notifications ---
                if [ "$mins_remaining" -le 10 ] && [ "$mins_remaining" -gt 5 ] && [ "$notif_10" -eq 0 ]; then
                    notif_10=1
                    show_overlay "$GP_APP_NAME" "$GP_NOTIF_10MIN"
                    log "Notification: 10 min warning"
                fi

                if [ "$mins_remaining" -le 5 ] && [ "$mins_remaining" -gt 1 ] && [ "$notif_5" -eq 0 ]; then
                    notif_5=1
                    show_overlay "$GP_APP_NAME" "$GP_NOTIF_5MIN"
                    log "Notification: 5 min warning"
                fi

                if [ "$mins_remaining" -le 1 ] && [ "$GP_TIME_REMAINING" -gt 0 ] && [ "$notif_1" -eq 0 ]; then
                    notif_1=1
                    show_overlay "$GP_APP_NAME" "$GP_NOTIF_1MIN"
                    log "Notification: 1 min warning"
                fi

                # --- Time Up: Kill game ---
                if [ "$GP_TIME_REMAINING" -le 0 ]; then
                    log "Time is up for game: $current_game"
                    session_secs=$(( $(date +%s) - session_start_secs ))
                    record_session_stop "$current_game" "$session_secs"
                    GP_TIME_REMAINING=0
                    save_time
                    force_stop_game
                    was_game_running=0
                    current_rom=""
                    current_game=""
                    rm -f /tmp/gp_bypass_active
                    sleep 3
                    continue
                fi
            fi

        else
            if [ "$was_game_running" -eq 1 ]; then
                # Game just STOPPED
                was_game_running=0
                session_secs=$(( $(date +%s) - session_start_secs ))
                log "Game stopped: $current_game (session: ${session_secs}s)"
                record_session_stop "$current_game" "$session_secs"
                # Save remaining time
                save_time
                current_rom=""
                current_game=""
                notif_10=0
                notif_5=0
                notif_1=0
                # Clear parent bypass flag for next game
                rm -f /tmp/gp_bypass_active
            fi
        fi

        sleep 1
    done
}

# Trap SIGTERM for clean shutdown
trap 'log "Daemon stopped."; rm -f /tmp/guardianplay_daemon.pid; exit 0' TERM INT

main "$@"
