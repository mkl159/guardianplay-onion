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

# Launch the main UI
./parental_ui.sh
