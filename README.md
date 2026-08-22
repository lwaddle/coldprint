# coldprint

Print a secret — a passphrase, a block of recovery codes — onto paper for a
continuity envelope, without it touching disk, shell history, or an
unencrypted network hop.

    ./coldprint                 # select a printer, enter a secret
    ./coldprint -P NAME -n 2    # named queue, two copies
    ./coldprint --cpi 8         # larger type
    ./coldprint --dry-run       # render sample content to a PDF

## What it does for you

- **Refuses to run while backup software is live.** Time Machine (including
  armed-but-idle, which can fire mid-print), Backblaze, Arq, Carbon Copy
  Cloner, ChronoSync, restic, borg, duplicati. Override requires typing
  `OVERRIDE` in full — `y` will not do it.
- **Warns unconditionally**, every run, even when nothing is detected. The
  detector only knows the tools it knows.
- **Refuses cleartext print transports** unless overridden the same way. A
  `dnssd://` queue advertising `_ipp._tcp` is cleartext despite the scheme;
  the script parses the service type, not just the URI prefix.
- **Forces one-sided printing.** The queue default here is duplex, which would
  put copy 2 on the back of copy 1 and defeat the point of two copies.
- **Never echoes the secret**, disables bracketed paste, and strips
  `ESC[200~`/`ESC[201~` if a terminal sends them anyway — tmux re-arms
  bracketed paste, and those bytes would otherwise land silently inside the
  secret.
- **Shows you what you actually captured** — first and last two characters of
  each line plus exact counts, so a wrong paste or a missing line is visible
  without putting plaintext on screen.
- **Never writes the secret to disk.** It exists in shell variables and pipes
  only. (`--dry-run` does write a file, which is exactly why it refuses to
  accept a real secret and renders fixed sample content instead.)

## What it cannot do for you

- **`/var/spool/cups`.** While the job prints, it exists there in cleartext.
  This is unavoidable and is the entire reason the backup gate exists.
- **Memory.** `unset` drops a reference; it does not zero memory. Shell cannot.
- **Your clipboard.** If you paste from a password manager, the secret is in
  the system clipboard, which is outside this script's reach.
- **Terminal session logging.** If iTerm2's "Automatically log session to
  files" is on, your session is being written to disk. Check
  Settings → Profiles → Session. The script clears scrollback but cannot
  un-write a log file.
- **The printer's own memory**, and the output tray. Collect the page.

## The printed page

    Fastmail recovery codes
    --------------------------------------------------
    2026-08-21 22:22

     (1)  4fh2n8-xk3m2c
     (2)  9ap7q1-w4rte1
     ...

    sha256/8: 1fd05191  (LF-joined, no trailing NL)
    0=zero  O=oh  1=one  l=ell  I=eye

The date matters: recovery codes get regenerated, and two undated sheets in
one envelope is a coin flip. The checksum prints its own recipe, because eight
hex characters you cannot reproduce are decoration. The glyph legend is there
so you can compare *this printer's* shapes against a reference when reading
degraded toner years from now.

Font is Monaco, chosen automatically by the CUPS text filter — slashed zero,
`1` with a top flag and base serif, `l` with a tail.

Type is set at `cpi=10` and long lines **wrap** rather than shrinking the page.
Shrinking to fit the longest line penalises every other line, and past a
certain length it wraps anyway — so it costs readability and buys nothing.
Line numbers are parenthesised — `(1)`, not a bare `1` — because with an
all-numeric secret an unadorned ordinal separated only by spaces reads as
part of the code. Continuations are marked by `...` in the number column, never by a character
appended to the secret itself. `--cpi 8` gives larger type; `--cpi 15` or `17`
pack more per line if you prefer fewer wraps.

## Verifying a transcription

The `sha256/8` line answers one question: *did I type this back in correctly?*

Restoring from paper means retyping the secret by hand with no feedback — the
service just says "invalid", and you cannot tell a typo from an expired code.
Check before you commit:

    printf '%s' "$(cat)" | shasum -a 256 | cut -c1-8

Type or paste the lines, press Ctrl-D, and compare to the page. Matching means
you transcribed it correctly.

    $ printf '%s' "$(cat)" | shasum -a 256 | cut -c1-8
    aaa
    bbb
    ccc
    ^D
    8c802c52

**The `(LF-joined, no trailing NL)` note on the page is the recipe, not a
footnote.** Join the lines with newlines and do not add a trailing one. Getting
that wrong produces a completely different hash — for the example above,
including a trailing newline yields `e77229fd` instead of `8c802c52`, which
looks exactly like a failed transcription. The `$(cat)` above handles this for
you: command substitution strips trailing newlines while preserving everything
else, including a trailing space on the last line.

Two things this is not. Eight hex characters is 32 bits — ample for catching a
typo (roughly one in four billion false accepts) but not a cryptographic
integrity guarantee. And it cannot tell you the secret is still *valid*, only
that it matches what was printed.

## Requirements

macOS with zsh. No third-party dependencies: `lp`, `lpstat`, `cancel`,
`cupsfilter`, `shasum`, `defaults`, `tmutil`, `pgrep`, and `stty` are all base
system.

## Tests

    zsh tests/run_all.zsh

54 tests covering transport classification, the backup gate, capture and paste
handling, masking, and page layout.

## Design notes

[`docs/design.md`](docs/design.md) records the threat model and the reasoning
behind each decision, including what was measured rather than assumed — how
CUPS renders text, why PostScript was rejected, and why the backup gate cannot
watch for `backupd`.

## Contributing

Issues and pull requests welcome. If you find a way to get a secret onto disk,
onto the network in cleartext, or silently corrupted between the prompt and the
page, that is the most useful bug you can report.

## License

MIT — see [LICENSE](LICENSE).
