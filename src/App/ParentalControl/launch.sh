#!/bin/sh
# ============================================================
# GuardianPlay — App Launcher
# Onion OS Parental Control Add-on
# ============================================================
echo "[GuardianPlay] Starting UI..."
cd "$(dirname "$0")"

# Set up PATH and library paths for Onion OS binaries
export SYSDIR="/mnt/SDCARD/.tmp_update"
export LD_LIBRARY_PATH="/lib:/config/lib:/mnt/SDCARD/miyoo/lib:$SYSDIR/lib:$SYSDIR/lib/parasyte"
export PATH="$SYSDIR/bin:$PATH"

# Ensure the background daemon is running (tracks play time and history)
_pidfile="/tmp/guardianplay_daemon.pid"
_daemon_running=0
if [ -f "$_pidfile" ]; then
    _pid=$(cat "$_pidfile")
    kill -0 "$_pid" 2>/dev/null && _daemon_running=1
fi
if [ "$_daemon_running" -eq 0 ]; then
    echo "[GuardianPlay] Starting daemon..."
    sh ./parental_daemon.sh > /dev/null 2>&1 &
fi

# Launch the main UI
./parental_ui.sh
