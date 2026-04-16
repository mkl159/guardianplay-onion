#!/bin/sh
# ============================================================
# GuardianPlay v1.0 — Installer
# ============================================================
# Run this script ONCE from your Miyoo Mini SD card.
# It patches runtime.sh and sets up the daemon startup.
#
# Usage:
#   Copy the App/ParentalControl folder to:
#   /mnt/SDCARD/App/ParentalControl/
#   Then run: sh /mnt/SDCARD/App/ParentalControl/install.sh
# ============================================================

APPDIR="/mnt/SDCARD/App/ParentalControl"
SYSDIR="/mnt/SDCARD/.tmp_update"
RUNTIME="$SYSDIR/runtime.sh"
STARTUP_DIR="$SYSDIR/startup"
STARTUP_SCRIPT="$STARTUP_DIR/guardianplay.sh"
BACKUP_RUNTIME="$SYSDIR/runtime.sh.gp_backup"

INFOPANEL="$SYSDIR/bin/infoPanel"
export LD_LIBRARY_PATH="/lib:/config/lib:/mnt/SDCARD/miyoo/lib:$SYSDIR/lib:$SYSDIR/lib/parasyte"
export PATH="$SYSDIR/bin:$PATH"

log() { echo "[GuardianPlay Installer] $1"; }
die() { log "ERROR: $1"; exit 1; }

# ============================================================
# PREFLIGHT CHECKS
# ============================================================

log "=== GuardianPlay v1.0 Installer ==="
log "Checking prerequisites..."

[ -d "$APPDIR" ]   || die "App directory not found at $APPDIR"
[ -f "$RUNTIME" ]  || die "runtime.sh not found at $RUNTIME"
[ -x "$INFOPANEL" ] || log "WARNING: infoPanel binary not found — notifications may not work"

# Check if already installed
if grep -q "GUARDIANPLAY" "$RUNTIME" 2>/dev/null; then
    log "GuardianPlay hook already present in runtime.sh."
    log "Run uninstall.sh first if you want to reinstall."
    exit 0
fi

# ============================================================
# STEP 1: Backup runtime.sh
# ============================================================

log "Backing up runtime.sh to $BACKUP_RUNTIME..."
cp "$RUNTIME" "$BACKUP_RUNTIME" || die "Failed to backup runtime.sh"
log "Backup OK."

# ============================================================
# STEP 2: Patch runtime.sh — inject hook after playActivity start
# ============================================================
# We inject a GuardianPlay block right after the line:
#     playActivity start "$rompath"
#
# The patch adds 7 lines. We use awk for a safe, line-based patch.
# ============================================================

log "Patching runtime.sh..."

# Use awk to insert the GuardianPlay hook after the 'playActivity start' line
awk '
/[[:space:]]*playActivity start "\$rompath"/ && !inserted {
    print
    print "        # === GUARDIANPLAY HOOK ==="
    print "        # Block game launch if parental time is exhausted"
    print "        if [ -f \"/mnt/SDCARD/App/ParentalControl/parental_hook.sh\" ]; then"
    print "            /mnt/SDCARD/App/ParentalControl/parental_hook.sh \"$rompath\""
    print "            if [ \$? -ne 0 ]; then"
    print "                playActivity stop \"$rompath\" 2>/dev/null"
    print "                rm -f \$sysdir/cmd_to_run.sh 2>/dev/null"
    print "                return"
    print "            fi"
    print "        fi"
    print "        # === END GUARDIANPLAY HOOK ==="
    inserted=1
    next
}
{ print }
' "$BACKUP_RUNTIME" > "$RUNTIME" || die "Failed to patch runtime.sh"

# Verify patch was applied
if ! grep -q "GUARDIANPLAY HOOK" "$RUNTIME"; then
    log "Patch verification failed! Restoring backup..."
    cp "$BACKUP_RUNTIME" "$RUNTIME"
    die "Could not patch runtime.sh. Please check manually."
fi
log "runtime.sh patched successfully."

# ============================================================
# STEP 3: Install startup script for the daemon
# ============================================================

log "Installing daemon startup script..."
mkdir -p "$STARTUP_DIR"

cat > "$STARTUP_SCRIPT" << 'STARTUP_EOF'
#!/bin/sh
# GuardianPlay daemon startup script
APPDIR="/mnt/SDCARD/App/ParentalControl"
if [ -f "$APPDIR/parental_daemon.sh" ]; then
    chmod +x "$APPDIR/parental_daemon.sh"
    # Start daemon in background (non-blocking)
    sh "$APPDIR/parental_daemon.sh" &
    echo "[GuardianPlay] Daemon started (PID $!)"
fi
STARTUP_EOF

chmod +x "$STARTUP_SCRIPT"
log "Startup script installed at $STARTUP_SCRIPT"

# ============================================================
# STEP 4: Make all scripts executable
# ============================================================

log "Setting executable permissions..."
chmod +x "$APPDIR/launch.sh"
chmod +x "$APPDIR/parental_ui.sh"
chmod +x "$APPDIR/parental_daemon.sh"
chmod +x "$APPDIR/parental_hook.sh"
chmod +x "$APPDIR/uninstall.sh"

# ============================================================
# STEP 5: Create data directory with default config
# ============================================================

mkdir -p "$APPDIR/data"
if [ ! -f "$APPDIR/data/config.cfg" ]; then
    cat > "$APPDIR/data/config.cfg" << 'CFG_EOF'
# GuardianPlay Configuration
GP_ENABLED_STATE=0
GP_PIN=0000
GP_TIME_REMAINING=3600
CFG_EOF
    log "Default config created."
fi

# ============================================================
# DONE
# ============================================================

log ""
log "================================================"
log "  GuardianPlay installed successfully!"
log "================================================"
log "  - Hook injected into runtime.sh"
log "  - Daemon startup: $STARTUP_SCRIPT"
log "  - App location: $APPDIR"
log ""
log "  NEXT STEPS:"
log "  1. Reboot your Miyoo Mini"
log "  2. Open GuardianPlay from the Apps menu"
log "  3. Set your PIN and configure play time"
log "================================================"

# Show success notification if infoPanel is available
if [ -x "$INFOPANEL" ]; then
    "$INFOPANEL" --title "GuardianPlay Installed!" \
        --message "Installation complete!\nReboot your device to activate." \
        --auto
fi

exit 0
