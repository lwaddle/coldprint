#!/bin/zsh
source ${0:A:h}/helpers.zsh
COLDPRINT_LIB=1 source ${0:A:h}/../coldprint

# --- cpi budgets ---------------------------------------------------------
assert_eq "default favours legibility, not density" "10" "$CPI_DEFAULT"
assert_eq "cpi 8 budget"  "56"  "$(cpi_budget 8)"
assert_eq "cpi 10 budget" "70"  "$(cpi_budget 10)"
assert_eq "cpi 12 budget" "84"  "$(cpi_budget 12)"
assert_eq "cpi 15 budget" "105" "$(cpi_budget 15)"
assert_eq "cpi 17 budget" "119" "$(cpi_budget 17)"
cpi_budget 9  >/dev/null 2>&1; assert_status "unsupported cpi rejected" 1 $?
cpi_budget 10 >/dev/null 2>&1; assert_status "supported cpi accepted"   0 $?
assert_eq "choices are offered largest-type first" "8 10 12 15 17" "$(cpi_choices)"

# --- gutter ---------------------------------------------------------------
# Bare ordinals read as part of a numeric secret, so markers are parenthesised.
assert_eq "single line carries no gutter"       "0" "$(gutter_width 1)"
assert_eq "two lines get the base gutter"       "6" "$(gutter_width 2)"
assert_eq "two-digit counts still fit the base" "6" "$(gutter_width 99)"
assert_eq "three-digit counts widen the field"  "7" "$(gutter_width 100)"

assert_eq "markers are parenthesised, not bare" \
    " (1)  8273910" \
    "$(printf '8273910\n9182736\n' | build_page 'N' '2026-08-22 08:15' 70 | sed -n 5p)"

# --- page layout ---------------------------------------------------------
# Checksum is sha256 over the LF-joined lines with no trailing newline.
SUM_MULTI="$(printf '%s' 'aaa
bbb' | shasum -a 256 | cut -c1-8)"

assert_eq "multi-line page is numbered and carries metadata" \
"My codes
--------------------------------------------------
2026-08-21 21:45

 (1)  aaa
 (2)  bbb

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

 (1)  ABCDEFGHIJ
 ...  KLMNO
 (2)  short

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
