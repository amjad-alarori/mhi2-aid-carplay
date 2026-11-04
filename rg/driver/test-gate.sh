#!/bin/sh
# Emulates the log gate on real driver bytes (test_log_gate.py) in the qnx65-armv7-toolchain:8.5 image, no network.
# unicorn crashes on macOS here, so it runs in docker. UNICORN_SITE = an unpacked unicorn 2.1.1 manylinux x86_64 wheel
# (third-party download: own directory, python -I). Usage: rg/driver/test-gate.sh B4_DRIVER GATED_DRIVER
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
: "${UNICORN_SITE:?set UNICORN_SITE}"
A=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); B=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
docker run --rm --network=none --platform=linux/amd64 -v "$UNICORN_SITE":/uc:ro -v "$HERE":/t:ro \
    -v "$A":/d/b4.so:ro -v "$B":/d/gated.so:ro qnx65-armv7-toolchain:8.5 \
    python3 -I -c "import sys,runpy; sys.path.insert(0,'/uc'); sys.argv=['t','/d/b4.so','/d/gated.so']; runpy.run_path('/t/test_log_gate.py', run_name='__main__')"
