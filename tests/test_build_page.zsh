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

# --- line spacing ----------------------------------------------------------
# lpi is leading only: glyph width measures 72.01pt for 10 characters at every
# lpi, while the line pitch moves 12pt (lpi=6) to 24pt (lpi=3).
assert_eq "default leaves breathing room" "4" "$LPI_DEFAULT"
assert_eq "lpi 6 capacity" "57" "$(page_capacity 6)"
assert_eq "lpi 5 capacity" "47" "$(page_capacity 5)"
assert_eq "lpi 4 capacity" "38" "$(page_capacity 4)"
assert_eq "lpi 3 capacity" "28" "$(page_capacity 3)"
lpi_ok 4 && assert_status "supported lpi accepted" 0 0 || assert_status "supported lpi accepted" 0 1
lpi_ok 7 && assert_status "unsupported lpi rejected" 1 0 || assert_status "unsupported lpi rejected" 1 1

assert_eq "lp_options carries the requested lpi and forces one-sided" \
    "cpi=10 lpi=4 sides=one-sided" \
    "$(lp_options 10 4 | grep -E '^(cpi|lpi|sides)=' | tr '\n' ' ' | sed 's/ $//')"

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
# The secret block is closed by a second rule, and the footer states the
# expected shape so a torn or truncated page is detectable from the page alone.
SUM_MULTI="$(printf '%s' 'aaa
bbb' | shasum -a 256 | cut -c1-8)"

assert_eq "multi-line page is numbered, delimited, and carries metadata" \
"My codes
--------------------------------------------------
2026-08-21 21:45

 (1)  aaa
 (2)  bbb

--------------------------------------------------
2 lines, 6 chars
sha256/8: ${SUM_MULTI}  (LF-joined, no trailing NL)" \
    "$(printf 'aaa\nbbb\n' | build_page 'My codes' '2026-08-21 21:45' 70)"

SUM_ONE="$(printf '%s' 'hunter2' | shasum -a 256 | cut -c1-8)"
assert_eq "single-line page omits the number gutter" \
"My pass
--------------------------------------------------
2026-08-21 21:45

hunter2

--------------------------------------------------
1 line, 7 chars
sha256/8: ${SUM_ONE}  (LF-joined, no trailing NL)
2=two" \
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

----------------
2 lines, 20 chars
sha256/8: ${SUM_WRAP}  (LF-joined, no trailing NL)
O=oh  I=eye
B=bee" \
    "$(printf 'ABCDEFGHIJKLMNO\nshort\n' | build_page 'W' '2026-08-21 21:45' 16)"

# --- glyph legend ---------------------------------------------------------
# The legend exists to put this printer's actual glyph shapes next to their
# names. An entry for a glyph the secret does not contain is noise; a secret
# with no ambiguous glyphs gets no legend at all.
assert_eq "legend lists only the ambiguous glyphs present, in canonical order" \
    "0=zero  O=oh  1=one  l=ell" \
    "$(printf 'O01l\n' | build_page 'L' '2026-08-21 21:45' 70 | tail -1)"

assert_eq "clean secret gets no legend line" \
    "sha256/8" \
    "$(printf 'aaa\nbbb\n' | build_page 'L' '2026-08-21 21:45' 70 | tail -1 | cut -c1-8)"

assert_eq "hyphen and underscore are legend glyphs" \
    "-=hyphen  _=underscore" \
    "$(printf 'a-b_c\n' | build_page 'L' '2026-08-21 21:45' 70 | tail -1)"

# A legend that outgrows the printable width wraps between entries rather than
# letting the CUPS filter break it mid-entry.
assert_eq "over-width legend wraps between entries" \
"0=zero  O=oh  1=one
l=ell  I=eye  2=two" \
    "$(printf '0O1lI2\n' | build_page 'L' '2026-08-21 21:45' 20 | tail -2)"

# A single-line secret normally has no gutter — but if it wraps, the wrap
# must still be visible. Numbering is forced so continuations get the marker.
assert_eq "a wrapping single-line secret gains the gutter and markers" \
" (1)  abcdef
 ...  hjkmnp
 ...  r" \
    "$(printf 'abcdefhjkmnpr\n' | build_page 'P' '2026-08-21 21:45' 12 | sed -n '5,7p')"

# --- on-page notes --------------------------------------------------------
# Trailing whitespace and tabs print invisibly, yet the checksum includes
# them — a transcription that omits one fails the hash with nothing on the
# page explaining why. The screen warning protects the author; only ink
# protects the reader.
assert_eq "invisible characters are noted on the page itself" \
"note: line 1 ends with whitespace (part of the secret)
note: line 2 contains a tab" \
    "$(printf 'abc \nd\te\n' | build_page 'N' '2026-08-21 21:45' 70 | tail -2)"

assert_eq "clean secret carries no notes" \
    "0" \
    "$(printf 'aaa\nbbb\n' | build_page 'N' '2026-08-21 21:45' 70 | grep -c '^note:' | tr -d ' ')"

# --- per-line counts ------------------------------------------------------
# Opt-in: a right-aligned (nn) column localises a mistranscription to one
# line without bisecting the whole-page hash. The count is the source line's
# length and sits on its last printed segment.
assert_eq "counts column is right-aligned past the widest content" \
" (1)  abcdef     (6)
 (2)  xy         (2)" \
    "$(printf 'abcdef\nxy\n' | build_page 'C' '2026-08-21 21:45' 20 0 1 | sed -n '5,6p')"

assert_eq "a wrapped line carries its count on the last segment only" \
" (1)  abcdefgh
 ...  jkm       (11)
 (2)  xy         (2)" \
    "$(printf 'abcdefghjkm\nxy\n' | build_page 'C' '2026-08-21 21:45' 20 0 1 | sed -n '5,7p')"

# The counts column narrows the budget, so the single-line wrap check must
# account for it: 15 chars at total 20 with counts reserved must still wrap
# visibly.
assert_eq "counts reserve keeps single-line wraps visible" \
" (1)  abcdefhj
 ...  kmnprst   (15)" \
    "$(printf 'abcdefhjkmnprst\n' | build_page 'C' '2026-08-21 21:45' 20 0 1 | sed -n '5,6p')"

# --- pagination -----------------------------------------------------------
# When a secret spills past one sheet, build_page paginates itself with form
# feeds (the CUPS text filter honours \f) instead of letting the filter break
# the page blind. Every sheet carries the label, rule, and a dated
# "(sheet k of K)" marker so a separated sheet is self-identifying; the footer
# prints on the last sheet.
#
# A sheet followed by a form feed holds at most capacity-1 lines: at exactly
# capacity the filter breaks the page on its own first and the form feed then
# emits a blank sheet (verified empirically against cgtexttopdf).
SUM_PAGED="$(printf '%s' 'aa
bb
cc
dd
ee
ff
hh
mm
nn
pp' | shasum -a 256 | cut -c1-8)"

assert_eq "spilling content paginates with headers on every sheet" \
"Codes
--------------------------------------------------
2026-08-21 21:45  (sheet 1 of 2)

 (1)  aa
 (2)  bb
 (3)  cc
 (4)  dd
 (5)  ee
 (6)  ff
 (7)  hh
"$'\f'"Codes
--------------------------------------------------
2026-08-21 21:45  (sheet 2 of 2)

 (8)  mm
 (9)  nn
(10)  pp

--------------------------------------------------
10 lines, 20 chars
sha256/8: ${SUM_PAGED}  (LF-joined, no trailing NL)" \
    "$(printf 'aa\nbb\ncc\ndd\nee\nff\nhh\nmm\nnn\npp\n' \
        | build_page 'Codes' '2026-08-21 21:45' 70 12)"

assert_eq "content that fits one sheet gets no sheet marker" \
    "2026-08-21 21:45" \
    "$(printf 'aa\nbb\n' | build_page 'Codes' '2026-08-21 21:45' 70 38 | sed -n 3p)"

# When the rows fill every non-final sheet, the footer moves to a sheet of
# its own rather than spilling blind — and drops its leading blank line,
# which the fresh sheet's header already provides.
assert_eq "footer that cannot fit under the rows gets its own sheet" \
$'\f'"Codes
--------------------------------------------------
2026-08-21 21:45  (sheet 2 of 2)

--------------------------------------------------
7 lines, 14 chars
sha256/8: $(printf '%s' 'aa
bb
cc
dd
ee
ff
hh' | shasum -a 256 | cut -c1-8)  (LF-joined, no trailing NL)" \
    "$(printf 'aa\nbb\ncc\ndd\nee\nff\nhh\n' \
        | build_page 'Codes' '2026-08-21 21:45' 70 12 | sed -n '12,$p')"

# --- envelope slip --------------------------------------------------------
# A slip for the outside of the envelope: label, date, shape, checksum — no
# secret — so future-me can identify an envelope's contents, and whether they
# were superseded, without breaking the seal.
assert_eq "envelope slip carries metadata and no secret content" \
"My codes
--------------------------------------------------
2026-08-21 21:45
2 lines, 6 chars
sha256/8: ${SUM_MULTI}  (LF-joined, no trailing NL)

(envelope slip; contains no secret)" \
    "$(printf 'aaa\nbbb\n' | build_envelope_slip 'My codes' '2026-08-21 21:45' 70)"

assert_eq "slip never echoes a secret line" \
    "0" \
    "$(printf 'hunter2\n' | build_envelope_slip 'P' '2026-08-21 21:45' 70 | grep -c hunter2 | tr -d ' ')"

# The rule never runs past the printable width.
assert_eq "rule is clamped to the character budget" \
    "20" \
    "$(printf 'x\n' | build_page 'Lbl' '2026-08-21 21:45' 20 | sed -n 2p | tr -d '\n' | wc -c | tr -d ' ')"

# A label longer than 50 widens the rule to match.
assert_eq "rule matches an over-long label" \
    "60" \
    "$(printf 'x\n' | build_page "$(printf 'L%.0s' {1..60})" '2026-08-21 21:45' 70 | sed -n 2p | tr -d '\n' | wc -c | tr -d ' ')"

finish
