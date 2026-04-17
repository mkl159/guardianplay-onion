#!/bin/sh
# ============================================================
# GuardianPlay v1.0 — Pre-Launch Hook (with PIN Bypass)
# ============================================================
# Called by the patched runtime.sh BEFORE each game launches.
#
# BEHAVIOUR (when parental control is ENABLED):
#   Prompt for PIN at every game launch:
#     Correct PIN   -> launch allowed, timer NOT counted
#     Cancel (B)    -> launch allowed if time > 0, timer IS counted
#     Time=0 + no PIN -> launch BLOCKED
#
# Exit codes:
#   0 = launch allowed
#   1 = launch BLOCKED
#
# Side effect: creates /tmp/gp_bypass_active when correct PIN entered.
# The daemon reads this flag to skip countdown.
# ============================================================

APPDIR="/mnt/SDCARD/App/ParentalControl"
SYSDIR="/mnt/SDCARD/.tmp_update"
CONFIG="$APPDIR/data/config.cfg"

PROMPT="$SYSDIR/bin/prompt"
INFOPANEL="$SYSDIR/bin/infoPanel"

export LD_LIBRARY_PATH="/lib:/config/lib:/mnt/SDCARD/miyoo/lib:$SYSDIR/lib:$SYSDIR/lib/parasyte"
export PATH="$SYSDIR/bin:$PATH"

# --- Load config ---
if [ -f "$CONFIG" ]; then
    . "$CONFIG"
fi
GP_ENABLED_STATE=$(( ${GP_ENABLED_STATE:-0} + 0 ))
GP_TIMER_SECS=$(( ${GP_TIMER_SECS:-0} + 0 ))
GP_PIN="${GP_PIN:-0000}"

# --- If parental control is disabled: silent pass-through ---
if [ "$GP_ENABLED_STATE" -eq 0 ]; then
    rm -f /tmp/gp_bypass_active
    exit 0
fi

# --- Load language strings ---
load_lang() {
    _raw="en"
    if [ -f "/mnt/SDCARD/system.json" ]; then
        _raw=$(grep -o '"language"[[:space:]]*:[[:space:]]*"[^"]*"' \
            /mnt/SDCARD/system.json | sed 's/.*"\([^"]*\)"/\1/' | head -1)
    fi
    _lower=$(echo "$_raw" | tr 'A-Z' 'a-z')
    case "$_lower" in
        fr*)
            L_TITLE="GuardianPlay"
            L_MSG="Entrez le code PIN parent\npour jouer sans limite de temps.\n\nAppuyez B pour jouer normalement"
            L_DIGIT="Chiffre %d sur 4"
            L_BYPASS_OK="Mode parent active !\nTemps de jeu illimite."
            L_BLOCKED_TITLE="Temps de jeu epuise"
            L_BLOCKED_MSG="Plus de temps de jeu disponible.\nDemandez l'autorisation a un parent."
            ;;
        es*)
            L_TITLE="GuardianPlay"
            L_MSG="Introduzca el PIN de padre\npara jugar sin limite de tiempo.\n\nPulse B para jugar normalmente"
            L_DIGIT="Digito %d de 4"
            L_BYPASS_OK="Modo padre activado!\nTiempo de juego ilimitado."
            L_BLOCKED_TITLE="Tiempo de juego agotado"
            L_BLOCKED_MSG="No queda tiempo de juego.\nPida permiso a un padre."
            ;;
        de*)
            L_TITLE="GuardianPlay"
            L_MSG="Eltern-PIN eingeben\num ohne Zeitlimit zu spielen.\n\nB druecken fuer normales Spielen"
            L_DIGIT="Ziffer %d von 4"
            L_BYPASS_OK="Elternmodus aktiv!\nUnbegrenzte Spielzeit."
            L_BLOCKED_TITLE="Spielzeit abgelaufen"
            L_BLOCKED_MSG="Keine Spielzeit mehr verfuegbar.\nFragen Sie einen Elternteil."
            ;;
        it*)
            L_TITLE="GuardianPlay"
            L_MSG="Inserire il PIN genitore\nper giocare senza limiti.\n\nPremere B per giocare normalmente"
            L_DIGIT="Cifra %d di 4"
            L_BYPASS_OK="Modalita genitore attiva!\nTempo di gioco illimitato."
            L_BLOCKED_TITLE="Tempo di gioco esaurito"
            L_BLOCKED_MSG="Nessun tempo di gioco disponibile.\nChiedere il permesso a un genitore."
            ;;
        pt*)
            L_TITLE="GuardianPlay"
            L_MSG="Introduza o PIN parental\npara jogar sem limite de tempo.\n\nPrima B para jogar normalmente"
            L_DIGIT="Digito %d de 4"
            L_BYPASS_OK="Modo parental ativo!\nTempo de jogo ilimitado."
            L_BLOCKED_TITLE="Tempo de jogo esgotado"
            L_BLOCKED_MSG="Sem tempo de jogo disponivel.\nPeca autorizacao a um adulto."
            ;;
        *)
            L_TITLE="GuardianPlay"
            L_MSG="Enter parent PIN\nto play with no time limit.\n\nPress B to play with timer"
            L_DIGIT="Digit %d of 4"
            L_BYPASS_OK="Parent mode active!\nUnlimited play time."
            L_BLOCKED_TITLE="No Play Time Left"
            L_BLOCKED_MSG="No more play time available.\nAsk a parent for permission."
            ;;
    esac
}

# Block and show message
block_launch() {
    if [ -x "$INFOPANEL" ]; then
        "$INFOPANEL" --title "$L_BLOCKED_TITLE" --message "$L_BLOCKED_MSG" --auto
    fi
    rm -f /tmp/gp_bypass_active
    exit 1
}

# Allow launch without bypass (timer will count)
allow_with_timer() {
    rm -f /tmp/gp_bypass_active
    if [ "$GP_TIMER_SECS" -le 0 ]; then
        block_launch
    fi
    exit 0
}

# ============================================================
# MAIN
# ============================================================

load_lang

# Ensure daemon is running (starts it if the startup script didn't)
_pidfile="/tmp/guardianplay_daemon.pid"
_running=0
if [ -f "$_pidfile" ]; then
    _pid=$(cat "$_pidfile")
    kill -0 "$_pid" 2>/dev/null && _running=1
fi
[ "$_running" -eq 0 ] && sh "$APPDIR/parental_daemon.sh" &

# Check if prompt binary is available
if [ ! -x "$PROMPT" ]; then
    # No prompt available — just check time
    if [ "$GP_TIMER_SECS" -le 0 ]; then
        exit 1
    fi
    rm -f /tmp/gp_bypass_active
    exit 0
fi

# Digit 1 — also shows the bypass explanation
"$PROMPT" -t "$L_TITLE" -m "$(printf "$L_DIGIT" 1)\n\n$L_MSG" \
    "0" "1" "2" "3" "4" "5" "6" "7" "8" "9"
d1=$?
[ "$d1" -ge 10 ] && allow_with_timer

# Digit 2
"$PROMPT" -t "$L_TITLE" -m "$(printf "$L_DIGIT" 2)" \
    "0" "1" "2" "3" "4" "5" "6" "7" "8" "9"
d2=$?
[ "$d2" -ge 10 ] && allow_with_timer

# Digit 3
"$PROMPT" -t "$L_TITLE" -m "$(printf "$L_DIGIT" 3)" \
    "0" "1" "2" "3" "4" "5" "6" "7" "8" "9"
d3=$?
[ "$d3" -ge 10 ] && allow_with_timer

# Digit 4
"$PROMPT" -t "$L_TITLE" -m "$(printf "$L_DIGIT" 4)" \
    "0" "1" "2" "3" "4" "5" "6" "7" "8" "9"
d4=$?
[ "$d4" -ge 10 ] && allow_with_timer

# Check PIN
ENTERED="${d1}${d2}${d3}${d4}"

if [ "$ENTERED" = "$GP_PIN" ]; then
    # Correct PIN: bypass mode
    touch /tmp/gp_bypass_active
    if [ -x "$INFOPANEL" ]; then
        "$INFOPANEL" --title "$L_TITLE" --message "$L_BYPASS_OK" --auto
    fi
    exit 0
else
    # Wrong PIN: treat as no PIN
    allow_with_timer
fi
