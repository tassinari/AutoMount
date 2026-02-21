#!/bin/bash
SCRIPT_DIR="$(dirname "$0")"
echo $SCRIPT_DIR
pushd $SCRIPT_DIR
hdiutil attach test.dmg
popd
