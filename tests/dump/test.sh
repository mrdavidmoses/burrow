#! /bin/bash

# Test the dump restore functionality
# 
# Steps taken:
# - Create a chain
# - Create some code and events
# - Dump chain
# - Stop chain and delete
# - Restore chain from dump
# - Check all bits are present (account, namereg, code, events)
#

set -e

burrow_dump="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
tmp_dir=$(mktemp -d 2>/dev/null || mktemp -d -t 'tmpdumpXXX')
trap "rm -f $tmp_dir" EXIT
cd $tmp_dir
rm -rf .burrow genesis.json burrow.toml burrow.log

burrow_bin=${burrow_bin:-burrow}

echo "------------------------------------"
echo "Creating new chain..."
echo "------------------------------------"

$burrow_bin spec -n "Fresh Chain" -v1 | $burrow_bin configure -m BurrowTestDumpNode -s- -w genesis.json > burrow.toml

$burrow_bin start 2>> burrow.log &
burrow_pid=$!
function kill_burrow {
	kill -KILL $burrow_pid
	rm -rf $tmp_dir
}
trap kill_burrow EXIT

sleep 1

echo "------------------------------------"
echo "Creating code, events and names..."
echo "------------------------------------"

$burrow_bin deploy -o '' -a Validator_0 --file deploy.yaml --dir $burrow_dump


echo "------------------------------------"
echo "Dumping chain..."
echo "------------------------------------"

$burrow_bin dump dump.bin
$burrow_bin dump -j dump.json
height=$(head -1  dump.json | jq .Height)

kill $burrow_pid

# Now we have a dump with out stuff in it. Delete everything apart from
# the dump and the keys
mv genesis.json genesis-original.json
rm -rf .burrow burrow.toml

echo "------------------------------------"
echo "Create new chain based of dump with new name..."
echo "------------------------------------"

$burrow_bin configure -m BurrowTestRestoreNode -n "Restored Chain" -g genesis-original.json -w genesis.json --restore-dump dump.json > burrow.toml

$burrow_bin restore dump.json
$burrow_bin start 2>> burrow.log &
burrow_pid=$!
sleep 13

echo "------------------------------------"
echo "Dumping restored chain for comparison..."
echo "------------------------------------"

burrow dump -j --height $height dump-after-restore.json

kill $burrow_pid

if cmp dump.json dump-after-restore.json
then
	echo "------------------------------------"
	echo "Done."
	echo "------------------------------------"
else
	echo "RESTORE FAILURE"
	echo "restored dump is different"
	diff -u dump.json dump-after-restore.json
	exit 1
fi
