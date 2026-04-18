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
STATS_FILE="$APPDIR/data/stats.dat"

PROMPT="$SYSDIR/bin/prompt"
INFOPANEL="$SYSDIR/bin/infoPanel"

# ROM path passed by runtime.sh
GP_ROM_PATH="${1:-}"

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
            L_INFO_TITLE="Temps de jeu"
            L_INFO_LEFT="Temps restant :"
            L_INFO_PLAYED="Deja joue sur ce jeu :"
            L_H="h"; L_MIN="min"; L_SEC="sec"
            ;;
        es*)
            L_TITLE="GuardianPlay"
            L_MSG="Introduzca el PIN de padre\npara jugar sin limite de tiempo.\n\nPulse B para jugar normalmente"
            L_DIGIT="Digito %d de 4"
            L_BYPASS_OK="Modo padre activado!\nTiempo de juego ilimitado."
            L_BLOCKED_TITLE="Tiempo de juego agotado"
            L_BLOCKED_MSG="No queda tiempo de juego.\nPida permiso a un padre."
            L_INFO_TITLE="Tiempo de juego"
            L_INFO_LEFT="Tiempo restante:"
            L_INFO_PLAYED="Ya jugado en este juego:"
            L_H="h"; L_MIN="min"; L_SEC="seg"
            ;;
        de*)
            L_TITLE="GuardianPlay"
            L_MSG="Eltern-PIN eingeben\num ohne Zeitlimit zu spielen.\n\nB druecken fuer normales Spielen"
            L_DIGIT="Ziffer %d von 4"
            L_BYPASS_OK="Elternmodus aktiv!\nUnbegrenzte Spielzeit."
            L_BLOCKED_TITLE="Spielzeit abgelaufen"
            L_BLOCKED_MSG="Keine Spielzeit mehr verfuegbar.\nFragen Sie einen Elternteil."
            L_INFO_TITLE="Spielzeit"
            L_INFO_LEFT="Verbleibende Zeit:"
            L_INFO_PLAYED="Bereits gespielt:"
            L_H="Std"; L_MIN="Min"; L_SEC="Sek"
            ;;
        it*)
            L_TITLE="GuardianPlay"
            L_MSG="Inserire il PIN genitore\nper giocare senza limiti.\n\nPremere B per giocare normalmente"
            L_DIGIT="Cifra %d di 4"
            L_BYPASS_OK="Modalita genitore attiva!\nTempo di gioco illimitato."
            L_BLOCKED_TITLE="Tempo di gioco esaurito"
            L_BLOCKED_MSG="Nessun tempo di gioco disponibile.\nChiedere il permesso a un genitore."
            L_INFO_TITLE="Tempo di gioco"
            L_INFO_LEFT="Tempo rimanente:"
            L_INFO_PLAYED="Gia giocato a questo gioco:"
            L_H="h"; L_MIN="min"; L_SEC="sec"
            ;;
        pt*)
            L_TITLE="GuardianPlay"
            L_MSG="Introduza o PIN parental\npara jogar sem limite de tempo.\n\nPrima B para jogar normalmente"
            L_DIGIT="Digito %d de 4"
            L_BYPASS_OK="Modo parental ativo!\nTempo de jogo ilimitado."
            L_BLOCKED_TITLE="Tempo de jogo esgotado"
            L_BLOCKED_MSG="Sem tempo de jogo disponivel.\nPeca autorizacao a um adulto."
            L_INFO_TITLE="Tempo de jogo"
            L_INFO_LEFT="Tempo restante:"
            L_INFO_PLAYED="Ja jogado neste jogo:"
            L_H="h"; L_MIN="min"; L_SEC="seg"
            ;;
        *)
            L_TITLE="GuardianPlay"
            L_MSG="Enter parent PIN\nto play with no time limit.\n\nPress B to play with timer"
            L_DIGIT="Digit %d of 4"
            L_BYPASS_OK="Parent mode active!\nUnlimited play time."
            L_BLOCKED_TITLE="No Play Time Left"
            L_BLOCKED_MSG="No more play time available.\nAsk a parent for permission."
            L_INFO_TITLE="Play Time"
            L_INFO_LEFT="Time remaining:"
            L_INFO_PLAYED="Already played on this game:"
            L_H="h"; L_MIN="min"; L_SEC="sec"
            ;;
    esac
}

# Format seconds as "Xh YYmin", "YYmin", or "NNsec"
format_time_hook() {
    _s="$1"
    _h=$(( _s / 3600 ))
    _m=$(( (_s % 3600) / 60 ))
    _sec=$(( _s % 60 ))
    if [ "$_h" -gt 0 ]; then
        printf "%d%s %02d%s" "$_h" "$L_H" "$_m" "$L_MIN"
    elif [ "$_m" -gt 0 ]; then
        printf "%d%s" "$_m" "$L_MIN"
    else
        printf "%d%s" "$_sec" "$L_SEC"
    fi
}

# Total seconds already recorded for this game (0 if never played)
get_played_seconds() {
    _g="$1"
    [ ! -f "$STATS_FILE" ] && { echo 0; return; }
    _v=$(grep -F "${_g}|" "$STATS_FILE" 2>/dev/null | head -1 | cut -d'|' -f2)
    echo "${_v:-0}"
}

# Popup shown right before the game starts when the user chose timed play (B)
show_prelaunch_info() {
    [ ! -x "$INFOPANEL" ] && return
    _base=$(basename "$GP_ROM_PATH")
    _game="${_base%.*}"
    _left=$(format_time_hook "$GP_TIMER_SECS")
    _played=$(get_played_seconds "$_game")

    if [ "$_played" -gt 0 ]; then
        _played_fmt=$(format_time_hook "$_played")
        _msg="$L_INFO_LEFT $_left\n\n$L_INFO_PLAYED\n$_played_fmt"
    else
        _msg="$L_INFO_LEFT $_left"
    fi

    # Show the popup for ~4 seconds, then close it
    "$INFOPANEL" --title "$L_INFO_TITLE" --message "$_msg" --persistent > /dev/null 2>&1 &
    _ip_pid=$!
    sleep 4
    kill -9 "$_ip_pid" 2>/dev/null
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
    show_prelaunch_info
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
if [ "$_running" -eq 0 ]; then
    sh "$APPDIR/parental_daemon.sh" > /dev/null 2>&1 &
fi

# Check if prompt binary is available
if [ ! -x "$PROMPT" ]; then
    # No prompt available — just check time
    if [ "$GP_TIMER_SECS" -le 0 ]; then
        exit 1
    fi
    rm -f /tmp/gp_bypass_active
    exit 0
fi

# Phone-keypad-style digit prompt: returns 0-9 or sets _cancel=1
ask_digit_hook() {
    "$PROMPT" -t "$L_TITLE" -m "$1" \
        "1" "2" "3" \
        "4" "5" "6" \
        "7" "8" "9" \
        "0"
    _rc=$?
    if [ "$_rc" -ge 10 ]; then
        _cancel=1
        return 0
    fi
    if [ "$_rc" -eq 9 ]; then
        _dval=0
    else
        _dval=$(( _rc + 1 ))
    fi
}

_cancel=0

# Digit 1 — also shows the bypass explanation
ask_digit_hook "$(printf "$L_DIGIT" 1)\n\n$L_MSG\n\n_ _ _ _"
[ "$_cancel" -eq 1 ] && allow_with_timer
d1=$_dval

# Digit 2
ask_digit_hook "$(printf "$L_DIGIT" 2)\n\n* _ _ _"
[ "$_cancel" -eq 1 ] && allow_with_timer
d2=$_dval

# Digit 3
ask_digit_hook "$(printf "$L_DIGIT" 3)\n\n* * _ _"
[ "$_cancel" -eq 1 ] && allow_with_timer
d3=$_dval

# Digit 4
ask_digit_hook "$(printf "$L_DIGIT" 4)\n\n* * * _"
[ "$_cancel" -eq 1 ] && allow_with_timer
d4=$_dval

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
