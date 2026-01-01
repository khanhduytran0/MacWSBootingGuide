#!/bin/bash
set -e

if [[ -z "$1" ]]; then
    echo "Usage: $0 /path/to/launchservicesd"
    exit 1
fi

path="${mktemp /tmp/launchservicesd.XXXX}
lipo -thin arm64e -o $path "$1"

# patch exec to dylib
# patch filetype = MH_DYLIB
printf '\x06' | dd of=$1 bs=1 seek=12 count=1 conv=notrunc
# patch flags = MH_NO_REEXPORTED_DYLIBS ~ MH_PIE
printf '\x80\x11' | dd of=$1 bs=1 seek=25 count=2 conv=notrunc
# patch PAGEZERO

#vtool -set-build-version 1 13.0 13.0 -replace -output "$path" "$path"
ldid -S "$path"
