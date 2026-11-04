#!/bin/sh
# Assembles log-gate.S at its final address in the patched driver (QNX 6.5 binutils in the qnx65-armv7-toolchain:8.5
# image). Usage: rg/driver/build-gate.sh OUTDIR  ->  OUTDIR/log-gate.bin
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(mkdir -p "$1" && cd "$1" && pwd)
docker run --rm --platform=linux/amd64 -v "$HERE":/src:ro -v "$OUT":/out -w /src qnx65-armv7-toolchain:8.5 bash -c '
set -e
P=/opt/qnx650/host/linux/x86/usr/bin/arm-unknown-nto-qnx6.5.0eabi
$P-as -march=armv7-a -o /tmp/gate.o log-gate.S
$P-ld -Ttext=0xb571c --defsym open_plt=0x4cb8 --defsym close_plt=0x4d3c --defsym b2_receive_resume=0xb5124 \
    -e pmcp_log_gate -o /tmp/gate.elf /tmp/gate.o
$P-objcopy -O binary -j .text /tmp/gate.elf /out/log-gate.bin
$P-objdump -d /tmp/gate.elf | sed -n "/<pmcp_log_gate>/,\$p"'
