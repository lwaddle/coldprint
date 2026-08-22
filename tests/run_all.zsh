#!/bin/zsh
cd ${0:A:h}
typeset -i failed=0
for t in test_*.zsh; do
    print -r -- "== $t"
    zsh "$t" || failed=1
done
exit $failed
