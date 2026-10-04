#!/usr/bin/env bash
# Checks the busy guards: refuse without --force, warn and proceed with it.
# Loads the three guard functions from bin/claude-crew and stubs what they read.
set -uo pipefail
crew="$(dirname "$0")/../bin/claude-crew"
source <(sed -n '/^busy_cost() {/,/^}/p; /^guard_busy() {/,/^}/p; /^guard_all() {/,/^}/p' "$crew")

declare -A PID_OF_SESS=([A]=1 [B]=2 [C]=3) STATE=([A]=working [B]=idle [C]=draft)
SELF_SESS=""; WAIT_IDLE=0
sess_activity() { echo "${STATE[$1]}"; }
title_of_sess() { echo "title-$1"; }
die() { echo "crew: $*" >&2; exit 1; }
fail() { echo "FAIL: $*"; exit 1; }

FORCE=0
out=$( (guard_busy A stop) 2>&1 ) && fail "busy session was not refused"
grep -q 'Nothing was done' <<<"$out" || fail "refusal text missing: $out"
out=$( (guard_busy B stop) 2>&1 ) || fail "idle session was refused"
[ -z "$out" ] || fail "idle session printed: $out"
out=$( (guard_all restart) 2>&1 ) && fail "restart was not refused"
grep -q '2 session(s) are not idle' <<<"$out" || fail "restart refusal text: $out"

FORCE=1
out=$( (guard_busy A stop) 2>&1 ) || fail "--force did not proceed"
grep -q 'WARNING: stop --force: title-A (A) is working on a turn, which ends now' <<<"$out" || fail "warning missing: $out"
out=$( (guard_busy B stop) 2>&1 ) || fail "--force refused an idle session"
[ -z "$out" ] || fail "idle session warned: $out"
out=$( (guard_all restart) 2>&1 ) || fail "restart --force did not proceed"
grep -q 'stops 2 session(s)' <<<"$out" || fail "restart warning count: $out"
grep -q 'title-C (C) has an unsent draft' <<<"$out" || fail "restart warning detail: $out"
grep -q 'title-B' <<<"$out" && fail "restart warned about an idle session"
echo "ok"
