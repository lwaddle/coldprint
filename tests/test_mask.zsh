#!/bin/zsh
source ${0:A:h}/helpers.zsh
COLDPRINT_LIB=1 source ${0:A:h}/../coldprint

assert_eq "long line shows first two and last two" \
    "hu••••••••••r2" "$(mask_line 'hunter2hunter2')"
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

  [ 1] ab••ef    (6 chars)
  [ 2] gh••••mn  (8 chars)

  Total: 2 lines, 14 chars" \
    "$(render_preview 'Test codes' 'abcdef' 'ghijklmn' 2>&1)"

assert_eq "single-line preview totals correctly" \
"Label:  One
Lines:  1

  [ 1] hu••••••••••r2  (14 chars)

  Total: 1 line, 14 chars" \
    "$(render_preview 'One' 'hunter2hunter2' 2>&1)"

finish
