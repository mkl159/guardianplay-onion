#!/bin/sh
# ============================================================
# GuardianPlay v1.0 — Pre-Launch Hook (with PIN Bypass)
# ============================================================
# Called by the patched runtime.sh BEFORE each game launches.
#
# BEHAVIOUR:
#  - If parental control is DISABLED → launch allowed silently.
#  - If parental control is ENABLED:
#      → Prompt for PIN at every launch.
#        • Correct PIN  → launch allowed, timer NOT counted.
#        • No PIN / cancelled → launch allowed, timer IS counted.
#        • Time == 0 + No PIN  → launch BLOCKED.
#
# Exit codes:
#   0 = launch allowed  (with or without timer counting)
#   1 = launch BLOCKED
#
# Side effect: creates /tmp/gp_bypass_active when PIN was entered
# correctly. The daemon reads this flag to skip countdown.
#
# Usage: parental_hook.sh [rom_path]
# ============================================================

APPDIR="/mnt/SDCARD/App/ParentalControl"
SYSDIR="/mnt/SDCARD/.tmp_update"
DATADIR="$APPDIR/data"
CONFIG="$DATADIR/config.cfg"

PROMPT="$SYSDIR/bin/prompt"
INFOPANEL="$SYSDIR/bin/infoPanel"

export LD_LIBRARY_PATH="/lib:/config/lib:/mnt/SDCARD/miyoo/lib:$SYSDIR/lib:$SYSDIR/lib/parasyte"
export PATH="$SYSDIR/bin:$PATH"

# --- Load config ---
if [ -f "$CONFIG" ]; then
    . "$CONFIG"
fi
GP_ENABLED_STATE=$(( ${GP_ENABLED_STATE:-0} + 0 ))
GP_TIME_REMAINING=$(( ${GP_TIME_REMAINING:-0} + 0 ))
GP_PIN="${GP_PIN:-0000}"

# --- If parental control is disabled: silent pass-through ---
if [ "$GP_ENABLED_STATE" -eq 0 ]; then
    rm -f /tmp/gp_bypass_active
    exit 0
fi

# --- Load language strings ---
load_lang() {
    local sys_lang="en"
    if [ -f "/mnt/SDCARD/system.json" ]; then
        sys_lang=$(grep -o '"language"[[:space:]]*:[[:space:]]*"[^"]*"' \
            /mnt/SDCARD/system.json | sed 's/.*"\([^"]*\)"/\1/' | head -1)
    fi
    case "$sys_lang" in
        fr|french|FR)
            L_HOOK_TITLE="🛡️ GuardianPlay"
            L_HOOK_MSG="Entrez le code PIN parent\npour jouer sans limite de temps.\n(Appuyez sur B pour jouer normalement)"
            L_DIGIT="Chiffre %d/4"
            L_BYPASS_OK="✅ Mode parent activé !\nTemps de jeu illimité."
            L_PLAY_LIMITED="▶ Lancement avec minuterie\n(Temps restant : %s)"
            L_BLOCKED_TITLE="⛔ Temps de jeu épuisé"
            L_BLOCKED_MSG="Plus de temps de jeu disponible.\nDemandez l'autorisation à un parent."
            L_MINS="min"
            L_HOURS="h"
            ;;
        es|spanish|ES)
            L_HOOK_TITLE="🛡️ GuardianPlay"
            L_HOOK_MSG="Introduzca el PIN de padre\npara jugar sin límite de tiempo.\n(Pulse B para jugar normalmente)"
            L_DIGIT="Dígito %d/4"
            L_BYPASS_OK="✅ ¡Modo padre activado!\nTiempo de juego ilimitado."
            L_PLAY_LIMITED="▶ Inicio con temporizador\n(Tiempo restante: %s)"
            L_BLOCKED_TITLE="⛔ Tiempo de juego agotado"
            L_BLOCKED_MSG="No queda tiempo de juego.\nPida permiso a un padre."
            L_MINS="min"
            L_HOURS="h"
            ;;
        *)
            L_HOOK_TITLE="🛡️ GuardianPlay"
            L_HOOK_MSG="Enter parent PIN\nto play with no time limit.\n(Press B to play with timer)"
            L_DIGIT="Digit %d/4"
            L_BYPASS_OK="✅ Parent mode active!\nUnlimited play time."
            L_PLAY_LIMITED="▶ Launching with timer\n(Time left: %s)"
            L_BLOCKED_TITLE="⛔ No Play Time Left"
            L_BLOCKED_MSG="No more play time available.\nAsk a parent for permission."
            L_MINS="min"
            L_HOURS="h"
            ;;
    esac
}

# Format seconds as readable time
fmt_time() {
    local t="$1"
    local h=$(( t / 3600 ))
    local m=$(( (t % 3600) / 60 ))
    if [ "$h" -gt 0 ]; then
        printf "%d%s %02d%s" "$h" "$L_HOURS" "$m" "$L_MINS"
    elif [ "$m" -gt 0 ]; then
        printf "%d%s" "$m" "$L_MINS"
    else
        printf "< 1%s" "$L_MINS"
    fi
}

# Enter one digit via prompt; returns digit (0-9) or 255 (cancelled/B)
ask_digit() {
    local title="$1"
    local msg="$2"
    "$PROMPT" -t "$title" -m "$msg" \
        "0" "1" "2" "3" "4" "5" "6" "7" "8" "9"
    return $?
}

# --- Main logic ---

load_lang

# Check if prompt is available (it might not be during very early boot)
if [ ! -x "$PROMPT" ]; then
    # Fallback: just check time without PIN prompt
    if [ "$GP_TIME_REMAINING" -le 0 ]; then
        exit 1
    fi
    rm -f /tmp/gp_bypass_active
    exit 0
fi

# Show PIN entry prompt
# User can press B (returns 255) to skip PIN and play with timer
"$PROMPT" -t "$L_HOOK_TITLE" -m "$L_HOOK_MSG" \
    "0" "1" "2" "3" "4" "5" "6" "7" "8" "9"
d1=$?

if [ "$d1" -eq 255 ]; then
    # --- User pressed B: play normally with timer ---
    rm -f /tmp/gp_bypass_active
    if [ "$GP_TIME_REMAINING" -le 0 ]; then
        # Time is up AND no PIN → BLOCK
        if [ -x "$INFOPANEL" ]; then
            "$INFOPANEL" --title "$L_BLOCKED_TITLE" --message "$L_BLOCKED_MSG" --auto
        fi
        exit 1
    fi
    # Launch with timer running
    exit 0
fi

# User started entering PIN — collect remaining 3 digits
ask_digit "$L_HOOK_TITLE" "$(printf "$L_DIGIT" 2)"
d2=$?
if [ "$d2" -eq 255 ]; then
    rm -f /tmp/gp_bypass_active
    [ "$GP_TIME_REMAINING" -le 0 ] && exit 1
    exit 0
fi

ask_digit "$L_HOOK_TITLE" "$(printf "$L_DIGIT" 3)"
d3=$?
if [ "$d3" -eq 255 ]; then
    rm -f /tmp/gp_bypass_active
    [ "$GP_TIME_REMAINING" -le 0 ] && exit 1
    exit 0
fi

ask_digit "$L_HOOK_TITLE" "$(printf "$L_DIGIT" 4)"
d4=$?
if [ "$d4" -eq 255 ]; then
    rm -f /tmp/gp_bypass_active
    [ "$GP_TIME_REMAINING" -le 0 ] && exit 1
    exit 0
fi

ENTERED_PIN="${d1}${d2}${d3}${d4}"

if [ "$ENTERED_PIN" = "$GP_PIN" ]; then
    # ✅ Correct PIN: bypass mode — no timer, launch allowed even if time=0
    touch /tmp/gp_bypass_active
    if [ -x "$INFOPANEL" ]; then
        "$INFOPANEL" --title "$L_HOOK_TITLE" --message "$L_BYPASS_OK" --auto
    fi
    exit 0
else
    # ❌ Wrong PIN: treat as "no PIN entered" (play with timer)
    rm -f /tmp/gp_bypass_active
    if [ "$GP_TIME_REMAINING" -le 0 ]; then
        if [ -x "$INFOPANEL" ]; then
            "$INFOPANEL" --title "$L_BLOCKED_TITLE" --message "$L_BLOCKED_MSG" --auto
        fi
        exit 1
    fi
    # Wrong PIN but time remaining → launch with timer
    exit 0
fi
