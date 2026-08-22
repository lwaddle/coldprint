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
