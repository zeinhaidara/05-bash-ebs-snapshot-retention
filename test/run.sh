#!/usr/bin/env bash
# Runs backup.sh against test/fake-aws. No AWS calls.
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp "$here/fake-aws" "$tmp/aws"
chmod +x "$tmp/aws"
export PATH="$tmp:$PATH"
export FAKE_LOG="$tmp/calls.log"
script="$here/../backup.sh"
fails=0

check() { # name, condition result (0 = pass)
  if [ "$2" -eq 0 ]; then echo "PASS $1"; else echo "FAIL $1"; fails=1; fi
}
run() { : > "$FAKE_LOG"; "$script" "$@" >/dev/null 2>&1; rc=$?; }
called() { grep -q "$1" "$FAKE_LOG"; }

run snapshot --region us-east-1
[ $rc -eq 0 ] && called "create-snapshot --volume-id vol-running" && ! called "create-snapshot --volume-id vol-stopped"
check "snapshot skips stopped instances" $?

run prune --region us-east-1
[ $rc -eq 0 ] && ! called delete-snapshot
check "prune without --execute deletes nothing" $?

run prune --region us-east-1 --execute
[ $rc -eq 0 ] && called "delete-snapshot --snapshot-id snap-old" && ! called "snap-recent"
check "prune --execute deletes only old snapshots" $?

run prune --region us-east-1 --execute
! called "snap-foreign"
check "prune never touches snapshots without the tag" $?

run prune --region us-east-1 --retention-days 3 --execute
[ $rc -ne 0 ] && ! called delete-snapshot
check "retention below 7 days is refused" $?

exit $fails
