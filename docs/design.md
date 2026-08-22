# coldprint — design

Date: 2026-08-21

## Purpose

Print a secret (passphrase, recovery-code block) onto paper for a continuity
envelope, without the secret touching disk, the clipboard's persistence, shell
history, or an unencrypted network hop.

The reader of the printed page is the author. Pages are terse and dense, not
explanatory.

## Prior art (why we're building this)

Surveyed and rejected:

- **paperkey** — OpenPGP-specific; strips public-key material from a private
  key. Does not apply to passphrases or recovery codes.
- **paperback** — Shamir-shards an encrypted backup across sheets. Far heavier
  ceremony than this use case.
- **offkey** — encrypted QR codes; recovery needs a phone and a key, defeating
  "open envelope, read page".
- **txt4print** — nearest match (disambiguating font, per-line CRC, SHA256
  header) but Linux-only, unmaintained, **file in / PDF on disk out** — both
  fatal here.

None provide the operational hygiene that is the actual point. We keep the
ideas (character disambiguation, checksum, page metadata) and discard the
implementations.

## Threat model

In scope:

- Secret persisting on disk where a backup agent can capture it.
- Secret crossing the network in cleartext.
- Secret remaining in terminal scrollback after the run.
- A printed page that is *wrong* — mistyped, truncated, or misread years later.

Out of scope (documented, not enforced):

- Memory forensics. Shell cannot zero a variable; we will not pretend it can.
- Clipboard persistence in the password manager the secret is pasted from.
- Terminal application session logging (iTerm2 "log to file"). Noted in README.
- Physical security of the printer output tray.

**The one unavoidable disk exposure:** CUPS writes the job to `/var/spool/cups`
in cleartext for the duration of printing. A stock macOS `cupsd.conf` sets no
`Preserve*` directives, so the `PreserveJobFiles No` default applies and the file is unlinked on
completion — but unlinked is not erased on APFS, and a snapshot or backup
firing during that window captures it. This is why the backup gate exists and
why it is a gate rather than a hint.

## Components

### 1. Backup gate

Two tiers, in this order, before any prompt.

**Tier 1 — unconditional banner.** Runs every time regardless of detection
results. Generic by category, since Time Machine and Backblaze are not the only
offenders:

    Pause all automatic backup, sync, and snapshot software before continuing.
    Time Machine, Backblaze, Arq, Carbon Copy Cloner, Dropbox, restic, etc.
    The print job is written to /var/spool/cups in cleartext while it prints.

**Tier 2 — detection and hard gate.** All checks are sudo-free:

| Check | Command | Trips when |
|---|---|---|
| Time Machine armed | `defaults read /Library/Preferences/com.apple.TimeMachine.plist AutoBackup` | `1` |
| Time Machine running | `tmutil status` | `Running = 1` |
| Backup agents | `pgrep -f` over a pattern list | any match |

Agent pattern list: `bztransmit`, `bzbkup`, `bzserv`, `backupd`, `Arq`,
`ccc_helper`, `SuperDuper`, `restic`, `borg`, `duplicati`, `ChronoSync`.

"Armed but idle" must trip the gate. Time Machine with `AutoBackup=1` can fire
mid-print; only checking `Running` would miss it.

On any trip: print each live item by name, then require the literal string
`OVERRIDE` to continue. Not `y` — the override must be un-muscle-memoriable.
Anything else exits non-zero.

**Deliberate exclusion:** file-sync daemons (`bird`/iCloud Drive, Dropbox,
Google Drive) are *not* gated on. `bird` runs permanently on macOS and would
block every run, and these sync the home directory only — the secret never
lands there. They appear in the Tier 1 banner, where the judgment is the user's.

### 2. Printer selection

Enumerate with `lpstat -v`. Classify transport from **both** the URI scheme and,
for `dnssd://` URIs, the embedded service type — `dnssd://…_ipp._tcp…` is
cleartext IPP despite the scheme.

| Transport | Classification |
|---|---|
| `ippusb://` | `usb` — no network exposure |
| `ipps://`, `dnssd://…_ipps._tcp…` | `ipps / TLS` — encrypted in transit |
| `ipp://`, `dnssd://…_ipp._tcp…`, `http://`, `socket://`, `lpd://` | `CLEARTEXT` |
| anything else | `UNKNOWN` — treated as cleartext |

Present a numbered menu, safe transports first, cleartext below a rule and
labelled. Selecting a cleartext or unknown queue requires typing `OVERRIDE`,
matching the backup gate's friction so there is one mental model, not two.

`-P NAME` skips the menu. No remembered-choice config file — that is disk state
purchased for a keystroke.

### 3. Secret input

One loop, echo suppressed, terminated by **a blank line or Ctrl-D**. Handles a
pasted burst and hand-typed lines identically.

- **Bracketed paste is explicitly disabled** (`ESC[?2004l`) for the duration of
  capture and restored (`ESC[?2004h`) after. If the terminal has it armed, a
  paste arrives wrapped in `ESC[200~` / `ESC[201~` and those bytes land silently
  inside the secret. This is the single highest-risk correctness bug in the
  feature.
- **Captured lines are additionally stripped of `ESC[200~` / `ESC[201~`**, and
  a warning is printed when any is found. Added during implementation after
  confirming the failure empirically: disabling only helps if the terminal
  obeys, and tmux re-arms bracketed paste regardless. Verified that a wrapped
  payload otherwise reaches the secret as `ESC[200~code-one` /
  `code-two ESC[201~`. These bytes are never legitimate secret content, and a
  silently corrupted secret on paper cannot be recovered — so stripping is
  correct despite the general rule against mutating input.
- Per-line feedback (`· line 3 captured (14 chars)`) so hand-typing is not dead
  air. Harmless during a paste burst.
- Tabs, non-ASCII, and trailing whitespace are **flagged, never stripped** — a
  trailing space can be legitimate in a passphrase, and silent mutation of a
  secret is worse than an ugly one. Non-ASCII is a layout warning, not a
  legibility one: it prints correctly but invalidates the cpi width table (§5).
- Label is a separate single-line prompt, echoed normally.
- Empty label or empty secret is an error.

### 4. Preview

Masked edges plus structure. Full plaintext never reaches the screen.

    Label:  Fastmail recovery codes
    Lines:  10

      [ 1] 4f••••••2c    (10 chars)
      [ 2] 9a••••••e1    (10 chars)
      ...
      Total: 10 lines, 104 chars

Lines of **5 characters or fewer are fully masked** — revealing first-two and
last-two of a 5-character secret exposes 80% of it.

Character counts are per-line content only and exclude line terminators; the
total is the sum of those, so it will differ from the checksum input length by
the number of joining newlines.

Warnings for flagged characters appear here, before the print confirmation.

### 5. Page rendering

Layout:

    Fastmail recovery codes
    ───────────────────────
    2026-08-21 21:45

      1  4fh2n8-xk3m2c
      2  9ap7q1-w4rte1
      ...

    sha256/8: 3f9a2c1e (LF-joined, no trailing NL)
    0=zero O=oh 1=one l=ell I=eye

- **Date** is mandatory. Recovery codes get regenerated; two undated sheets in
  one envelope is a coin flip.
- **Line numbers** appear only when the secret has more than one line, and
  are parenthesised — `(1)`, never a bare `1`. Found on the first real print
  of numeric recovery codes: `   1  48273910` separates the ordinal from the
  content with nothing but whitespace, which is the weakest possible
  delimiter when both sides are digits. Parentheses delimit on both sides so
  the marker cannot bind to an adjacent digit. The field widens past 99 lines
  rather than overflowing the width budget.
- **Checksum** is the first 8 hex characters of `sha256` over the lines joined
  with LF and no trailing newline. The recipe is printed alongside it — an
  unreproducible checksum is decoration.
- **Glyph legend** is one line and is kept even for a self-reader. Its purpose
  is not to teach `0` vs `O` but to provide this printer's actual glyph shapes
  as a side-by-side reference when reading degraded toner years later.

**Font sizing.** Monospace. Select the largest size from 12/11/10/9/8pt whose
longest secret line fits the usable width. Below 8pt, hard-wrap with a visible
continuation marker (`↳`) and say so in the preview. A silently wrapped secret
is a corrupt secret; wrapping must always be visible.

**Output format: RESOLVED — plain text piped to `lp`.** Settled empirically on
2026-08-21 against macOS 26 / CUPS 2.3.x; evidence below.

PostScript was rejected on two independent grounds:

1. The target queue does not advertise it. `document-format-supported` for
   `Laser_2000_tls` lists `application/pdf` and `text/plain`, with no
   `application/postscript`.
2. macOS 26 ships no PostScript-to-PDF filter (`/usr/libexec/cups/filter/` has
   `cgtexttopdf`, `cgpdftops`, `pstops`, `pstoappleps` — no Ghostscript), so
   `cupsfilter -m application/pdf` fails with "No filter to convert from
   application/postscript to application/pdf". This would also make `--dry-run`
   unimplementable for that route.

**Font is Monaco**, selected automatically by `cgtexttopdf` and embedded as a
subset. Not configurable — and does not need to be. Monaco's zero is slashed,
its `1` carries both a top flag and a base serif, its `l` has a tail, and its
`I` has crossbars. The disambiguation goal is met by the default.

**`cpi` is honored exactly.** Measured width of a 10-character string:
72.01pt at `cpi=10`, 60.01pt at `cpi=12`, 42.36pt at `cpi=17` — i.e. exactly
`72/cpi` points per character. This gives deterministic width control and is the
only layout primitive the design needs.

**Print options (all mandatory):**

    -o cpi=N
    -o lpi=N          # 3/4/5/6, default 4
    -o page-left=54 -o page-right=54 -o page-top=54 -o page-bottom=54
    -o sides=one-sided

`sides=one-sided` is **required, not cosmetic**. The queue's default is
`*DuplexNoTumble`; with `-n 2` the second copy would print on the reverse of the
first, silently destroying the purpose of making two copies for two locations.

**Line spacing is leading only.** Measured 2026-08-22: a ten-character string
is 72.01pt wide at every lpi, while the line pitch moves 12pt (lpi=6), 18pt
(lpi=4), 24pt (lpi=3). So spacing and type size are independent controls, and
the default moved from 6 to 4 after the first real print read as cramped.
Inserting blank lines was rejected: it alters the content structure, and a
blank line on a secret page raises the question of whether it belongs to the
secret.

**Page capacity is checked before printing.** Lower lpi means fewer lines per
sheet — 57 at lpi=6 down to 28 at lpi=3 — so the overflow risk rises with the
new default. A secret continuing onto a second sheet is a real hazard, because
the sheets can be separated and half a secret is no secret. `rendered_lines`
computes the wrapped line count and `main` warns when it plus the seven-line
header and footer exceeds `page_capacity`.

**Width budget.** Usable width is `612 - 54 - 54 = 504pt`. The line-number
gutter (`%4d` plus two spaces) consumes 6 characters when the secret has more
than one line.

| cpi | pt/char | total chars | secret chars (numbered) |
|---|---|---|---|
| 10 | 7.20 | 70 | 64 |
| 12 | 6.00 | 84 | 78 |
| 15 | 4.80 | 105 | 99 |
| 17 | 4.24 | 119 | 113 |

**The default is a fixed `cpi=10`, not a fit-search.** Revised 2026-08-22
after the first real print. The original design stepped down the ladder until
the longest line fit without wrapping. On a page holding one 120-character
secret alongside a 32-character one, that selected `cpi=17` — shrinking *every*
line to accommodate the longest — and then wrapped anyway, because 120 exceeds
even the 113-character budget at that size. The page paid in legibility across
the board and got a wrap regardless.

Legibility now wins: print at `cpi=10` and wrap what does not fit. Wrapping is
already unambiguous (see below), so there is nothing to buy by shrinking.
`--cpi` accepts 8, 10, 12, 15 or 17 for a reader who wants larger type or
denser packing; `--cpi 8` is effectively a large-print mode.

**Wrapping uses the gutter, not an in-band marker.** A continuation line prints
`...` in the number column instead of a digit. This avoids appending any
character to the secret's own text, so no wrap marker can ever be mistaken for
part of the secret.

**Non-ASCII prints correctly but breaks width math.** Verified: `café`, `→`,
`密码`, and `—` all render correctly through the filter — the earlier concern
that MacRoman encoding would mangle them was wrong. However, glyph advances stop
matching character counts (CJK is double-width, `→` is not), so the cpi table
above becomes unreliable. When non-ASCII is present, warn and drop one step in
the cpi ladder rather than attempting exact measurement. The horizontal rule
uses ASCII `-` for the same reason.

**Dry-run rendering** uses `cupsfilter -m application/pdf` with the identical
option set, so what is inspected is what would print.

### 6. Post-print

1. `lpstat -o` for the chosen printer; wait for Enter.
2. Purge the completed job **for that printer only**. Skip with a printed note
   if other jobs are queued — the script must never be able to cancel an
   unrelated print.
3. `clear` followed by `ESC[3J` to drop scrollback.

### 7. `--dry-run`

Renders the full page to a PDF using **built-in sample content** and prints the
path. It does **not** prompt for a secret.

This is deliberate. A dry-run that accepted a real secret would write that
secret in plaintext to a PDF on disk — precisely the outcome the entire script
exists to prevent, reachable by one wrong flag. Sample content is shaped like
realistic recovery codes so margins and font selection can be tuned honestly.

Output goes to `$TMPDIR`, never the project directory, so it cannot be
committed by accident.

## Removed from the original script

- `unset HISTFILE` — deleted. A non-interactive zsh script writes no history,
  and `read` values never enter history under any circumstance. It is harmless
  but implies a protection that does not exist; the only history artifact is the
  script's own invocation, which is fine. A comment records why it is absent.
- Fixed-width `••••••••••••••••` preview mask — replaced by real structure
  (§4). A mask that is identical for every input verifies nothing.
- `unset LABEL SECRET` — **kept**, with honest framing in a comment: it drops
  the reference, it does not zero the memory. Shell cannot do better.

## Structure

Single zsh file. Dependencies are base macOS only: `lp`, `lpstat`, `cancel`,
`shasum`, `defaults`, `tmutil`, `pgrep`.

    check_backup_agents()  -> tier 1 banner, tier 2 detection, gate
    select_printer()       -> enumerate, classify, menu, gate
    read_secret()          -> bracketed-paste-safe capture loop
    render_preview()       -> masked-edge structure display
    build_page()           -> PURE: (label, lines, date) -> page text/PostScript
    submit()               -> pipe to lp, report, purge, clear

`build_page` is pure by design — no I/O, no globals — so it can be exercised
with dummy input from a test harness and from `--dry-run` without a printer.

Flags: `-P NAME`, `-n COPIES` (default 1), `--dry-run`, `-h`.

Exit codes: `0` success or user cancel; `1` usage/validation error; `2` backup
gate refused; `3` printer selection refused; `4` print submission failed.

## Testing

- `build_page` against fixtures: single-line, 10-line, over-width line, line
  containing a tab, non-ASCII line, 1-character line.
- Transport classifier against one queue URI of each transport class, plus
  synthetic `socket://` and `lpd://`.
- Bracketed-paste guard: verify capture is byte-identical with the terminal's
  paste mode armed and disarmed.
- Backup gate: verify it trips on `AutoBackup=1` while `tmutil status` reports
  `Running = 0`.
- `--dry-run` end to end, inspecting the PDF.
