#!/bin/zsh
source ${0:A:h}/helpers.zsh
COLDPRINT_LIB=1 source ${0:A:h}/../coldprint

# Dry-run PDFs are namespaced coldprint_dryrun_* and used to pile up in
# $TMPDIR, one per run. Each run now removes its predecessors, so at most the
# newest survives.
work="$(mktemp -d)"
TMPDIR="$work"

touch "$work/coldprint_dryrun_stale1.pdf" "$work/coldprint_dryrun_stale2.txt"
do_dry_run 10 4 >/dev/null 2>&1

assert_eq "stale dry-run files are removed" \
    "" "$(print -rl -- "$work"/coldprint_dryrun_stale*(N))"

remaining=( "$work"/coldprint_dryrun_*.pdf(N) )
assert_eq "exactly one dry-run PDF remains" "1" "${#remaining}"

rm -rf "$work"
finish
