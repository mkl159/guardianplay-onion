#!/bin/sh
# ============================================================
# GuardianPlay v1.0 — Uninstaller
# ============================================================
# Removes GuardianPlay hooks from runtime.sh and
# deletes the daemon startup script.
# Your game data (stats/history) is preserved.
#
# Usage: sh /mnt/SDCARD/App/ParentalControl/uninstall.sh
# ============================================================

APPDIR="/mnt/SDCARD/App/ParentalControl"
SYSDIR="/mnt/SDCARD/.tmp_update"
RUNTIME="$SYSDIR/runtime.sh"
BACKUP_RUNTIME="$SYSDIR/runtime.sh.gp_backup"
STARTUP_SCRIPT="$SYSDIR/startup/guardianplay.sh"

INFOPANEL="$SYSDIR/bin/infoPanel"
export LD_LIBRARY_PATH="/lib:/config/lib:/mnt/SDCARD/miyoo/lib:$SYSDIR/lib:$SYSDIR/lib/parasyte"
export PATH="$SYSDIR/bin:$PATH"

log() { echo "[GuardianPlay Uninstaller] $1"; }

log "=== GuardianPlay v1.0 Uninstaller ==="

# ============================================================
# STEP 1: Stop daemon if running
# ============================================================

if [ -f /tmp/guardianplay_daemon.pid ]; then
    daemon_pid=$(cat /tmp/guardianplay_daemon.pid)
    if kill -0 "$daemon_pid" 2>/dev/null; then
        log "Stopping daemon (PID $daemon_pid)..."
        kill -TERM "$daemon_pid"
        sleep 1
    fi
    rm -f /tmp/guardianplay_daemon.pid
fi

# ============================================================
# STEP 2: Remove startup script
# ============================================================

if [ -f "$STARTUP_SCRIPT" ]; then
    rm -f "$STARTUP_SCRIPT"
    log "Daemon startup script removed."
else
    log "No daemon startup script found (already removed?)."
fi

# ============================================================
# STEP 3: Restore runtime.sh from backup OR strip the patch
# ============================================================

if [ -f "$BACKUP_RUNTIME" ]; then
    log "Restoring runtime.sh from backup..."
    cp "$BACKUP_RUNTIME" "$RUNTIME"
    rm -f "$BACKUP_RUNTIME"
    log "runtime.sh restored from backup."
elif grep -q "GUARDIANPLAY HOOK" "$RUNTIME" 2>/dev/null; then
    log "No backup found. Stripping GuardianPlay hook from runtime.sh..."
    # Remove the injected block using awk
    awk '
    /# === GUARDIANPLAY HOOK ===/ { skip=1 }
    /# === END GUARDIANPLAY HOOK ===/ { skip=0; next }
    !skip { print }
    ' "$RUNTIME" > /tmp/runtime_stripped.sh
    mv /tmp/runtime_stripped.sh "$RUNTIME"
    log "Hook stripped from runtime.sh."
else
    log "No GuardianPlay hook found in runtime.sh (already clean)."
fi

# ============================================================
# DONE
# ============================================================

log ""
log "================================================"
log "  GuardianPlay uninstalled."
log "  Your stats and history data are preserved."
log "  Reboot your device to complete uninstallation."
log "================================================"

exit 0
