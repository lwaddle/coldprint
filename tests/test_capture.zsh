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

# A double paste of the same block is easy to do blind (echo is off) and the
# masked preview of identical lines looks unremarkable.
assert_eq "a duplicate line is flagged with both positions" \
    "line 3 duplicates line 1 (double paste?)" \
    "$(flag_characters 'aaa' 'bbb' 'aaa')"

assert_eq "each later duplicate points at the first occurrence" \
    "line 2 duplicates line 1 (double paste?)
line 3 duplicates line 1 (double paste?)" \
    "$(flag_characters 'x1y2' 'x1y2' 'x1y2')"

# Defence in depth: disabling bracketed paste only works if the terminal obeys.
# tmux re-arms it. Wrapper bytes are never legitimate secret content, and a
# silently corrupted secret on paper is unrecoverable.
assert_eq "leading paste wrapper is stripped" \
    "code-one" \
    "$(printf '\033[200~code-one\n\n' | read_secret_lines 2>/dev/null)"

assert_eq "wrappers spanning several lines are stripped" \
    "code-one
code-two" \
    "$(printf '\033[200~code-one\ncode-two\033[201~\n\n' | read_secret_lines 2>/dev/null)"

assert_eq "stripping a wrapper emits a warning" \
    "1" \
    "$(printf '\033[200~x\n\n' | read_secret_lines 2>&1 >/dev/null | grep -c 'bracketed paste' | tr -d ' ')"

assert_eq "ordinary escape-like text is untouched" \
    "a[200~b" \
    "$(printf 'a[200~b\n\n' | read_secret_lines 2>/dev/null)"

finish
