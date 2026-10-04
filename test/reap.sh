#!/usr/bin/env bash
# Checks that a stop ends what the stopped process left running: a child in its
# own process session that ignores SIGTERM, like a stuck background tool shell.
set -uo pipefail
crew="$(dirname "$0")/../bin/claude-crew"
source <(sed -n '/^proc_start() {/,/^}/p; /^descendants() {/,/^}/p; /^reap_survivors() {/,/^}/p' "$crew")
count() { local p n=0; for p in $(pgrep -x sleep); do [ "$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)" = "sleep 30171 " ] && n=$((n + 1)); done; echo "$n"; }

bash -c 'setsid -w bash -c "sleep 30171 & trap \"\" TERM; sleep 30171" & wait' & parent=$!
sleep 1
mapfile -t kids < <(descendants "$parent")
[ "${#kids[@]}" -eq 3 ] || { echo "FAIL: expected 3 descendants, got ${#kids[@]}"; exit 1; }
kill "$parent"; wait "$parent" 2>/dev/null
[ "$(count)" -eq 2 ] || { echo "FAIL: children should outlive the parent, $(count) alive"; exit 1; }
out=$(reap_survivors "${kids[@]}")
[ "$(count)" -eq 0 ] || { echo "FAIL: $(count) survived the reap"; exit 1; }
grep -q '^ended 3 process' <<<"$out" || { echo "FAIL: report was: $out"; exit 1; }
[ -z "$(reap_survivors "${kids[@]}")" ] || { echo "FAIL: a second reap found something"; exit 1; }
echo ok
