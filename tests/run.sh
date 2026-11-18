#!/bin/sh
# tests/run.sh [term]: check every program, read saved screens, and drive a
# real fzf in a session core of its own (agy is not run: it needs a sign-in;
# see README). term: the term executable (default: term on PATH).
set -u
TERM_BIN=${1:-term}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(dirname "$HERE")
export TERM_SESSION_DIR=$(mktemp -d /tmp/tpt-XXXXXX)
export TERM_CORE_GRACE_MS=300 # this core ends soon after its last session
unset TERM_SESSION_ID
fails=0
cleanup() { # only this core's sessions (term quit would end the window too)
  for id in $("$TERM_BIN" session ls 2>/dev/null | awk 'NR > 1 { print $1 }'); do "$TERM_BIN" session kill "$id" >/dev/null 2>&1; done
  sleep 1
  rm -rf "$TERM_SESSION_DIR"
}
trap cleanup EXIT

expect() { # expect <name> <want> <got>
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: want [$2], got [$3]"; fails=$((fails + 1)); fi
}

for prog in agy fzf; do
  "$TERM_BIN" program check "$ROOT/$prog.lua" >/dev/null 2>&1; expect "check $prog" 0 $?
done
(cd "$HERE" && "$TERM_BIN" run ./fzf_screen.lua) >/dev/null 2>&1; expect "fzf screens" 0 $?

ITEMS="printf 'alpha\nbeta\ngamma\nbetamax\nalphabet soup\n'"
FZF="$TERM_BIN run $ROOT/fzf.lua"
$FZF list "" -- sh -c "$ITEMS" >/dev/null 2>&1 # the first one starts the core
expect "list" "beta,betamax,alphabet soup" "$($FZF list bet -- sh -c "$ITEMS" | paste -sd, -)"
expect "list --json" '{"items":["gamma"],"matched":1,"query":"gam","total":5}' "$($FZF list gam --json -- sh -c "$ITEMS")"
expect "pick" "beta" "$($FZF pick bet -- sh -c "$ITEMS")"
expect "pick --nth 3" "alphabet soup" "$($FZF pick bet --nth 3 -- sh -c "$ITEMS")"
$FZF pick zzz -- sh -c "$ITEMS" >/dev/null 2>&1; expect "pick no match exits 1" 1 $?
$FZF pick bet >/dev/null 2>&1; expect "no target exits 2" 2 $?

# an fzf someone else's command shows
S=$("$TERM_BIN" session new -s 80x14 -- sh -c "$ITEMS | fzf > $TERM_SESSION_DIR/picked; sleep 5")
expect "pick --session" "betamax" "$($FZF pick bet --nth 2 --session "$S")"
sleep 0.3
expect "the command got it" "betamax" "$(cat "$TERM_SESSION_DIR/picked")"

[ "$fails" -eq 0 ] && echo "all passed" || echo "$fails failed"
[ "$fails" -eq 0 ]
