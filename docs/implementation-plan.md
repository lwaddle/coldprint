# coldprint Implementation Plan

> **Historical record.** This is the plan as executed, kept for the reasoning
> it captures. Where it differs from the current code the code is correct —
> notably the cpi ladder, which was replaced by a fixed default after the
> first real print. See [design.md](design.md).

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A zsh script that prints a single- or multi-line secret to paper for a continuity envelope, gating on active backup software and refusing cleartext print transports.

**Architecture:** One auditable file, `coldprint`, composed of small functions with a `main` guarded by `COLDPRINT_LIB` so tests can source it without executing. Rendering is plain text piped to `lp` with explicit `cpi`/`lpi`/margin/`sides` options — resolved empirically, see spec §5. The page builder is a pure function driven by stdin, so it is testable without a printer.

**Tech Stack:** zsh 5.9, base macOS only — `lp`, `lpstat`, `cancel`, `cupsfilter`, `shasum`, `defaults`, `tmutil`, `pgrep`, `stty`. No third-party dependencies. Tests are plain zsh scripts.

## Global Constraints

- Target: macOS 26, CUPS 2.3.x, zsh 5.9. No Homebrew dependencies in the shipped script.
- The secret must never be written to a file, passed as a command-line argument, or placed in an environment variable. It moves only through shell variables and pipes.
- Every `lp` invocation includes `-o sides=one-sided`. The queue default is `*DuplexNoTumble`; without this, copy 2 prints on the back of copy 1.
- Print option set is exactly: `-o cpi=N -o lpi=6 -o page-left=54 -o page-right=54 -o page-top=54 -o page-bottom=54 -o sides=one-sided`.
- cpi ladder and character budgets (usable width 504pt):

  | cpi | pt/char | total chars | secret chars when numbered (gutter 6) |
  |---|---|---|---|
  | 10 | 7.20 | 70 | 64 |
  | 12 | 6.00 | 84 | 78 |
  | 15 | 4.80 | 105 | 99 |
  | 17 | 4.24 | 119 | 113 |

- `backupd` must NOT appear in the process pattern list. It is a permanently-resident daemon on macOS 26 and would trip the gate on every run.
- The override token is the literal uppercase string `OVERRIDE`. Never `y`.
- Exit codes: `0` success or user cancel; `1` usage/validation; `2` backup gate refused; `3` printer selection refused; `4` print submission failed.

---

## File Structure

| File | Responsibility |
|---|---|
| `coldprint` | The entire tool. Functions plus a guarded `main`. |
| `tests/helpers.zsh` | Assertion helpers and the pass/fail counter. |
| `tests/test_transport.zsh` | Transport classifier cases. |
| `tests/test_backup_gate.zsh` | Detection logic against injected fixtures. |
| `tests/test_capture.zsh` | Secret capture: terminators, feedback, flagging. |
| `tests/test_mask.zsh` | Preview masking rules. |
| `tests/test_build_page.zsh` | Page layout, cpi selection, wrapping, checksum. |
| `tests/run_all.zsh` | Runs every `test_*.zsh`, exits non-zero on any failure. |
| `README.md` | Usage plus the threat-model caveats the script cannot enforce. |

Single file for the tool is deliberate: this is a security utility whose value depends on being auditable in one read.

---

### Task 1: Test harness and transport classifier

**Files:**
- Create: `tests/helpers.zsh`
- Create: `tests/run_all.zsh`
- Create: `tests/test_transport.zsh`
- Create: `coldprint`

**Interfaces:**
- Consumes: nothing.
- Produces: `classify_transport(uri) -> "usb" | "ipps" | "cleartext" | "unknown"` on stdout. `assert_eq(desc, expected, actual)` and `finish()` for later test files. Sourcing `coldprint` with `COLDPRINT_LIB=1` set must define functions without running `main`.

- [ ] **Step 1: Write the test harness**

`tests/helpers.zsh`:

```zsh
#!/bin/zsh
typeset -g TESTS_RUN=0 TESTS_FAILED=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    (( TESTS_RUN++ ))
    if [[ "$expected" == "$actual" ]]; then
        print -r -- "  ok   $desc"
    else
        (( TESTS_FAILED++ ))
        print -r -- "  FAIL $desc"
        print -r -- "         expected: ${(qqq)expected}"
        print -r -- "         actual:   ${(qqq)actual}"
    fi
}

assert_status() {
    local desc="$1" expected="$2" actual="$3"
    (( TESTS_RUN++ ))
    if [[ "$expected" == "$actual" ]]; then
        print -r -- "  ok   $desc"
    else
        (( TESTS_FAILED++ ))
        print -r -- "  FAIL $desc (exit $actual, wanted $expected)"
    fi
}

finish() {
    print -r -- "$TESTS_RUN run, $TESTS_FAILED failed"
    (( TESTS_FAILED == 0 ))
}
```

`tests/run_all.zsh`:

```zsh
#!/bin/zsh
cd ${0:A:h}
typeset -i failed=0
for t in test_*.zsh; do
    print -r -- "== $t"
    zsh "$t" || failed=1
done
exit $failed
```

- [ ] **Step 2: Write the failing test**

`tests/test_transport.zsh`:

```zsh
#!/bin/zsh
source ${0:A:h}/helpers.zsh
COLDPRINT_LIB=1 source ${0:A:h}/../coldprint

assert_eq "ippusb is usb" \
    "usb" "$(classify_transport 'ippusb://Example%20Laser%201000._ipp._tcp.local./?uuid=00000000-aaaa')"
assert_eq "legacy usb scheme" \
    "usb" "$(classify_transport 'usb://Example/Laser-1000')"
assert_eq "explicit ipps is encrypted" \
    "ipps" "$(classify_transport 'ipps://PRN000000000000.local.:631/ipp/print')"
assert_eq "dnssd advertising _ipps is encrypted" \
    "ipps" "$(classify_transport 'dnssd://Example%20Laser%202000._ipps._tcp.local./?uuid=00000000-bbbb')"
assert_eq "dnssd advertising _ipp is cleartext" \
    "cleartext" "$(classify_transport 'dnssd://Example(R)%20Inkjet%20500._ipp._tcp.local./?uuid=00000000-cccc')"
assert_eq "plain ipp is cleartext" \
    "cleartext" "$(classify_transport 'ipp://PRN000000000000.local.:631/ipp/print')"
assert_eq "socket is cleartext" \
    "cleartext" "$(classify_transport 'socket://192.168.1.50:9100')"
assert_eq "lpd is cleartext" \
    "cleartext" "$(classify_transport 'lpd://192.168.1.50/queue')"
assert_eq "http is cleartext" \
    "cleartext" "$(classify_transport 'http://192.168.1.50:631/printers/x')"
assert_eq "unrecognised is unknown" \
    "unknown" "$(classify_transport 'weirdproto://somewhere')"

finish
```

- [ ] **Step 3: Run it to make sure it fails**

Run: `zsh tests/test_transport.zsh`
Expected: FAIL — `coldprint` does not exist, so `source` errors.

- [ ] **Step 4: Write the minimal implementation**

`coldprint`:

```zsh
#!/bin/zsh
#
# coldprint — print a secret to paper for a continuity envelope.
#
# NOTE: there is deliberately no `unset HISTFILE` here. A non-interactive zsh
# script writes no history, and values captured by `read` never enter history
# under any circumstance. Unsetting it would imply a protection that does not
# exist. The only history artifact is this script's own invocation, which is
# harmless.

emulate -L zsh
setopt err_return no_unset pipe_fail

readonly OVERRIDE_TOKEN='OVERRIDE'

# classify_transport <device-uri>
# Prints one of: usb | ipps | cleartext | unknown
#
# The URI scheme alone is insufficient: dnssd:// URIs are cleartext or TLS
# depending on the advertised service type embedded in the URI. _ipps must be
# tested before _ipp.
classify_transport() {
    local uri="$1"
    case "$uri" in
        (ippusb://*|usb://*)      print -r -- "usb" ;;
        (ipps://*)                print -r -- "ipps" ;;
        (dnssd://*_ipps._tcp*)    print -r -- "ipps" ;;
        (dnssd://*_ipp._tcp*)     print -r -- "cleartext" ;;
        (ipp://*|http://*|https://*|socket://*|lpd://*|smb://*)
                                  print -r -- "cleartext" ;;
        (*)                       print -r -- "unknown" ;;
    esac
}

main() {
    print -r -- "not yet implemented" >&2
    return 1
}

[[ -n "${COLDPRINT_LIB:-}" ]] || main "$@"
```

- [ ] **Step 5: Run the tests and make sure they pass**

Run: `chmod +x coldprint tests/*.zsh && zsh tests/test_transport.zsh`
Expected: `10 run, 0 failed`

- [ ] **Step 6: Commit**

```bash
git add coldprint tests/
git commit -m "Add test harness and print transport classifier"
```

---

### Task 2: Backup gate

**Files:**
- Modify: `coldprint`
- Create: `tests/test_backup_gate.zsh`

**Interfaces:**
- Consumes: nothing from Task 1 beyond the sourcing guard.
- Produces: `detect_backup_agents()` prints one human-readable line per live item to stdout, empty output when clear. `backup_banner()` prints the unconditional Tier 1 warning to stderr. `backup_gate()` runs both and returns 0 to proceed, 2 to abort.
- Overridable seams for testing: `detect_backup_agents` reads Time Machine state through `_tm_autobackup()` and `_tm_running()`, and scans processes through `_pgrep_agent(pattern)`. Tests redefine those three.

- [ ] **Step 1: Write the failing test**

`tests/test_backup_gate.zsh`:

```zsh
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

finish
```

- [ ] **Step 2: Run it to verify it fails**

Run: `zsh tests/test_backup_gate.zsh`
Expected: FAIL — `detect_backup_agents: command not found`

- [ ] **Step 3: Write the implementation**

Insert into `coldprint` above `main()`:

```zsh
# Full-disk backup agents. Deliberately excludes `backupd`: it is a resident
# daemon on macOS 26 and would trip the gate on every run, training the user to
# reflex-type the override. Time Machine is covered by _tm_autobackup/_tm_running.
#
# Deliberately excludes file-sync daemons (bird/iCloud, Dropbox, Google Drive):
# `bird` runs permanently, and these sync the home directory only — the secret
# never lands there. They are named in the Tier 1 banner instead.
#
# pgrep -f (full command line) is required, not -x: ChronoSync's process is
# named "ChronoSync Scheduler" and -x misses it.
typeset -ga BACKUP_AGENT_PATTERNS=(
    bztransmit bzbkup bzserv
    Arq ccc_helper SuperDuper ChronoSync
    restic borg duplicati
)

_tm_autobackup() {
    defaults read /Library/Preferences/com.apple.TimeMachine.plist AutoBackup 2>/dev/null || true
}

_tm_running() {
    tmutil status 2>/dev/null | awk -F'=' '/Running/ { gsub(/[^0-9]/, "", $2); print $2; exit }' || true
}

_pgrep_agent() {
    pgrep -qf "$1" 2>/dev/null
}

# detect_backup_agents
# Prints one line per live backup mechanism. Empty output means clear.
detect_backup_agents() {
    local -a live
    local p

    [[ "$(_tm_autobackup)" == "1" ]] && \
        live+=("Time Machine: AutoBackup is enabled (can start mid-print)")
    [[ "$(_tm_running)" == "1" ]] && \
        live+=("Time Machine: a backup is in progress")

    for p in $BACKUP_AGENT_PATTERNS; do
        _pgrep_agent "$p" && live+=("Process: $p")
    done

    (( ${#live} )) && print -rl -- $live
    return 0
}

# backup_banner — Tier 1. Unconditional, every run, regardless of detection.
backup_banner() {
    print -r -- "" >&2
    print -r -- "  Pause all automatic backup, sync, and snapshot software before continuing." >&2
    print -r -- "  Time Machine - Backblaze - Arq - Carbon Copy Cloner - ChronoSync -" >&2
    print -r -- "  Dropbox - iCloud Drive - restic - borg - or anything else you run." >&2
    print -r -- "" >&2
    print -r -- "  While the job prints, it exists in cleartext in /var/spool/cups." >&2
    print -r -- "" >&2
}

# backup_gate — Tier 2. Returns 0 to proceed, 2 to abort.
backup_gate() {
    local -a live
    local reply
    live=( ${(f)"$(detect_backup_agents)"} )

    (( ${#live} )) || return 0

    print -r -- "  BLOCKED. These are live right now:" >&2
    print -rl -- "    ${^live}" >&2
    print -r -- "" >&2
    print -r -- "  Stop them, or type ${OVERRIDE_TOKEN} to print anyway." >&2
    printf '  > ' >&2
    IFS= read -r reply || return 2

    [[ "$reply" == "$OVERRIDE_TOKEN" ]] || { print -r -- "  Aborted." >&2; return 2 }
    print -r -- "  Overridden." >&2
    return 0
}
```

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `zsh tests/test_backup_gate.zsh`
Expected: `7 run, 0 failed`

- [ ] **Step 5: Verify against real system state**

Run: `COLDPRINT_LIB=1 zsh -c 'source ./coldprint; detect_backup_agents'`
Expected: one line per backup mechanism actually live on the test machine, naming each. Crucially it must NOT list anything relating to `backupd`, which is always resident.

- [ ] **Step 6: Commit**

```bash
git add coldprint tests/test_backup_gate.zsh
git commit -m "Add two-tier backup gate with unconditional banner"
```

---

### Task 3: Printer enumeration and selection

**Files:**
- Modify: `coldprint`
- Modify: `tests/test_transport.zsh`

**Interfaces:**
- Consumes: `classify_transport` from Task 1, `OVERRIDE_TOKEN`.
- Produces: `enumerate_printers()` prints `name<TAB>transport` per queue, safe transports (`usb`, `ipps`) first. `select_printer(preselected_name)` prints the chosen queue name to stdout, returns 0 on success and 3 on refusal.
- Overridable seam: `enumerate_printers` reads queues through `_lpstat_v()`, which tests redefine.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_transport.zsh`, before the `finish` line:

```zsh
_lpstat_v() {
    cat <<'FIXTURE'
device for Laser_1000_usb: ippusb://Example%20Laser%201000._ipp._tcp.local./?uuid=00000000-aaaa
device for Laser_1000_legacy: ipp://PRN000000000000.local.:631/ipp/print
device for Laser_2000_tls: dnssd://Example%20Laser%202000._ipps._tcp.local./?uuid=00000000-bbbb
device for Inkjet_500_legacy: dnssd://Example(R)%20Inkjet%20500._ipp._tcp.local./?uuid=00000000-cccc
FIXTURE
}

assert_eq "safe transports sort first, cleartext last" \
"Laser_1000_usb	usb
Laser_2000_tls	ipps
Laser_1000_legacy	cleartext
Inkjet_500_legacy	cleartext" \
    "$(enumerate_printers)"

_lpstat_v() { return 1 }
assert_eq "no printers yields empty output" "" "$(enumerate_printers)"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `zsh tests/test_transport.zsh`
Expected: FAIL — `enumerate_printers: command not found`

- [ ] **Step 3: Write the implementation**

Insert into `coldprint` above `main()`:

```zsh
_lpstat_v() { lpstat -v 2>/dev/null }

# enumerate_printers
# Prints "name<TAB>transport", safe transports first.
enumerate_printers() {
    local line name uri t
    local -a safe unsafe
    while IFS= read -r line; do
        [[ "$line" == device\ for\ * ]] || continue
        name="${${line#device for }%%:*}"
        uri="${line#*: }"
        t="$(classify_transport "$uri")"
        case "$t" in
            (usb|ipps)  safe+=("$name	$t") ;;
            (*)         unsafe+=("$name	$t") ;;
        esac
    done < <(_lpstat_v)
    (( ${#safe} ))   && print -rl -- $safe
    (( ${#unsafe} )) && print -rl -- $unsafe
    return 0
}

# select_printer [preselected-name]
# Prints the chosen queue name. Returns 3 if the user refuses.
select_printer() {
    local preselect="${1:-}"
    local -a rows
    local row name t choice reply i

    rows=( ${(f)"$(enumerate_printers)"} )
    (( ${#rows} )) || { print -r -- "No print queues found." >&2; return 3 }

    if [[ -n "$preselect" ]]; then
        for row in $rows; do
            [[ "${row%%	*}" == "$preselect" ]] || continue
            t="${row##*	}"
            _confirm_transport "$preselect" "$t" || return 3
            print -r -- "$preselect"
            return 0
        done
        print -r -- "No such print queue: $preselect" >&2
        return 3
    fi

    print -r -- "" >&2
    print -r -- "  Select printer:" >&2
    for (( i = 1; i <= ${#rows}; i++ )); do
        name="${rows[i]%%	*}"
        t="${rows[i]##*	}"
        case "$t" in
            (usb)  printf '    %d) %-30s usb          no network exposure\n' $i "$name" >&2 ;;
            (ipps) printf '    %d) %-30s ipps / TLS   encrypted in transit\n' $i "$name" >&2 ;;
            (*)    printf '    %d) %-30s %-12s CLEARTEXT\n' $i "$name" "$t" >&2 ;;
        esac
    done
    printf '  > ' >&2
    IFS= read -r choice || return 3

    [[ "$choice" == <-> ]] && (( choice >= 1 && choice <= ${#rows} )) || {
        print -r -- "  Invalid selection." >&2; return 3
    }

    name="${rows[choice]%%	*}"
    t="${rows[choice]##*	}"
    _confirm_transport "$name" "$t" || return 3
    print -r -- "$name"
    return 0
}

# _confirm_transport <name> <transport>
# Safe transports pass silently. Cleartext and unknown require the override
# token — the same friction as the backup gate, so there is one mental model.
_confirm_transport() {
    local name="$1" t="$2" reply
    case "$t" in
        (usb|ipps) return 0 ;;
    esac
    print -r -- "" >&2
    print -r -- "  $name uses a $t transport. The secret would cross the network unencrypted." >&2
    print -r -- "  Type ${OVERRIDE_TOKEN} to use it anyway." >&2
    printf '  > ' >&2
    IFS= read -r reply || return 1
    [[ "$reply" == "$OVERRIDE_TOKEN" ]]
}
```

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `zsh tests/test_transport.zsh`
Expected: `12 run, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add coldprint tests/test_transport.zsh
git commit -m "Add printer enumeration and transport-gated selection"
```

---

### Task 4: Secret capture

**Files:**
- Modify: `coldprint`
- Create: `tests/test_capture.zsh`

**Interfaces:**
- Consumes: nothing.
- Produces: `read_secret_lines()` reads from stdin until a blank line or EOF, prints captured lines to stdout, per-line progress to stderr. `flag_characters(lines...)` prints one warning line per issue found.

- [ ] **Step 1: Write the failing test**

`tests/test_capture.zsh`:

```zsh
#!/bin/zsh
source ${0:A:h}/helpers.zsh
COLDPRINT_LIB=1 source ${0:A:h}/../coldprint

assert_eq "blank line terminates capture" \
    "alpha
beta" \
    "$(printf 'alpha\nbeta\n\ntrailing-ignored\n' | read_secret_lines 2>/dev/null)"

assert_eq "EOF terminates capture without a blank line" \
    "alpha
beta" \
    "$(printf 'alpha\nbeta\n' | read_secret_lines 2>/dev/null)"

assert_eq "single line works" \
    "hunter2" "$(printf 'hunter2\n' | read_secret_lines 2>/dev/null)"

assert_eq "immediate blank yields nothing" \
    "" "$(printf '\n' | read_secret_lines 2>/dev/null)"

assert_eq "internal spaces are preserved" \
    "correct horse battery staple" \
    "$(printf 'correct horse battery staple\n' | read_secret_lines 2>/dev/null)"

assert_eq "backslashes are preserved literally" \
    'a\b\\c' "$(printf 'a\\b\\\\c\n' | read_secret_lines 2>/dev/null)"

assert_eq "progress goes to stderr, one line per capture" \
    "  . line 1 captured (5 chars)
  . line 2 captured (3 chars)" \
    "$(printf 'alpha\nbet\n' | read_secret_lines 2>&1 >/dev/null)"

# Character flagging.
assert_eq "trailing space is flagged, not stripped" \
    "line 1 has trailing whitespace (preserved as-is)" \
    "$(flag_characters 'secret ')"

assert_eq "tab is flagged" \
    "line 1 contains a tab" \
    "$(flag_characters $'a\tb')"

assert_eq "non-ascii is flagged as a layout risk" \
    "line 1 contains non-ASCII (prints correctly, but widens the layout)" \
    "$(flag_characters 'café')"

assert_eq "clean lines produce no warnings" \
    "" "$(flag_characters 'abc123' 'def456')"

finish
```

- [ ] **Step 2: Run it to verify it fails**

Run: `zsh tests/test_capture.zsh`
Expected: FAIL — `read_secret_lines: command not found`

- [ ] **Step 3: Write the implementation**

Insert into `coldprint` above `main()`:

```zsh
# read_secret_lines
# Reads from stdin until a blank line or EOF. Captured lines go to stdout,
# progress to stderr.
#
# Echo is suppressed with stty rather than `read -s` so that a single restore
# path covers the whole loop, and bracketed paste is explicitly disabled: if the
# terminal has it armed, a paste arrives wrapped in ESC[200~ / ESC[201~ and
# those bytes would land silently inside the secret.
read_secret_lines() {
    local -a lines
    local line saved="" n=0
    local interactive=0
    [[ -t 0 ]] && interactive=1

    if (( interactive )); then
        saved="$(stty -g)"
        # Restore on any exit path, including Ctrl-C mid-secret.
        trap 'stty "$saved" 2>/dev/null; printf "\033[?2004h" >&2' EXIT INT TERM
        printf '\033[?2004l' >&2
        stty -echo
    fi

    while IFS= read -r line; do
        [[ -z "$line" ]] && break
        lines+=("$line")
        (( n++ ))
        printf '  . line %d captured (%d chars)\n' $n ${#line} >&2
    done

    if (( interactive )); then
        stty "$saved"
        printf '\033[?2004h' >&2
        trap - EXIT INT TERM
        print -r -- "" >&2
    fi

    (( ${#lines} )) && print -rl -- $lines
    return 0
}

# flag_characters <line>...
# Prints one warning per issue. Nothing is ever stripped: a trailing space can
# be legitimate in a passphrase, and silently mutating a secret is worse than
# an ugly one.
flag_characters() {
    local -a warn
    local l i=0
    for l in "$@"; do
        (( i++ ))
        [[ "$l" == *[[:space:]] ]] && \
            warn+=("line $i has trailing whitespace (preserved as-is)")
        [[ "$l" == *$'\t'* ]] && \
            warn+=("line $i contains a tab")
        [[ "$l" == *[^[:ascii:]]* ]] && \
            warn+=("line $i contains non-ASCII (prints correctly, but widens the layout)")
    done
    (( ${#warn} )) && print -rl -- $warn
    return 0
}
```

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `zsh tests/test_capture.zsh`
Expected: `11 run, 0 failed`

- [ ] **Step 5: Manually verify echo suppression and paste safety**

Run: `COLDPRINT_LIB=1 zsh -c 'source ./coldprint; read_secret_lines > /tmp/cap.txt'`
Paste three lines, press Enter on a blank line.
Expected: nothing echoes while typing; progress lines appear; `/tmp/cap.txt` contains exactly three lines with no `ESC[200~` bytes. Verify with `cat -v /tmp/cap.txt`, then `rm /tmp/cap.txt`.

Run again and press Ctrl-C partway through.
Expected: the terminal still echoes afterwards. If it does not, the trap is wrong.

- [ ] **Step 6: Commit**

```bash
git add coldprint tests/test_capture.zsh
git commit -m "Add bracketed-paste-safe multi-line secret capture"
```

---

### Task 5: Preview masking

**Files:**
- Modify: `coldprint`
- Create: `tests/test_mask.zsh`

**Interfaces:**
- Consumes: nothing.
- Produces: `mask_line(text)` prints the masked form. `render_preview(label, lines...)` prints the full preview block to stderr.

- [ ] **Step 1: Write the failing test**

`tests/test_mask.zsh`:

```zsh
#!/bin/zsh
source ${0:A:h}/helpers.zsh
COLDPRINT_LIB=1 source ${0:A:h}/../coldprint

assert_eq "long line shows first two and last two" \
    "hu••••••••r2" "$(mask_line 'hunter2hunter2')"
assert_eq "six chars is the shortest partially-revealed case" \
    "ab••ef" "$(mask_line 'abcdef')"
assert_eq "five chars is fully masked" \
    "•••••" "$(mask_line 'abcde')"
assert_eq "one char is fully masked" \
    "•" "$(mask_line 'a')"
assert_eq "empty stays empty" "" "$(mask_line '')"

assert_eq "preview reports structure and totals" \
"Label:  Test codes
Lines:  2

  [ 1] ab••ef        (6 chars)
  [ 2] gh••••mn      (8 chars)

  Total: 2 lines, 14 chars" \
    "$(render_preview 'Test codes' 'abcdef' 'ghijklmn' 2>&1)"

assert_eq "single-line preview totals correctly" \
"Label:  One
Lines:  1

  [ 1] hu••••••••r2  (14 chars)

  Total: 1 line, 14 chars" \
    "$(render_preview 'One' 'hunter2hunter2' 2>&1)"

finish
```

- [ ] **Step 2: Run it to verify it fails**

Run: `zsh tests/test_mask.zsh`
Expected: FAIL — `mask_line: command not found`

- [ ] **Step 3: Write the implementation**

Insert into `coldprint` above `main()`:

```zsh
# mask_line <text>
# Lines of 5 characters or fewer are fully masked: revealing two at each end of
# a 5-character secret would expose 80% of it.
mask_line() {
    local s="$1"
    local -i n=${#s}
    local dots=""

    (( n == 0 )) && return 0
    if (( n <= 5 )); then
        repeat $n; do dots+="•"; done
        print -r -- "$dots"
        return 0
    fi
    repeat $(( n - 4 )); do dots+="•"; done
    print -r -- "${s[1,2]}${dots}${s[-2,-1]}"
}

# render_preview <label> <line>...
# Character counts are per-line content only and exclude line terminators, so
# the total differs from the checksum input length by the number of newlines.
render_preview() {
    local label="$1"; shift
    local -i i=0 total=0
    local l noun

    print -r -- "Label:  $label" >&2
    print -r -- "Lines:  $#" >&2
    print -r -- "" >&2
    for l in "$@"; do
        (( i++ ))
        (( total += ${#l} ))
        printf '  [%2d] %-14s(%d chars)\n' $i "$(mask_line "$l")" ${#l} >&2
    done
    print -r -- "" >&2
    noun="lines"; (( $# == 1 )) && noun="line"
    print -r -- "  Total: $# $noun, $total chars" >&2
    return 0
}
```

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `zsh tests/test_mask.zsh`
Expected: `7 run, 0 failed`

Note: `printf '%-14s'` pads by bytes, and `•` is 3 bytes in UTF-8, so the column will not visually align for masked output. If the assertion fails on spacing, fix by padding on character count rather than with `%-14s` — compute `local pad=$(( 14 - ${#masked} ))` and emit that many spaces. Do not change the expected values; the test encodes the intended visual result.

- [ ] **Step 5: Commit**

```bash
git add coldprint tests/test_mask.zsh
git commit -m "Add masked-edge secret preview"
```

---

### Task 6: Page builder

**Files:**
- Modify: `coldprint`
- Create: `tests/test_build_page.zsh`

**Interfaces:**
- Consumes: nothing.
- Produces: `select_cpi(widest, gutter)` prints `"<cpi> <total_chars>"`, returns 0 if it fits and 1 if wrapping is needed. `build_page(label, date, total_chars)` reads secret lines from stdin and prints the page text to stdout.

- [ ] **Step 1: Write the failing test**

`tests/test_build_page.zsh`:

```zsh
#!/bin/zsh
source ${0:A:h}/helpers.zsh
COLDPRINT_LIB=1 source ${0:A:h}/../coldprint

# --- cpi selection -------------------------------------------------------
assert_eq "short line takes the largest glyphs" "10 70" "$(select_cpi 20 6)"
assert_eq "exactly at the cpi=10 numbered budget" "10 70" "$(select_cpi 64 6)"
assert_eq "one over cpi=10 steps to cpi=12" "12 84" "$(select_cpi 65 6)"
assert_eq "unnumbered gets the full width at cpi=10" "10 70" "$(select_cpi 70 0)"
assert_eq "wide line lands on cpi=15" "15 105" "$(select_cpi 99 6)"
assert_eq "very wide line lands on cpi=17" "17 119" "$(select_cpi 113 6)"
select_cpi 200 6 >/dev/null; assert_status "over-budget signals wrapping" 1 $?
select_cpi 20 6  >/dev/null; assert_status "in-budget signals no wrapping" 0 $?

# --- page layout ---------------------------------------------------------
# Checksum is sha256 over the LF-joined lines with no trailing newline.
SUM_MULTI="$(printf '%s' 'aaa
bbb' | shasum -a 256 | cut -c1-8)"

assert_eq "multi-line page is numbered and carries metadata" \
"My codes
--------------------------------------------------
2026-08-21 21:45

   1  aaa
   2  bbb

sha256/8: ${SUM_MULTI}  (LF-joined, no trailing NL)
0=zero  O=oh  1=one  l=ell  I=eye" \
    "$(printf 'aaa\nbbb\n' | build_page 'My codes' '2026-08-21 21:45' 70)"

SUM_ONE="$(printf '%s' 'hunter2' | shasum -a 256 | cut -c1-8)"
assert_eq "single-line page omits the number gutter" \
"My pass
--------------------------------------------------
2026-08-21 21:45

hunter2

sha256/8: ${SUM_ONE}  (LF-joined, no trailing NL)
0=zero  O=oh  1=one  l=ell  I=eye" \
    "$(printf 'hunter2\n' | build_page 'My pass' '2026-08-21 21:45' 70)"

# Wrapping uses the gutter, never an in-band marker, so no character is ever
# appended to the secret's own text.
SUM_WRAP="$(printf '%s' 'ABCDEFGHIJKLMNO
short' | shasum -a 256 | cut -c1-8)"
assert_eq "over-width line wraps into the gutter" \
"W
--------------------------------------------------
2026-08-21 21:45

   1  ABCDEFGHIJ
 ...  KLMNO
   2  short

sha256/8: ${SUM_WRAP}  (LF-joined, no trailing NL)
0=zero  O=oh  1=one  l=ell  I=eye" \
    "$(printf 'ABCDEFGHIJKLMNO\nshort\n' | build_page 'W' '2026-08-21 21:45' 16)"

# The rule never runs past the printable width.
assert_eq "rule is clamped to the character budget" \
    "20" \
    "$(printf 'x\n' | build_page 'Lbl' '2026-08-21 21:45' 20 | sed -n 2p | tr -d '\n' | wc -c | tr -d ' ')"

# A label longer than 50 widens the rule to match.
assert_eq "rule matches an over-long label" \
    "60" \
    "$(printf 'x\n' | build_page "$(printf 'L%.0s' {1..60})" '2026-08-21 21:45' 70 | sed -n 2p | tr -d '\n' | wc -c | tr -d ' ')"

finish
```

- [ ] **Step 2: Run it to verify it fails**

Run: `zsh tests/test_build_page.zsh`
Expected: FAIL — `select_cpi: command not found`

- [ ] **Step 3: Write the implementation**

Insert into `coldprint` above `main()`:

```zsh
# Usable width is 612pt - 54pt - 54pt = 504pt; a character is 72/cpi points.
# Verified empirically: a 10-character string measures 72.01pt at cpi=10 and
# 60.01pt at cpi=12.
typeset -ga CPI_LADDER=(10 12 15 17)
typeset -ga CPI_CHARS=(70 84 105 119)

# select_cpi <widest-line> <gutter>
# Prints "<cpi> <total_chars>". Returns 1 when even the densest step cannot fit
# the line, meaning build_page will wrap it.
select_cpi() {
    local -i widest=$1 gutter=$2 i
    for (( i = 1; i <= ${#CPI_LADDER}; i++ )); do
        if (( CPI_CHARS[i] - gutter >= widest )); then
            print -r -- "${CPI_LADDER[i]} ${CPI_CHARS[i]}"
            return 0
        fi
    done
    print -r -- "${CPI_LADDER[-1]} ${CPI_CHARS[-1]}"
    return 1
}

# build_page <label> <date> <total-chars>
# Reads secret lines from stdin, prints the page. Pure: no globals beyond the
# cpi tables, no side effects.
build_page() {
    local label="$1" date="$2"
    local -i total=$3
    local -a lines
    local l seg rule=""
    local -i n numbered gutter budget i rule_w first

    while IFS= read -r l; do lines+=("$l"); done
    n=${#lines}

    numbered=0; (( n > 1 )) && numbered=1
    gutter=0;   (( numbered )) && gutter=6
    budget=$(( total - gutter ))

    local joined="${(pj:\n:)lines}"
    local sum="$(printf '%s' "$joined" | shasum -a 256 | cut -c1-8)"

    rule_w=${#label}
    (( rule_w < 50 )) && rule_w=50
    (( rule_w > total )) && rule_w=$total
    repeat $rule_w; do rule+="-"; done

    print -r -- "$label"
    print -r -- "$rule"
    print -r -- "$date"
    print -r -- ""

    i=0
    for l in "${lines[@]}"; do
        (( i++ ))
        first=1
        while :; do
            seg="${l[1,$budget]}"
            l="${l[$(( budget + 1 )),-1]}"
            if (( numbered )); then
                if (( first )); then
                    printf '%4d  %s\n' $i "$seg"
                else
                    printf '%4s  %s\n' '...' "$seg"
                fi
            else
                printf '%s\n' "$seg"
            fi
            first=0
            [[ -z "$l" ]] && break
        done
    done

    print -r -- ""
    print -r -- "sha256/8: ${sum}  (LF-joined, no trailing NL)"
    print -r -- "0=zero  O=oh  1=one  l=ell  I=eye"
    return 0
}
```

- [ ] **Step 4: Run the tests and make sure they pass**

Run: `zsh tests/test_build_page.zsh`
Expected: `13 run, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add coldprint tests/test_build_page.zsh
git commit -m "Add page builder with cpi ladder and gutter wrapping"
```

---

### Task 7: Submission, dry-run, and CLI

**Files:**
- Modify: `coldprint`

**Interfaces:**
- Consumes: every function from Tasks 1-6.
- Produces: a working `coldprint` with `-P NAME`, `-n COPIES`, `--dry-run`, `-h`.

- [ ] **Step 1: Write the print options, submission, and cleanup**

Insert into `coldprint` above `main()`:

```zsh
# lp_options <cpi>
# sides=one-sided is mandatory, not cosmetic: the queue default is
# *DuplexNoTumble, which would print copy 2 on the reverse of copy 1 and
# silently defeat the purpose of making two copies for two locations.
lp_options() {
    print -r -- "-o" "cpi=$1" "-o" "lpi=6" \
                "-o" "page-left=54" "-o" "page-right=54" \
                "-o" "page-top=54" "-o" "page-bottom=54" \
                "-o" "sides=one-sided"
}

# purge_completed_jobs <printer>
# Scoped to one queue, and skipped entirely if anything is still queued, so the
# script can never cancel an unrelated print.
purge_completed_jobs() {
    local printer="$1" pending
    pending="$(lpstat -o "$printer" 2>/dev/null)"
    if [[ -n "$pending" ]]; then
        print -r -- "  Jobs still queued on $printer; skipping history purge." >&2
        return 0
    fi
    cancel -x "$printer" 2>/dev/null || true
    print -r -- "  Purged completed job history for $printer." >&2
    return 0
}

# Sample content for --dry-run. Deliberately fixed: a dry-run that accepted a
# real secret would write it in plaintext to a PDF on disk, which is precisely
# what this script exists to prevent, reachable by one wrong flag.
dry_run_sample() {
    cat <<'SAMPLE'
4fh2n8-xk3m2c
9ap7q1-w4rte1
m2x8v0-qq5nb7
t7yc44-hd91zs
b3kk09-rr2wme
z0p1la-6tn4xu
e5w7dd-oi3gvk
s8n2mq-1cf6ry
g4bt73-xz0jpe
ILlO0o1i-ambiguity-sampler
SAMPLE
}

do_dry_run() {
    local out="${TMPDIR:-/tmp}/coldprint_dryrun_$$.pdf"
    local -a lines opts
    local l
    local -i widest=0

    lines=( ${(f)"$(dry_run_sample)"} )
    for l in $lines; do (( ${#l} > widest )) && widest=${#l}; done

    local cpi total
    read -r cpi total <<< "$(select_cpi $widest 6)"
    opts=( ${(f)"$(lp_options $cpi)"} )

    print -rl -- $lines \
        | build_page 'Dry run sample' "$(date '+%Y-%m-%d %H:%M')" $total \
        | cupsfilter -m application/pdf $opts - > "$out" 2>/dev/null

    print -r -- "Dry run written to: $out" >&2
    print -r -- "(sample content only; no secret was requested)" >&2
    return 0
}

usage() {
    cat >&2 <<'USAGE'
coldprint — print a secret to paper for a continuity envelope.

  coldprint [-P PRINTER] [-n COPIES]
  coldprint --dry-run
  coldprint -h

  -P PRINTER   Use this queue, skipping the selection menu.
  -n COPIES    Number of copies (default 1). Always one-sided.
  --dry-run    Render sample content to a PDF and exit. Never asks for a secret.
  -h           This help.

Pause all backup, sync, and snapshot software before use.
USAGE
}
```

- [ ] **Step 2: Replace the placeholder `main`**

```zsh
main() {
    local printer="" label=""
    local -i copies=1
    local -a lines warnings opts
    local l reply cpi total

    while (( $# )); do
        case "$1" in
            (-P) printer="${2:-}"; shift 2 || return 1 ;;
            (-n) copies="${2:-1}"; shift 2 || return 1 ;;
            (--dry-run) do_dry_run; return 0 ;;
            (-h|--help) usage; return 0 ;;
            (*) print -r -- "Unknown argument: $1" >&2; usage; return 1 ;;
        esac
    done

    [[ "$copies" == <-> ]] && (( copies >= 1 )) || {
        print -r -- "Copies must be a positive integer." >&2; return 1
    }
    [[ -t 0 ]] || {
        print -r -- "A terminal is required: the secret is read with echo disabled." >&2
        return 1
    }

    backup_banner
    backup_gate || return 2

    printer="$(select_printer "$printer")" || return 3

    printf 'Label: ' >&2
    IFS= read -r label || return 1
    [[ -n "$label" ]] || { print -r -- "A label is required." >&2; return 1 }

    print -r -- "Secret (blank line or Ctrl-D to finish):" >&2
    lines=( ${(f)"$(read_secret_lines)"} )
    (( ${#lines} )) || { print -r -- "A secret is required." >&2; return 1 }

    print -r -- "" >&2
    render_preview "$label" "${lines[@]}"

    warnings=( ${(f)"$(flag_characters "${lines[@]}")"} )
    if (( ${#warnings} )); then
        print -r -- "" >&2
        print -rl -- "  ! ${^warnings}" >&2
    fi

    local -i widest=0
    for l in "${lines[@]}"; do (( ${#l} > widest )) && widest=${#l}; done
    local -i gutter=0
    (( ${#lines} > 1 )) && gutter=6

    if ! read -r cpi total <<< "$(select_cpi $widest $gutter)"; then :; fi
    read -r cpi total <<< "$(select_cpi $widest $gutter)"
    if ! select_cpi $widest $gutter >/dev/null; then
        print -r -- "" >&2
        print -r -- "  ! Longest line exceeds the page; it will wrap, marked by ... in the number column." >&2
    fi

    print -r -- "" >&2
    printf '  Print %d cop%s to %s? [y/N]: ' $copies "$( (( copies == 1 )) && print -n y || print -n ies )" "$printer" >&2
    IFS= read -r reply || return 0
    [[ "$reply" == [yY] ]] || { print -r -- "  Cancelled." >&2; unset lines label; return 0 }

    opts=( ${(f)"$(lp_options $cpi)"} )
    if ! print -rl -- "${lines[@]}" \
        | build_page "$label" "$(date '+%Y-%m-%d %H:%M')" $total \
        | lp -d "$printer" -n $copies $opts >/dev/null 2>&1
    then
        print -r -- "  Print submission failed." >&2
        unset lines label
        return 4
    fi

    # Drops the references. It does NOT zero the memory — shell cannot do that,
    # and pretending otherwise would be worse than saying so.
    unset lines label

    print -r -- "" >&2
    print -r -- "  Submitted to $printer." >&2
    lpstat -o "$printer" 2>/dev/null >&2 || true

    printf '\n  Press Enter once the page is in your hand... ' >&2
    read -r _ || true

    purge_completed_jobs "$printer"
    clear
    printf '\033[3J'
    return 0
}
```

- [ ] **Step 3: Remove the duplicated `select_cpi` calls in `main`**

The block written in Step 2 calls `select_cpi` three times, which is wasteful and confusing. Replace those seven lines with:

```zsh
    local wrap_needed=0
    read -r cpi total <<< "$(select_cpi $widest $gutter)" || true
    select_cpi $widest $gutter >/dev/null || wrap_needed=1
    if (( wrap_needed )); then
        print -r -- "" >&2
        print -r -- "  ! Longest line exceeds the page; it will wrap, marked by ... in the number column." >&2
    fi
```

- [ ] **Step 4: Run the full test suite**

Run: `zsh tests/run_all.zsh`
Expected: every file reports `0 failed`, overall exit status 0.

- [ ] **Step 5: Verify the dry run end to end**

Run: `./coldprint --dry-run`
Then open the reported path and confirm: Monaco glyphs, slashed zero, numbered lines, rule, date, `sha256/8` footer, glyph legend, one page, nothing clipped at the right edge.

Confirm it never prompted for a secret.

- [ ] **Step 6: Verify the gates refuse correctly**

Run: `./coldprint` with Backblaze running.
Expected: banner, then `BLOCKED` listing the live agents, then a prompt. Type `y` — expected: aborts with exit 2. Run again and type `OVERRIDE` — expected: proceeds to printer selection.

Run: `./coldprint -P Laser_1000_legacy`
Expected: cleartext warning, `OVERRIDE` required.

Run: `./coldprint -P nonexistent`
Expected: error, exit 3.

- [ ] **Step 7: Commit**

```bash
git add coldprint
git commit -m "Add submission, dry-run, cleanup, and CLI"
```

---

### Task 8: README

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: the finished script.
- Produces: user-facing documentation, including the threat-model limits the script cannot enforce.

- [ ] **Step 1: Write the README**

`README.md`:

```markdown
# coldprint

Print a secret — a passphrase, a block of recovery codes — onto paper for a
continuity envelope, without it touching disk, shell history, or an
unencrypted network hop.

    ./coldprint                 # select a printer, enter a secret
    ./coldprint -P NAME -n 2    # named queue, two copies
    ./coldprint --dry-run       # render sample content to a PDF

## What it does for you

- **Refuses to run while backup software is live.** Time Machine (including
  armed-but-idle, which can fire mid-print), Backblaze, Arq, Carbon Copy
  Cloner, ChronoSync, restic, borg, duplicati. Override requires typing
  `OVERRIDE` in full.
- **Refuses cleartext print transports** unless overridden the same way. A
  `dnssd://` queue advertising `_ipp._tcp` is cleartext despite the scheme.
- **Forces one-sided printing.** The queue default is duplex, which would put
  copy 2 on the back of copy 1.
- **Never echoes the secret** and disables bracketed paste, so no
  `ESC[200~` bytes end up inside it.
- **Never writes the secret to disk.** It exists in shell variables and pipes
  only.

## What it cannot do for you

- **`/var/spool/cups`.** While the job prints, it exists there in cleartext.
  This is unavoidable and is the entire reason for the backup gate.
- **Memory.** `unset` drops a reference; it does not zero memory. Shell cannot.
- **Your clipboard.** If you paste from a password manager, the secret is in
  the system clipboard and that is outside this script's reach.
- **Terminal session logging.** If iTerm2's "Automatically log session to
  files" is on, your prompts are being written to disk. Check
  Settings > Profiles > Session. The script clears scrollback but cannot
  un-write a log file.
- **The output tray.** Collect the page.

## Requirements

macOS with zsh. No third-party dependencies — `lp`, `lpstat`, `cancel`,
`cupsfilter`, `shasum`, `defaults`, `tmutil`, `pgrep`, `stty` are all base
system.

## Tests

    zsh tests/run_all.zsh
```

- [ ] **Step 2: Verify the documented commands actually work**

Run each command shown in the README's usage block and confirm it behaves as
described. Run `zsh tests/run_all.zsh` and confirm exit 0.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "Add README with threat-model limits"
```

---

## Self-Review

**Spec coverage.** Every spec section maps to a task: §1 backup gate → Task 2;
§2 printer selection → Tasks 1 and 3; §3 secret input → Task 4; §4 preview →
Task 5; §5 page rendering and the resolved format → Tasks 6 and 7; §6
post-print → Task 7; §7 `--dry-run` → Task 7; "Removed from the original
script" → Task 1's header comment and Task 7's `unset` comment; "Testing" →
the test files across Tasks 1-6.

**Known rough edge, deliberately left in.** Task 7 Step 2 writes a clumsy
triple call to `select_cpi`, and Step 3 immediately replaces it. This is
intentional: `select_cpi` communicates through both stdout and exit status, and
capturing both from a command substitution is the one genuinely awkward corner
of this script. Showing the wrong version first and then the fix is clearer
than presenting the subtle version as though it were obvious.

**Type consistency.** `select_cpi` prints two space-separated fields and is
consumed by `read -r cpi total` in both `main` and `do_dry_run`. `lp_options`
prints one option token per line and is consumed via `${(f)...}` in both.
`enumerate_printers` emits tab-separated `name<TAB>transport`, split with
`%%\t*` and `##*\t` in `select_printer`. `classify_transport` returns exactly
the four strings that `_confirm_transport` and `enumerate_printers` branch on.
