#!/bin/sh
# Builds the pmcp rgi-observer variant (rg/reader/reader.c) for QNX 6.5 armv7 in the Docker image
# qnx65-armv7-toolchain:8.5 (luka-dev/qnx65-armv7-toolchain, QNX SDP 6.5; not shipped here). Usage: rg/reader/build.sh OUTDIR
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(mkdir -p "$1" && cd "$1" && pwd)
docker run --rm --platform=linux/amd64 -v "$HERE":/src:ro -v "$OUT":/out -w /src qnx65-armv7-toolchain:8.5 bash -c '
set -e
export PATH=/opt/qnx650/host/linux/x86/usr/bin:$PATH QNX_HOST=/opt/qnx650/host/linux/x86 QNX_TARGET=/opt/qnx650/target/qnx6
P=arm-unknown-nto-qnx6.5.0eabi
$P-gcc -O2 -Wall -Wextra -Werror -std=c99 -march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16 \
    -ffile-prefix-map=/src=. reader.c -o /out/rgi-observer
$P-strip /out/rgi-observer
$P-readelf -d /out/rgi-observer | grep NEEDED'
shasum -a 256 "$OUT/rgi-observer"
wc -c < "$OUT/rgi-observer"
