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
----------------
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
