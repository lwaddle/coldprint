#!/bin/zsh
source ${0:A:h}/helpers.zsh
COLDPRINT_LIB=1 source ${0:A:h}/../coldprint

# All clear.
_tm_autobackup() { print -r -- "0" }
_tm_running()    { print -r -- "0" }
_pgrep_agent()   { return 1 }
assert_eq "no agents means empty output" "" "$(detect_backup_agents)"

# Armed but idle must still trip: TM can fire mid-print.
_tm_autobackup() { print -r -- "1" }
_tm_running()    { print -r -- "0" }
assert_eq "armed-but-idle Time Machine trips the gate" \
    "Time Machine: AutoBackup is enabled (can start mid-print)" \
    "$(detect_backup_agents)"

# Actively running.
_tm_autobackup() { print -r -- "0" }
_tm_running()    { print -r -- "1" }
assert_eq "running Time Machine trips the gate" \
    "Time Machine: a backup is in progress" \
    "$(detect_backup_agents)"

# Absent preference file yields empty string, must not trip.
_tm_autobackup() { print -r -- "" }
_tm_running()    { print -r -- "0" }
assert_eq "missing AutoBackup pref does not trip" "" "$(detect_backup_agents)"

# Process detection.
_tm_autobackup() { print -r -- "0" }
_tm_running()    { print -r -- "0" }
_pgrep_agent()   { [[ "$1" == "bztransmit" ]] }
assert_eq "matched process trips the gate" \
    "Process: bztransmit" "$(detect_backup_agents)"

# backupd must not be in the list: it is always resident on macOS 26 and
# would trip the gate on every run.
assert_eq "backupd is not a scanned pattern" \
    "" "${BACKUP_AGENT_PATTERNS[(r)backupd]}"

# Multiple simultaneous trips are all reported.
_tm_autobackup() { print -r -- "1" }
_pgrep_agent()   { [[ "$1" == "bzserv" || "$1" == "ChronoSync" ]] }
assert_eq "all live items are reported" \
    "Time Machine: AutoBackup is enabled (can start mid-print)
Process: bzserv
Process: ChronoSync" \
    "$(detect_backup_agents)"

# --- display ------------------------------------------------------------
# Regression: "${prefix}${^array}" inside double quotes collapses to a single
# word, which put every live agent on one unreadable line.
assert_eq "each item prints on its own line" \
    "  ! one
  ! two
  ! three" \
    "$(print_indented '  ! ' 'one' 'two' 'three')"

assert_eq "entries containing spaces stay on one line each" \
    "    Time Machine: AutoBackup is enabled
    Process: bztransmit" \
    "$(print_indented '    ' 'Time Machine: AutoBackup is enabled' 'Process: bztransmit')"

assert_eq "a single item still works" \
    "  x" "$(print_indented '  ' 'x')"

assert_eq "no items prints nothing" \
    "" "$(print_indented '  ')"

# The gate itself must render one agent per line.
detect_backup_agents() { print -rl -- "Agent one" "Agent two" "Agent three" }
assert_eq "backup_gate lists each live agent on its own line" \
    "3" \
    "$(printf 'OVERRIDE\n' | backup_gate 2>&1 >/dev/null | grep -c '^    Agent')"

finish
