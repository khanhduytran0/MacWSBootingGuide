#!/bin/bash
set -e
path="$2"

vtool -arch arm64 -set-build-version $PLATFORM 11.0 11.0 -replace -output "$path" "$path"
ldid -Cadhoc -S $@
