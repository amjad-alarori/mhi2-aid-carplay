#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Host tests for pmcp.sh against a fake unit tree built from our MU1161 backup, plus an execution
# test of the generated lsd.sh blocks (trial boot) over several simulated boots.
#   run_tests.sh SD_BUILD_DIR SHELL [SHELL...]
#   PMCP_TEST_SCOPE=speedlimit runs the optional reader cases against a fresh unit.
# Each scenario starts from a fresh factory tree. Exit status is the number of failed checks.
set -u
SDB=$(cd "${1:?sd build dir}" && pwd); shift
REPO=$(cd "$(dirname "$0")/../../.." && pwd)
BK="${PMCP_BACKUP:-$REPO/backup/MU1161}/advanced/MU1161-appimg"
export PMCP_TEST_GAWK="${PMCP_TEST_GAWK:-$REPO/upstream/tools/gawk-3.1.5/gawk}"
FAILS=0
W=$(mktemp -d /tmp/pmcp-test.XXXX)
STOCK_LSD=97bbd4ecb51045b34c2a41955d9f53e1f144d174bff1aa8560e911525808e8d8
LSD_JAVA=$(sed -n 's/^LSD_JAVA \([0-9a-f]*\) .*/\1/p' "$SDB/pmcp/pmcp.sh")
jsha() { sed -n "s/^JAR_$1 \([0-9a-f]*\) .*/\1/p" "$SDB/pmcp/pmcp.sh"; }
jid() { echo "$1-$(jsha "$1" | cut -c1-8)"; }
NAI_SHA=$(jsha nai); NP_SHA=$(jsha np)
NAI=$(jid nai); NP=$(jid np); RG=$(jid rg); ZOOM=$(jid zoom); DN=$(jid dn)
[ -n "$NAI_SHA" ] && [ -n "$NP_SHA" ] || { echo "no JAR hashes in the manifest"; exit 99; }
# simulate the lsd.sh block of the unit tree for one normal boot (or RUN_MODE=$1); prints "boot=USE set=ID jars=LIST"
unit_boot() {
    { echo "BASE_DIR=/X; BOOTCLASSPATH=-Xbootclasspath/a:/ifs/lsd.jxe; RUN_MODE=${1:-}"
      sed -n '/^# >>> pmcp: CarPlay AID mod/,/^# <<< pmcp/p' "$W/unit/mnt/app/eso/hmi/lsd/lsd.sh" \
        | sed -e "s#/mnt/app/carplaymaps#$W/unit/mnt/app/carplaymaps#g" -e "s#/mnt/persist/pmcp#$W/unit/mnt/persist/pmcp#g" \
              -e "s|( .PMCP_DIR/rg/rgi-observer.*) &|:|"
      echo 'echo "boot=$PMCP_USE set=$PMCP_SET jars=$PMCP_JARS"'; } > "$W/unit-boot.sh"
    $SH "$W/unit-boot.sh" 2>&1 | tail -1
}

ok()   { echo "  ok   $*"; }
bad()  { echo "  FAIL $*"; FAILS=$((FAILS+1)); }
expect_out() { grep -q -- "$1" "$W/out" && ok "$2" || { bad "$2 (wanted '$1')"; sed 's/^/       | /' "$W/out" | tail -8; }; }
snapshot() { (cd "$1" && find . -type f ! -path './sdlog/*' -exec shasum -a 256 {} \; | sort -k2); }
h() { shasum -a 256 < "$1" | cut -d' ' -f1; }

fresh_unit() {
    rm -rf "$W/unit" "$W/sd"
    mkdir -p "$W/unit/ifs" "$W/unit/ramdisk" "$W/unit/mnt/app/eso/bin/apps" "$W/unit/mnt/app/eso/hmi/lsd/jars" "$W/unit/mnt/app/armle/usr/bin" "$W/unit/mnt/persist/etc" \
        "$W/unit/mnt/app/armle/lib/dll" "$W/unit/mnt/system/etc/mm"
    cp "$BK/armle/lib/dll/ipod-drvr-iap2.so" "$W/unit/mnt/app/armle/lib/dll/"
    cp "$BK/../MU1161-system/mm/iap2.cfg" "$W/unit/mnt/system/etc/mm/"
    mkfile -n 55830309 "$W/unit/ifs/lsd.jxe" 2>/dev/null || truncate -s 55830309 "$W/unit/ifs/lsd.jxe"
    cp "$BK/eso/bin/apps/dio_manager" "$W/unit/mnt/app/eso/bin/apps/dio_manager"
    cp "$BK/eso/hmi/lsd/lsd.sh" "$W/unit/mnt/app/eso/hmi/lsd/lsd.sh"
    cp "$BK/eso/hmi/lsd/jars/"* "$W/unit/mnt/app/eso/hmi/lsd/jars/"
    echo "factory persist content" > "$W/unit/mnt/persist/etc/ffs3.2ver"
    cp -R "$SDB/pmcp" "$W/sd"
}

run() { PMCP_TEST_ROOT="$W/unit" $SH "$W/sd/pmcp.sh" "$@" > "$W/out" 2>&1; echo $? > "$W/rc"; }
rc_is() { [ "$(cat "$W/rc")" = "$1" ] && ok "exit $1" || { bad "exit $(cat "$W/rc"), wanted $1"; sed 's/^/       | /' "$W/out" | tail -5; }; }

for SH in "$@"; do
    echo "=== shell: $SH"
    U="$W/unit/mnt/app"

    if [ "${PMCP_TEST_SCOPE:-all}" != speedlimit ]; then
    echo "[1] verify on factory unit"
    fresh_unit; before=$(snapshot "$W/unit")
    run verify; rc_is 0; expect_out "PMCP_VERIFY_OK state=STOCK" "state STOCK"
    [ "$before" = "$(snapshot "$W/unit")" ] && ok "verify wrote nothing to the unit" || bad "verify changed the unit"

    echo "[2] unknown variant refused before any write"
    run install nonsense; rc_is 1; expect_out "PMCP_FAIL=UNKNOWN_VARIANT_nonsense" "unknown variant"
    [ "$before" = "$(snapshot "$W/unit")" ] && ok "unit unchanged" || bad "unit changed"

    echo "[2b] Java actions: no unlock file needed, but they need stage A"
    run java-on nai; rc_is 1; expect_out "JAVA_NEEDS_STAGE_A_STATE_STOCK" "needs stage A"
    grep -q "STAGE_B_LOCKED" "$W/out" && bad "Java still locked" || ok "no lock without an unlock file"
    run java-on nonsense; rc_is 1; expect_out "UNKNOWN_JAVA_PACKAGE_nonsense" "unknown package"
    [ "$before" = "$(snapshot "$W/unit")" ] && ok "unit unchanged" || bad "unit changed"

    echo "[3] install map-clean (stage A: video only)"
    run install map-clean; rc_is 0; expect_out "PMCP_INSTALL_OK stage=A variant=map-clean" "install ok"
    [ "$(h "$U/eso/hmi/lsd/lsd.sh")" = $STOCK_LSD ] && ok "lsd.sh still factory" || bad "lsd.sh changed in stage A"
    [ ! -e "$U/eso/hmi/lsd/jars/NavActiveIgnore.jar" ] && ok "no NAI jar in stage A" || bad "NAI jar in stage A"
    [ "$(h "$U/eso/bin/apps/dio_manager")" = 8c12f6974adf9c8c9eb746e7d033e7fb35a9605e49c31ff2129e8ba938b2633d ] && ok "dio_manager is wrapper" || bad "dio_manager"
    [ "$(h "$U/carplaymaps/stock_first/dio_manager.real")" = 609e42723ab3e36c7be5ceade81e03672ba4acd251f8eeb8b100e074aaf3c250 ] && ok "factory dio saved" || bad "factory dio copy"
    [ "$(h "$U/carplaymaps/core.so")" = c5f4870427d6d24bf78908497beb27e4e881d64374b58c564e7395d809efe2f4 ] && ok "core.so map-clean" || bad "core.so"
    [ -e "$U/carplaymaps/CLUSTER_AUTO_ENABLE" ] && ok "auto-enable marker" || bad "marker"
    ls -a "$U" | grep -q '^\.carplaymaps-new' && bad "staging dir left behind" || ok "no staging leftovers"
    run status; expect_out "Unit state: VIDEO" "state VIDEO"

    echo "[3b] java-on nai, confirm, retry"
    run java-on nai; rc_is 0; expect_out "PMCP_JAVA_ON_OK package=nai set=$NAI" "java-on ok"
    [ "$(h "$U/eso/hmi/lsd/lsd.sh")" = "$LSD_JAVA" ] && ok "lsd.sh has the pmcp block" || bad "lsd.sh"
    [ "$(h "$U/eso/hmi/lsd/jars/NavActiveIgnore.jar")" = $NAI_SHA ] && ok "NAI jar" || bad "NAI jar"
    [ "$(cat "$U/carplaymaps/HMI_BOOT")" = "$NAI NavActiveIgnore.jar" ] && ok "HMI_BOOT = set id + JARs" || bad "HMI_BOOT: $(cat "$U/carplaymaps/HMI_BOOT")"
    run status; expect_out "Unit state: JAVA" "state JAVA"
    run java-on nai; rc_is 1; expect_out "JAVA_PACKAGE_ALREADY_ON_nai" "second java-on refused"
    run java-confirm; rc_is 1; expect_out "NO_TRIAL_BOOT_YET_FOR_SET" "confirm before any boot refused"
    # review 1, finding 2: confirm only during the trial boot of this set
    o=$(unit_boot); [ "$o" = "boot=trial set=$NAI jars=/X/lsd/jars/NavActiveIgnore.jar" ] && ok "boot 1: trial" || bad "boot 1: $o"
    o=$(unit_boot); [ "$o" = "boot=no set=$NAI jars=" ] && ok "boot 2 without confirm: factory" || bad "boot 2: $o"
    run java-confirm; rc_is 1; expect_out "NOT_IN_TRIAL_BOOT_OF_THIS_SET" "confirm on the factory boot after an unconfirmed trial refused"
    o=$(unit_boot); [ "$o" = "boot=no set=$NAI jars=" ] && ok "still factory (nothing confirmed)" || bad "boot 3: $o"
    run java-retry; rc_is 0; [ ! -e "$W/unit/mnt/persist/pmcp/trial.$NAI" ] && ok "retry clears trial" || bad "trial left"
    o=$(unit_boot); [ "$o" = "boot=trial set=$NAI jars=/X/lsd/jars/NavActiveIgnore.jar" ] && ok "after retry: trial again" || bad "retry boot: $o"
    o=$(unit_boot swdl); [ "$o" = "boot=no set= jars=" ] && ok "update mode (RUN_MODE=swdl): block loads nothing" || bad "swdl boot: $o"
    run java-confirm; rc_is 1; expect_out "NOT_IN_TRIAL_BOOT_OF_THIS_SET" "update-mode boot cleared last-boot: no confirm"
    o=$(unit_boot); [ "$o" = "boot=no set=$NAI jars=" ] && ok "trial used up" || bad "boot: $o"
    run java-retry; rc_is 0; o=$(unit_boot); [ "$o" = "boot=trial set=$NAI jars=/X/lsd/jars/NavActiveIgnore.jar" ] && ok "trial again" || bad "boot: $o"
    run java-confirm; rc_is 0; expect_out "PMCP_JAVA_CONFIRM_OK set=$NAI" "confirm during the trial boot"
    [ -e "$W/unit/mnt/persist/pmcp/ok.$NAI" ] && ok "ok marker" || bad "ok marker"
    run java-confirm; rc_is 1; expect_out "SET_ALREADY_CONFIRMED" "second confirm refused"
    o=$(unit_boot); [ "$o" = "boot=yes set=$NAI jars=/X/lsd/jars/NavActiveIgnore.jar" ] && ok "confirmed set loads on every boot" || bad "boot: $o"
    touch "$W/unit/mnt/persist/pmcp/DISABLED"; o=$(unit_boot); [ "$o" = "boot=no set= jars=" ] && ok "DISABLED: factory boot" || bad "DISABLED boot: $o"
    run java-confirm; rc_is 1; expect_out "JAVA_DISABLED_BY_RESCUE_CARD" "confirm refused while DISABLED"
    rm "$W/unit/mnt/persist/pmcp/DISABLED"
    run java-retry; rc_is 0; [ ! -e "$W/unit/mnt/persist/pmcp/trial.$NAI" ] && ok "retry clears trial" || bad "trial left"
    [ -z "$(find "$U" -name '*.pmcp-*')" ] && ok "no .pmcp-* leftovers" || bad "leftovers: $(find "$U" -name '*.pmcp-*')"

    echo "[3c] java-off nai back to stage A, then on again"
    run java-off nai; rc_is 0; expect_out "PMCP_JAVA_OFF_OK" "java-off ok"
    [ "$(h "$U/eso/hmi/lsd/lsd.sh")" = $STOCK_LSD ] && ok "lsd.sh factory again" || bad "lsd.sh"
    [ ! -e "$U/eso/hmi/lsd/jars/NavActiveIgnore.jar" ] && ok "NAI jar removed" || bad "NAI jar left"
    run status; expect_out "Unit state: VIDEO" "back to VIDEO"
    run java-off nai; rc_is 1; expect_out "JAVA_OFF_NEEDS_JAVA_STATE_VIDEO" "java-off on VIDEO refused"
    run java-on nai; rc_is 0
    installed=$(snapshot "$W/unit")

    echo "[3d] two Java packages: order, set id, removing one keeps the other"
    run java-on np; rc_is 0; expect_out "set=$NAI+$NP" "set id for nai+np"
    [ "$(cat "$U/carplaymaps/HMI_BOOT")" = "$NAI+$NP NavActiveIgnore.jar pmcp-np.jar" ] && ok "HMI_BOOT in catalog order" || bad "HMI_BOOT: $(cat "$U/carplaymaps/HMI_BOOT")"
    # regression (2026-10-21): a helper overwrote the caller's "f", so the np JAR was staged as NavActiveIgnore.jar
    [ "$(h "$U/eso/hmi/lsd/jars/NavActiveIgnore.jar")" = $NAI_SHA ] && [ "$(h "$U/eso/hmi/lsd/jars/pmcp-np.jar")" = $NP_SHA ] \
        && ok "each JAR under its own name with its own hash" || bad "JAR names/hashes mixed up"
    run java-off nai; rc_is 0
    [ "$(cat "$U/carplaymaps/HMI_BOOT")" = "$NP pmcp-np.jar" ] && [ ! -e "$U/eso/hmi/lsd/jars/NavActiveIgnore.jar" ] && ok "nai off, np stays" || bad "after nai off"
    [ "$(h "$U/eso/hmi/lsd/lsd.sh")" = "$LSD_JAVA" ] && ok "lsd.sh keeps the block while a package is on" || bad "lsd.sh"
    run status; expect_out "Unit state: JAVA" "still JAVA"
    run java-on nai; rc_is 0; expect_out "set=$NAI+$NP" "same set id again (catalog order)"
    installed=$(snapshot "$W/unit")

    echo "[3e] route guidance (package E): system part and Java package"
    run java-on rg; rc_is 1; expect_out "JAVA_RG_NEEDS_RG_SYSTEM_ON" "java rg refused without RG system"
    run rg-system-on; rc_is 0; expect_out "PMCP_RG_SYSTEM_ON_OK" "rg-system-on ok"
    [ "$(h "$U/armle/lib/dll/ipod-drvr-iap2.so")" = 76926bde9bdf1e06fdfe57fd324bbd8772bcb2a98a58ac444b4822e25a331b48 ] && ok "patched driver active" || bad "driver"
    [ "$(h "$W/unit/mnt/system/etc/mm/iap2.cfg")" = c61407d9c6cd0d2529afedad0c9a120d5da5a504739e273bbb3dbea1e0b9b491 ] && ok "iap2.cfg with [ident]" || bad "cfg"
    run rg-system-on; rc_is 1; expect_out "RG_SYSTEM_ALREADY_on" "second rg-system-on refused"
    run java-on rg; rc_is 0; expect_out "set=$NAI+$NP+$RG" "set with rg"
    run rg-system-off; rc_is 1; expect_out "TURN_OFF_JAVA_PACKAGE_RG_FIRST" "rg-system-off refused while JAR rg on"
    run status; expect_out "Route guidance system: on" "status shows RG on"
    run java-off rg; rc_is 0
    run rg-system-off; rc_is 0; expect_out "PMCP_RG_SYSTEM_OFF_OK" "rg-system-off ok"
    [ "$(h "$U/armle/lib/dll/ipod-drvr-iap2.so")" = 7149a3e75b1b19e89021841759f420a6eced456b6c697a3dd1f0e436abea0b8c ] && ok "factory driver back" || bad "driver not factory"
    [ "$(h "$W/unit/mnt/system/etc/mm/iap2.cfg")" = 1539c79dd415eddeb59ea215c7a9b0ec4be3632fe066be3aefdff11bd19cdf37 ] && ok "factory cfg back" || bad "cfg not factory"
    run rg-system-on; rc_is 0; run java-on rg; rc_is 0

    echo "[3f] packages F (zoom) and G (day/night)"
    run java-on zoom; rc_is 0
    run java-on dn; rc_is 0; expect_out "set=$NAI+$NP+$RG+$ZOOM+$DN" "all five packages in catalog order"
    [ "$(cat "$U/carplaymaps/HMI_BOOT")" = "$NAI+$NP+$RG+$ZOOM+$DN NavActiveIgnore.jar pmcp-np.jar pmcp-rg.jar pmcp-zoom.jar pmcp-dn.jar" ] && ok "HMI_BOOT with five JARs" || bad "HMI_BOOT: $(cat "$U/carplaymaps/HMI_BOOT")"
    run status; expect_out "Unit state: JAVA" "JAVA with five packages (set names parsed from HMI_BOOT)"
    run java-off zoom; rc_is 0; [ ! -e "$U/eso/hmi/lsd/jars/pmcp-zoom.jar" ] && ok "zoom off" || bad "zoom jar left"
    run java-on zoom; rc_is 0
    installed=$(snapshot "$W/unit")

    echo "[4] second install refused"
    run install card-clean; rc_is 1; expect_out "UNIT_NOT_FACTORY_STATE_JAVA" "refused on JAVA"
    [ "$installed" = "$(snapshot "$W/unit")" ] && ok "unit unchanged" || bad "unit changed"

    echo "[5] switch to card-clean"
    run switch card-clean; rc_is 0; expect_out "PMCP_SWITCH_OK variant=card-clean" "switch ok"
    run switch card-clean; rc_is 1; expect_out "SWITCH_ALREADY_card-clean" "same map again: already, nothing done"
    [ "$(h "$U/carplaymaps/core.so")" = a4054ff9f1e7175ef9365e9f51990eb4ed3c58121ccfe4a6651e039e362552ac ] && ok "core.so card-clean" || bad "core.so after switch"
    run status; expect_out "variant card-clean" "status shows variant"

    echo "[6] restore (from JAVA + RG system) returns the exact factory tree, other /mnt/persist data kept"
    run restore; rc_is 0; expect_out "PMCP_RESTORE_OK" "restore ok"
    [ "$before" = "$(snapshot "$W/unit")" ] && ok "unit byte-identical to factory" || { bad "unit differs from factory"; diff <(echo "$before") <(snapshot "$W/unit") | head; }

    echo "[7] restore again refused, nothing changes"
    run restore; rc_is 1; expect_out "RESTORE_NEEDS_PMCP_INSTALL_STATE_STOCK" "refused on STOCK"
    [ "$before" = "$(snapshot "$W/unit")" ] && ok "unit unchanged" || bad "unit changed"

    echo "[8] corrupted payload byte: refused before any write"
    fresh_unit; before=$(snapshot "$W/unit")
    printf 'X' | dd of="$W/sd/payload/common/libCarPlayPairingCore.so" bs=1 seek=4096 conv=notrunc 2>/dev/null
    run install map-clean; rc_is 1; expect_out "HASH_MISMATCH_PAIR_CORE" "corruption detected"
    [ "$before" = "$(snapshot "$W/unit")" ] && ok "unit unchanged" || bad "unit changed"

    echo "[9] corrupted gawk self test: refused"
    fresh_unit
    printf 'Y' | dd of="$W/sd/bin/selftest.bin" bs=1 seek=10 conv=notrunc 2>/dev/null
    run verify; rc_is 1; expect_out "HASH_MISMATCH_SELFTEST" "self test catches it"

    echo "[9b] GEM runs us with a UTF-8 locale (unit 2026-10-23): pmcp.sh forces C, hashes still right"
    fresh_unit
    LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 LC_CTYPE=en_US.UTF-8 run verify; rc_is 0; expect_out "PMCP_VERIFY_OK state=STOCK" "verify ok under UTF-8"
    o=$(LC_ALL=en_US.UTF-8 "$PMCP_TEST_GAWK" -f "$W/sd/bin/sha256.awk" "$W/sd/bin/selftest.bin" 2>/dev/null)
    [ -z "$o" ] && ok "sha256.awk prints no hash when its byte table is broken" || bad "sha256.awk printed '$o' under UTF-8"

    echo "[9c] log not writable (SD read-only in GEM): warning only, actions still run"
    fresh_unit; echo x > "$W/unit/sdlog"
    run install map-clean; rc_is 0; expect_out "PMCP_WARN=SD_LOG_NOT_WRITABLE" "install warns"; expect_out "PMCP_INSTALL_OK" "install still runs"
    fresh_unit; echo x > "$W/unit/sdlog"
    run verify; rc_is 0; expect_out "PMCP_WARN=SD_LOG_NOT_WRITABLE" "verify warns"; expect_out "PMCP_VERIFY_OK" "verify still runs"
    rm -f "$W/unit/sdlog"

    echo "[10] not MU1161 (lsd.jxe size)"
    fresh_unit; rm "$W/unit/ifs/lsd.jxe"; truncate -s 55840541 "$W/unit/ifs/lsd.jxe"
    run install map-clean; rc_is 1; expect_out "NOT_MU1161_LSD_JXE_SIZE_55840541" "size gate"

    echo "[11] modified factory lsd.sh: refused"
    fresh_unit; echo "# local edit" >> "$W/unit/mnt/app/eso/hmi/lsd/lsd.sh"; before=$(snapshot "$W/unit")
    run install map-clean; rc_is 1; expect_out "UNIT_NOT_FACTORY_STATE_UNKNOWN" "unknown state"
    [ "$before" = "$(snapshot "$W/unit")" ] && ok "unit unchanged" || bad "unit changed"

    echo "[12] another mod present (generic CarPlayNavigationPatch.jar): refused"
    fresh_unit; echo x > "$W/unit/mnt/app/eso/hmi/lsd/jars/CarPlayNavigationPatch.jar"; before=$(snapshot "$W/unit")
    run install map-clean; rc_is 1; expect_out "UNIT_NOT_FACTORY_STATE_UNKNOWN" "other mod detected"
    [ "$before" = "$(snapshot "$W/unit")" ] && ok "unit unchanged" || bad "unit changed"

    echo "[13] interrupted state (dio back to factory by hand): PARTIAL, restore completes"
    fresh_unit; factory=$(snapshot "$W/unit")
    run install map-clean; rc_is 0; run java-on nai; rc_is 0
    cp "$BK/eso/bin/apps/dio_manager" "$W/unit/mnt/app/eso/bin/apps/dio_manager"
    run status; expect_out "Unit state: PARTIAL" "PARTIAL detected"
    run install map-clean; rc_is 1; expect_out "UNIT_NOT_FACTORY_STATE_PARTIAL" "install refused on PARTIAL"
    run restore; rc_is 0; expect_out "PMCP_RESTORE_OK" "restore from PARTIAL"
    [ "$factory" = "$(snapshot "$W/unit")" ] && ok "factory tree after PARTIAL restore" || bad "tree differs"

    echo "[13a] rescue-card result (factory lsd.sh, JAR gone, DISABLED): VIDEO, java-on again works, restore completes"
    fresh_unit; factory=$(snapshot "$W/unit")
    run install map-clean-l40; rc_is 0; run java-on nai; rc_is 0
    cp "$BK/eso/hmi/lsd/lsd.sh" "$U/eso/hmi/lsd/lsd.sh"; rm "$U/eso/hmi/lsd/jars/NavActiveIgnore.jar"
    mkdir -p "$W/unit/mnt/persist/pmcp"; touch "$W/unit/mnt/persist/pmcp/DISABLED"
    run status; expect_out "Unit state: VIDEO" "VIDEO after rescue (video still installed)"
    run java-on nai; rc_is 0; [ ! -e "$W/unit/mnt/persist/pmcp/DISABLED" ] && ok "java-on clears DISABLED" || bad "DISABLED left"
    run restore; rc_is 0
    [ "$factory" = "$(snapshot "$W/unit")" ] && ok "factory tree after rescue + restore" || bad "tree differs"

    echo "[13b] interrupted staging leftovers are cleaned on the next install"
    fresh_unit
    mkdir -p "$W/unit/mnt/app/.carplaymaps-new-999/stock_first"; echo junk > "$W/unit/mnt/app/eso/bin/apps/dio_manager.pmcp-new"
    mkdir -p "$W/unit/mnt/app/.carplaymaps-old-998"; mkdir -p "$W/unit/mnt/persist/pmcp"; touch "$W/unit/mnt/persist/pmcp/ok.$NAI"
    run install map-clean; rc_is 0; expect_out "removing leftover" "leftovers removed"
    [ -z "$(find "$W/unit/mnt/app" -name '.carplaymaps-new-*' -o -name '.carplaymaps-old-*' -o -name '*.pmcp-*')" ] && ok "no leftovers" || bad "leftovers remain"
    [ ! -e "$W/unit/mnt/persist/pmcp" ] && ok "old ok/trial markers removed by install" || bad "old markers kept"

    echo "[13d] restore interrupted after carplaymaps was moved away: tool still works"
    fresh_unit; factory=$(snapshot "$W/unit")
    run install map-clean; rc_is 0
    mv "$U/carplaymaps" "$U/.carplaymaps-old-777"; cp "$BK/eso/bin/apps/dio_manager" "$U/eso/bin/apps/dio_manager"
    run status; expect_out "Unit state: STOCK" "STOCK with only a leftover dir"
    run install map-clean; rc_is 0; run restore; rc_is 0
    [ "$factory" = "$(snapshot "$W/unit")" ] && [ -z "$(ls -a "$U" | grep carplaymaps)" ] && ok "factory tree, leftover gone" || bad "tree differs"

    echo "[13e] verify with an unwritable log dir still checks the payload"
    fresh_unit
    printf 'X' | dd of="$W/sd/payload/common/libCarPlayPairingCore.so" bs=1 seek=4096 conv=notrunc 2>/dev/null
    mkdir -p "$W/unit/sdlog"; chmod 500 "$W/unit/sdlog"
    run verify; rc_is 1; expect_out "HASH_MISMATCH_PAIR_CORE" "corruption found without a log dir"
    grep -q "can't create\|cannot create\|Permission denied" "$W/out" && bad "log redirect errors on screen" || ok "no log redirect noise"
    chmod 700 "$W/unit/sdlog"

    echo "[13c] JAR with a wrong hash in the unit: not JAVA, restore still works"
    fresh_unit; factory=$(snapshot "$W/unit")
    run install map-clean; rc_is 0; run java-on nai; rc_is 0
    printf 'Z' | dd of="$U/eso/hmi/lsd/jars/NavActiveIgnore.jar" bs=1 seek=100 conv=notrunc 2>/dev/null
    run status; expect_out "Unit state: PARTIAL" "tampered JAR detected"
    run restore; rc_is 0
    [ "$factory" = "$(snapshot "$W/unit")" ] && ok "factory tree" || bad "tree differs"

    echo "[14] GEM menu: buttons and menu file"
    for m in "$SDB"/pmcp/menu/*.sh; do
        $SH -n "$m" 2>/dev/null || bad "syntax $(basename "$m")"
        if [ "$(basename "$m")" = rglast.sh ]; then
            grep -q '^/bin/ksh /net/mmx/fs/sda0/pmcp/bin/rglast.sh$' "$m" && ! grep -q 'pmcp.sh' "$m" && ok "rglast button runs bin/rglast.sh only" || bad "rglast button"
            continue
        fi
        if [ "$(basename "$m")" = navdiag.sh ]; then
            grep -q '^/bin/ksh /net/mmx/fs/sda0/pmcp/bin/navdiag.sh$' "$m" && ! grep -q 'pmcp.sh' "$m" && ok "navdiag button runs bin/navdiag.sh only" || bad "navdiag button"
            continue
        fi
        if [ "$(basename "$m")" = timeline.sh ]; then
            grep -q '^/bin/ksh /net/mmx/fs/sda0/pmcp/bin/timeline.sh$' "$m" && ! grep -q 'pmcp.sh' "$m" && ok "timeline button runs bin/timeline.sh only" || bad "timeline button"
            continue
        fi
        if [ "$(basename "$m")" = diag.sh ]; then
            grep -q '^/bin/ksh /net/mmx/fs/sda0/pmcp/bin/diag.sh$' "$m" && ! grep -q 'pmcp.sh' "$m" && ok "diag button runs bin/diag.sh only" || bad "diag button"
            continue
        fi
        if [ "$(basename "$m")" = all-on.sh ]; then
            acts=$(sed -n 's/^for A in \(.*\); do$/\1/p' "$m")
            [ "$acts" = "switch_map-square-fps40 rg-system-on_ java-on_nai java-on_np java-on_zoom java-on_dn java-on_rglu" ] && grep -q '^PMCP=/net/mmx/fs/sda0/pmcp/pmcp.sh$' "$m" \
                && ok "all-on button: main map, RG system, then nai np zoom dn rglu" || bad "all-on actions: $acts"
            continue
        fi
        args=$(sed -n 's#^/bin/ksh /net/mmx/fs/sda0/pmcp/pmcp.sh ##p' "$m")
        case "$args" in
            verify|status|restore|java-retry|java-confirm|rg-system-on|rg-system-off|speedlimit-status|"speedlimit-mode turnto"|"speedlimit-mode off"|"install "*|"switch "*|"java-on "*|"java-off "*) ;;
            *) bad "unexpected button command in $(basename "$m"): $args" ;;
        esac
        set -- $args
        case "$1" in
            install|switch) grep -q "^CORE_$2 " <(sed -n "/^MANIFEST='/,/^'/p" "$SDB/pmcp/pmcp.sh") || bad "variant $2 of $(basename "$m") not in manifest" ;;
            java-on|java-off) grep -q "^JAR_$2 " <(sed -n "/^MANIFEST='/,/^'/p" "$SDB/pmcp/pmcp.sh") || bad "package $2 of $(basename "$m") not in manifest" ;;
        esac
    done
    nmenu=$(ls "$SDB"/pmcp/menu/*.sh | wc -l | tr -d ' ')
    nref=$(grep -c '/net/mmx/fs/sda0/pmcp/menu/' "$SDB/esd/Launcher-sda0.esd")
    [ "$nmenu" -gt 20 ] && [ "$nmenu" = "$nref" ] && ok "menu scripts: $nmenu, menu entries: $nref" || bad "menu scripts $nmenu vs entries $nref"
    grep -q "install map-square-fps40$" "$SDB/pmcp/menu/install-map-square-fps40.sh" && grep -q '"2. Install the CarPlay map on the AID"' "$SDB/esd/Launcher-sda0.esd" \
        && ok "main install button is map-square-fps40" || bad "main install button"
    main=$(tr -d '\r' < "$SDB/esd/Launcher-sda0.esd" | sed -n '/^screen pmcp_CarPlay_AID/,/^screen pmcp_advanced/p' | grep -o 'menu/[a-z0-9-]*\.sh' | tr '\n' ' ')
    [ "$main" = "menu/verify.sh menu/install-map-square-fps40.sh menu/all-on.sh menu/java-confirm.sh menu/java-retry.sh menu/status.sh menu/restore.sh " ] \
        && ok "main screen: check, map, all features, confirm, retry, status, restore" || bad "main screen: $main"
    ORIG="$REPO/archives/mib-3.6.0/Launcher-sda0.esd"
    head -c "$(stat -f %z "$ORIG")" "$SDB/esd/Launcher-sda0.esd" | cmp -s - "$ORIG" && ok "M.I.B. menu content unchanged (only appended)" || bad "M.I.B. menu prefix changed"
    for ref in $(grep -o '/net/mmx/fs/sda0/pmcp/menu/[a-z0-9-]*\.sh' "$SDB/esd/Launcher-sda0.esd"); do
        [ -f "$SDB/pmcp/menu/${ref##*/}" ] || bad "menu points to missing ${ref##*/}"
    done
    v=$(sed -n 's/^PMCP_VERSION="\(.*\)"$/\1/p' "$SDB/pmcp/pmcp.sh")
    case "$v" in pmcp-0.3.0-mu1161-791-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ok "version carries a build id: $v" ;; *) bad "version $v" ;; esac
    grep -q "$v" "$SDB/esd/Launcher-sda0.esd" && [ "$(head -1 "$SDB/BUILD-MANIFEST.txt")" = "$v" ] && ok "same id in GEM and BUILD-MANIFEST" || bad "version id mismatch"

    echo "[15] lsd.sh trial boot block, executed over simulated boots"
    B="$W/boot"; rm -rf "$B"; mkdir -p "$B/app/carplaymaps" "$B/persist"
    sed -n '/^# >>> pmcp: CarPlay AID mod/,/^# <<< pmcp/p' "$SDB/pmcp/payload/lsd/lsd.sh" > "$B/pre.sh"
    [ "$(grep -c '' "$B/pre.sh")" -gt 10 ] && ok "block extracted" || bad "block not found"
    [ "$(grep -c '>>> pmcp' "$SDB/pmcp/payload/lsd/lsd.sh")" = 1 ] && ok "exactly one pmcp block (no watcher after J9)" || bad "pmcp block count"
    diff <(cat "$BK/eso/hmi/lsd/lsd.sh") <(sed '/^# >>> pmcp: CarPlay AID mod/,/^# <<< pmcp/d' "$SDB/pmcp/payload/lsd/lsd.sh") >/dev/null \
        && ok "patched lsd.sh = factory + the block only" || bad "lsd.sh differs outside the block"
    # boot [RUN_MODE] -> prints BOOTCLASSPATH
    boot() {
        { echo "BASE_DIR=/ramdisk/hmi; BOOTCLASSPATH=-Xbootclasspath/a:/ifs/lsd.jxe; RUN_MODE=${1:-}"
          sed -e "s#/mnt/app/carplaymaps#$B/app/carplaymaps#g" -e "s#/mnt/persist/pmcp#$B/persist/pmcp#g" "$B/pre.sh"
          echo 'echo "BCP=$BOOTCLASSPATH"; wait'
        } > "$B/run.sh"
        $SH "$B/run.sh" 2>&1
    }
    echo "nai-823adeb0 NavActiveIgnore.jar" > "$B/app/carplaymaps/HMI_BOOT"
    o=$(boot); case "$o" in *"/p:/ramdisk/hmi/lsd/jars/NavActiveIgnore.jar"*) ok "boot 1 (trial) loads the JAR" ;; *) bad "boot 1: $o" ;; esac
    [ "$(cat "$B/persist/pmcp/last-boot")" = "set=nai-823adeb0 use=trial" ] && ok "last-boot says trial" || bad "last-boot: $(cat "$B/persist/pmcp/last-boot")"
    [ ! -e "$B/persist/pmcp/ok.nai-823adeb0" ] && ok "no automatic ok" || bad "ok written without the user"
    o=$(boot); case "$o" in *"/p:"*) bad "unconfirmed trial loaded again: $o" ;; *) ok "boot 2 without confirm is factory" ;; esac
    [ "$(cat "$B/persist/pmcp/last-boot")" = "set=nai-823adeb0 use=no" ] && ok "last-boot says no" || bad "last-boot: $(cat "$B/persist/pmcp/last-boot")"
    touch "$B/persist/pmcp/ok.nai-823adeb0"
    o=$(boot); case "$o" in *NavActiveIgnore*) ok "confirmed set loads" ;; *) bad "confirmed: $o" ;; esac
    o=$(boot swdl); case "$o" in *"/p:"*) bad "update mode loaded JARs: $o" ;; *) ok "RUN_MODE=swdl: factory boot even with ok" ;; esac
    [ ! -e "$B/persist/pmcp/last-boot" ] && ok "update mode removes last-boot" || bad "last-boot left in update mode"
    echo "nai-823adeb0+np-11111111 NavActiveIgnore.jar pmcp-np.jar" > "$B/app/carplaymaps/HMI_BOOT"
    o=$(boot); case "$o" in *"NavActiveIgnore.jar:/ramdisk/hmi/lsd/jars/pmcp-np.jar"*) ok "new set: trial loads both JARs" ;; *) bad "new set trial: $o" ;; esac
    o=$(boot); case "$o" in *"/p:"*) bad "unconfirmed trial loaded again: $o" ;; *) ok "next boot after the unconfirmed trial is factory" ;; esac
    touch "$B/persist/pmcp/DISABLED"; rm -f "$B/persist/pmcp/trial."*
    o=$(boot); case "$o" in *"/p:"*) bad "DISABLED ignored: $o" ;; *) ok "DISABLED (rescue card) gives a factory boot" ;; esac
    [ ! -e "$B/persist/pmcp/last-boot" ] && ok "DISABLED: no last-boot (nothing to confirm)" || bad "last-boot while DISABLED"
    rm -rf "$B/persist/pmcp"; chmod 500 "$B/persist"
    o=$(boot); case "$o" in *"/p:"*) bad "unwritable persist still loaded JARs: $o" ;; *) ok "unwritable /mnt/persist gives a factory boot" ;; esac
    chmod 700 "$B/persist"
    echo "nai-823adeb0" > "$B/app/carplaymaps/HMI_BOOT"
    o=$(boot); case "$o" in *"/p:"*) bad "id without JARs loaded: $o" ;; *) ok "HMI_BOOT without JARs gives a factory boot" ;; esac
    rm -f "$B/app/carplaymaps/HMI_BOOT"
    o=$(boot); case "$o" in *"/p:"*) bad "no HMI_BOOT still loaded: $o" ;; *) ok "no HMI_BOOT gives a factory boot" ;; esac
    echo "[15b] reader start: only with SYSTEM_ON and a loading Java set"
    echo "rg-11111111 pmcp-rg.jar" > "$B/app/carplaymaps/HMI_BOOT"; rm -rf "$B/persist/pmcp"
    mkdir -p "$B/app/carplaymaps/rg"; printf '#!/bin/sh\necho "$@" > %s/reader-started\n' "$B" > "$B/app/carplaymaps/rg/rgi-observer"; chmod 755 "$B/app/carplaymaps/rg/rgi-observer"
    rm -f "$B/reader-started"; boot >/dev/null; sleep 1
    [ ! -e "$B/reader-started" ] && ok "no SYSTEM_ON: reader not started" || bad "reader started without SYSTEM_ON"
    touch "$B/app/carplaymaps/rg/SYSTEM_ON"; rm -rf "$B/persist/pmcp"
    boot >/dev/null; sleep 1
    grep -q "start-live /dev/ipod0/rgi-events /ramdisk/carplay-route-guidance" "$B/reader-started" 2>/dev/null && ok "SYSTEM_ON + trial set: reader started with Tomasz's arguments" || bad "reader not started"
    rm -f "$B/reader-started"; touch "$B/persist/pmcp/DISABLED"; boot >/dev/null; sleep 1
    [ ! -e "$B/reader-started" ] && ok "DISABLED: reader not started" || bad "reader started while DISABLED"
    rm -f "$B/persist/pmcp/DISABLED"

    echo "[16] rescue card script (pmcp-ratunek.sh) against the fake unit"
    RS="${PMCP_RESCUE_SD:-$SDB/../sd-rescue-v2}/pmcp-ratunek/pmcp-ratunek.sh"
    rescue() { # rescue -> runs the rescue as stuff.sh would, then the log step; medium = $W/med
        rm -rf "$W/rr" "$W/med"; mkdir -p "$W/rr/net/rcc/dev/shmem" "$W/med"; ln -s "$W/unit" "$W/rr/net/mmx"
        PMCP_RESCUE_TEST_ROOT="$W/rr" PMCP_RESCUE_TEST_SLEEP=0 $SH "$RS" HW "$W/med" >/dev/null 2>&1
        PMCP_RESCUE_TEST_ROOT="$W/rr" $SH "$RS" --save-log "$W/med" >/dev/null 2>&1
    }
    fresh_unit; factory=$(snapshot "$W/unit")
    rescue
    [ "$factory" = "$(snapshot "$W/unit")" ] && ok "healthy factory unit: nothing changed" || bad "rescue changed a factory unit"
    grep -q "WYNIK=OK" "$W/med/PMCP_RATUNEK_LOG.txt" && tail -1 "$W/med/PMCP_RATUNEK_LOG.txt" | grep -q "PMCP RATUNEK koniec" \
        && ok "log on the card: WYNIK=OK ... koniec" || bad "log missing or incomplete"
    [ -z "$(ls "$W/rr/net/rcc/dev/shmem")" ] && ok "RAM log moved and cleared" || bad "RAM log left"

    fresh_unit; run install map-clean; rc_is 0; run java-on nai; rc_is 0
    rescue
    [ "$(h "$U/eso/hmi/lsd/lsd.sh")" = $STOCK_LSD ] && ok "JAVA unit: factory lsd.sh back" || bad "lsd.sh not restored"
    [ ! -e "$U/eso/hmi/lsd/jars/NavActiveIgnore.jar" ] && ok "JAR removed" || bad "JAR left"
    [ -e "$W/unit/mnt/persist/pmcp/DISABLED" ] && ok "DISABLED written" || bad "no DISABLED"
    [ -e "$U/carplaymaps/core.so" ] && [ "$(h "$U/eso/bin/apps/dio_manager")" = 8c12f6974adf9c8c9eb746e7d033e7fb35a9605e49c31ff2129e8ba938b2633d ] \
        && ok "video part left in place" || bad "video part touched"
    grep -q "WYNIK=OK" "$W/med/PMCP_RATUNEK_LOG.txt" && ok "WYNIK=OK" || bad "no WYNIK=OK"
    run restore; rc_is 0; expect_out "PMCP_RESTORE_OK" "GEM restore after rescue"

    fresh_unit; run install map-clean; rc_is 0; run java-on nai; rc_is 0
    rm "$U/carplaymaps/rollback/lsd.sh"
    rescue
    [ ! -e "$U/eso/hmi/lsd/jars/NavActiveIgnore.jar" ] && [ -e "$W/unit/mnt/persist/pmcp/DISABLED" ] && ok "no factory copy: JAR removed + DISABLED" || bad "fallback failed"
    grep -q "WYNIK=NIEPEWNY" "$W/med/PMCP_RATUNEK_LOG.txt" && ok "honest WYNIK=NIEPEWNY when lsd.sh still has our block" || bad "should be NIEPEWNY"

    fresh_unit; run install map-clean; rc_is 0; run rg-system-on; rc_is 0; run java-on rg; rc_is 0
    mkdir -p "$W/unit/mnt/persist/pmcp"; echo "set=$RG use=trial" > "$W/unit/mnt/persist/pmcp/last-boot"
    rescue
    [ "$(h "$U/armle/lib/dll/ipod-drvr-iap2.so")" = 7149a3e75b1b19e89021841759f420a6eced456b6c697a3dd1f0e436abea0b8c ] && ok "RG: factory iAP2 driver back" || bad "driver not restored"
    [ "$(h "$W/unit/mnt/system/etc/mm/iap2.cfg")" = 1539c79dd415eddeb59ea215c7a9b0ec4be3632fe066be3aefdff11bd19cdf37 ] && ok "RG: factory iap2.cfg back" || bad "cfg not restored"
    [ ! -e "$U/carplaymaps/rg/SYSTEM_ON" ] && [ ! -e "$W/unit/mnt/persist/pmcp/last-boot" ] && ok "SYSTEM_ON and last-boot removed" || bad "SYSTEM_ON/last-boot left"
    grep -q "WYNIK=OK" "$W/med/PMCP_RATUNEK_LOG.txt" && ok "WYNIK=OK" || bad "no WYNIK=OK"
    run java-confirm; rc_is 1; expect_out "JAVA_NEEDS\|JAVA_CONFIRM_NEEDS_JAVA_STATE\|NOT_IN_TRIAL\|DISABLED" "no confirm after a rescue"
    run restore; rc_is 0; expect_out "PMCP_RESTORE_OK" "GEM restore after an RG rescue"

    fresh_unit; run install map-clean; rc_is 0; run java-on nai; rc_is 0
    rm "$U/eso/hmi/lsd/lsd.sh"; rm "$U/carplaymaps/rollback/lsd.sh"
    rescue
    grep -q "WYNIK=NIEPEWNY" "$W/med/PMCP_RATUNEK_LOG.txt" && ok "lsd.sh missing: WYNIK=NIEPEWNY, not OK" || bad "missing lsd.sh reported OK"

    echo "[17] main screen button 3: install all features (the real menu script, one set, one trial)"
    allon() {
        sed -e "s#/bin/ksh \$PMCP#$SH $W/sd/pmcp.sh#" "$W/sd/menu/all-on.sh" > "$W/all-on.sh"
        PMCP_TEST_ROOT="$W/unit" $SH "$W/all-on.sh" > "$W/out" 2>&1; echo $? > "$W/rc"
    }
    fresh_unit; factory=$(snapshot "$W/unit")
    allon; rc_is 0; expect_out "PMCP_FAIL=ALL_ON_STOPPED_AT_switch_map-square-fps40" "without the map (stage A): stops at the first step"
    [ "$factory" = "$(snapshot "$W/unit")" ] && ok "without the map: unit unchanged" || bad "all-on without stage A changed the unit"
    run install map-square-fps40; rc_is 0
    allon; rc_is 0; expect_out "PMCP_ALL_ON_OK" "all features on"; expect_out "PMCP_RG_SYSTEM_ON_OK" "RG system on"
    ALL="nai-$(jsha nai | cut -c1-8)+np-$(jsha np | cut -c1-8)+zoom-$(jsha zoom | cut -c1-8)+dn-$(jsha dn | cut -c1-8)+rglu-$(jsha rglu | cut -c1-8)"
    [ "$(cut -d' ' -f1 "$U/carplaymaps/HMI_BOOT")" = "$ALL" ] && ok "one set with all five packages" || bad "set: $(cat "$U/carplaymaps/HMI_BOOT")"
    [ -e "$U/carplaymaps/rg/SYSTEM_ON" ] && ok "RG system marker" || bad "no SYSTEM_ON"
    o=$(unit_boot); case "$o" in "boot=trial set=$ALL jars="*pmcp-rglu.jar) ok "next start: one trial with all JARs" ;; *) bad "boot: $o" ;; esac
    run java-confirm; rc_is 0; expect_out "PMCP_JAVA_CONFIRM_OK set=$ALL" "one confirm for everything"
    allon; expect_out "everything was already on, nothing changed" "second press: nothing to do"
    run restore; rc_is 0; run verify; expect_out "PMCP_VERIFY_OK state=STOCK" "remove everything: factory state"
    [ "$(h "$W/unit/mnt/system/etc/mm/iap2.cfg")" = 1539c79dd415eddeb59ea215c7a9b0ec4be3632fe066be3aefdff11bd19cdf37 ] && ok "factory iap2.cfg back" || bad "cfg after restore"
    # update an older install (earlier card: map-square at 30 fps, rg without lanes, all confirmed) with the same button
    run install map-square; rc_is 0; run rg-system-on; rc_is 0
    for n in nai np rg zoom dn; do run java-on $n; rc_is 0; done
    mkdir -p "$W/unit/mnt/persist/pmcp"; read s rest < "$U/carplaymaps/HMI_BOOT"; touch "$W/unit/mnt/persist/pmcp/ok.$s"
    allon; rc_is 0; expect_out "PMCP_SWITCH_OK variant=map-square-fps40" "update: main map switched"
    expect_out "PMCP_JAVA_ON_OK package=rglu" "update: lanes instead of rg"; expect_out "PMCP_ALL_ON_OK" "update done"
    [ "$(cat "$U/carplaymaps/VARIANT")" = map-square-fps40 ] && ok "update: variant map-square-fps40" || bad "variant $(cat "$U/carplaymaps/VARIANT")"
    UPD="nai-$(jsha nai | cut -c1-8)+np-$(jsha np | cut -c1-8)+zoom-$(jsha zoom | cut -c1-8)+dn-$(jsha dn | cut -c1-8)+rglu-$(jsha rglu | cut -c1-8)"
    [ "$(cut -d' ' -f1 "$U/carplaymaps/HMI_BOOT")" = "$UPD" ] && ok "update: set nai np zoom dn rglu" || bad "update set: $(cat "$U/carplaymaps/HMI_BOOT")"
    o=$(unit_boot); case "$o" in "boot=trial set=$UPD jars="*) ok "update: next start is a trial" ;; *) bad "update boot: $o" ;; esac
    run restore; rc_is 0

    echo "[20] start timeline button (fake pidin/sloginfo; real script, host awk)"
    mkdir -p "$W/tl/bin"
    cat > "$W/tl/bin/pidin" <<'PEOF'
#!/bin/sh
case "$1" in
info) echo "CPU:ARM Release:6.5.0  FreeMem:200MB/1024MB BootTime:Oct 29 07:59:58 2026" ;;
times) echo "     pid name                       start time        utime        stime"
  if [ -n "$TL_NOSEC" ]; then echo "       1 procnto                    Oct 29 07:59   1s 2s"; echo "  401433 dio_manager                Oct 29 08:00   1s 2s"
  else echo "       1 procnto                    Oct 29 07:59:58      1s     2s"
       echo "   12300 smartphone_integrator      Oct 29 08:00:11      1s     2s"
       echo "  401433 dio_manager                Oct 29 08:00:23      1s     2s"
       echo "  401990 carplay-cluster-supervisor Oct 29 08:00:24      1s     2s"
       echo "  455000 navigation                 Oct 29 08:00:57      1s     2s"
       echo "  455111 unrelated-proc             Oct 29 08:01:00      1s     2s"; fi ;;
esac
PEOF
    printf '#!/bin/sh\necho "Oct 29 08:01:02  5 14 0 navi: map ready"\n' > "$W/tl/bin/sloginfo"
    chmod 755 "$W/tl/bin/pidin" "$W/tl/bin/sloginfo"
    sed -e "s#^export PATH=.*#export PATH=$W/tl/bin:/bin:/usr/bin#" -e "s#^AWK=.*#AWK=$PMCP_TEST_GAWK#" "$SDB/pmcp/bin/timeline.sh" > "$W/tl/t.sh"
    $SH "$W/tl/t.sh" > "$W/out" 2>&1
    mkdir -p "$W/tl/rd"
    echo "t_us=21437000 event=oem-most-release value1=0 value2=0" > "$W/tl/rd/carplay-cluster-supervisor.log"
    echo "launch=carplay-maps-video-only" > "$W/tl/rd/carplaymaps-launcher.log"
    PMCP_RAMDISK="$W/tl/rd" $SH "$W/tl/t.sh" > "$W/out" 2>&1
    expect_out "PMCP_TIMELINE_DONE" "timeline runs to the end"
    expect_out "^   21.4  event=oem-most-release" "supervisor event in seconds since unit start"
    expect_out "launch=carplay-maps-video-only" "launcher log shown"
    expect_out "^   25  401433 dio_manager" "dio_manager at +25 s"
    expect_out "^   59  455000 navigation" "navigation at +59 s"
    grep -q unrelated "$W/out" && bad "unrelated process listed" || ok "only the relevant processes"
    expect_out "navi: map ready" "system log line"
    TL_NOSEC=1 $SH "$W/tl/t.sh" > "$W/out" 2>&1
    expect_out "no start time with seconds; raw lines" "no seconds: raw lines instead of wrong numbers"

    echo "[21] RG last maneuver button (synthetic mailbox: route, U-turn without junction, right turn, U-turn by angle, lanes)"
    mkdir -p "$W/rgm"
    echo "52474d31010000005f0100000900000001000000000000000000000000000000524749310100000040810000000000000700000005000000050000000000000000000000000000000000000000000000000000000000000000000000000000000100000001521300070000000000000000060000000100050001010008000d000300040200000002522300070000000000000000060000000100060001000300050003040005000800000d000447c582c3b3776e6100030000000252210007000000000000000006000000010006000100040005000302000500080000050009000006000b005a0400000002521c000700000000000000000600000001000600010005000500030400050009000006000bff560500000004523c000700000000000000000600000001000600010005001500020006000000000005000100000600020000001b0002000600000001000500010200060002ff4c00060003ff4c" | xxd -r -p > "$W/rgm/latest.bin"
    echo "RG status=live polls=1" > "$W/rgm/status.txt"
    sed -e "s#^AWK=.*#AWK=$PMCP_TEST_GAWK#" "$SDB/pmcp/bin/rglast.sh" > "$W/rgm/t.sh"
    PMCP_RG_MAILBOX="$W/rgm" $SH "$W/rgm/t.sh" > "$W/out" 2>&1
    expect_out "PMCP_RGLAST_DONE" "rglast runs to the end"
    expect_out "route state=1 next maneuver idx=3" "route message: state and next maneuver"
    expect_out "idx=3 type=4 side=0 junction=- angle=- -> arrow 0 0 (junction missing" "U-turn without junction: no arrow (shown why)"
    expect_out "idx=4 type=2 side=0 junction=0 angle=90 -> arrow 13 turn" "right turn: arrow"
    expect_out "idx=5 type=4 side=- junction=0 angle=-170 -> arrow 25 64" "U-turn by signed angle"
    expect_out "lanes idx=5 \[pos=0 st=0 a=0/0|0\] \[pos=1 st=2 a=-180/128|114 hl=-180/128|114\]" "lanes: positions, status, angle -> direction byte"
    PMCP_RG_MAILBOX="$W/none" $SH "$W/rgm/t.sh" > "$W/out" 2>&1
    expect_out "no $W/none/latest.bin" "no mailbox: says so"

    echo "[19] lanes: rglu replaces rg (same classes), trial, back to rg, RG system guard; removed packages refused"
    RGLU=$(jid rglu)
    fresh_unit; run install map-square-fps40; rc_is 0
    run java-on rglu; rc_is 1; expect_out "JAVA_RG_NEEDS_RG_SYSTEM_ON" "lanes need the RG system"
    run rg-system-on; rc_is 0; run java-on nai; rc_is 0; run java-on rg; rc_is 0
    mkdir -p "$W/unit/mnt/persist/pmcp"; read s rest < "$U/carplaymaps/HMI_BOOT"; touch "$W/unit/mnt/persist/pmcp/ok.$s"
    run java-on rglu; rc_is 0; expect_out "rg replaced by rglu" "rglu swaps rg out"
    [ "$(cat "$U/carplaymaps/HMI_BOOT")" = "$NAI+$RGLU NavActiveIgnore.jar pmcp-rglu.jar" ] && ok "set: nai + rglu" || bad "set $(cat "$U/carplaymaps/HMI_BOOT")"
    [ ! -e "$U/eso/hmi/lsd/jars/pmcp-rg.jar" ] && [ "$(h "$U/eso/hmi/lsd/jars/pmcp-rglu.jar")" = "$(jsha rglu)" ] && ok "pmcp-rg.jar removed, pmcp-rglu.jar in place" || bad "JARs after swap"
    o=$(unit_boot); [ "$o" = "boot=trial set=$NAI+$RGLU jars=/X/lsd/jars/NavActiveIgnore.jar:/X/lsd/jars/pmcp-rglu.jar" ] && ok "lanes: new trial boot" || bad "boot: $o"
    run status; expect_out "Unit state: JAVA" "state JAVA with rglu"
    run rg-system-off; rc_is 1; expect_out "TURN_OFF_JAVA_PACKAGE_RG_FIRST" "RG system stays while rglu is on"
    run java-on rglu; rc_is 1; expect_out "JAVA_PACKAGE_ALREADY_ON_rglu" "second rglu refused"
    run java-on rg; rc_is 0; expect_out "rglu replaced by rg" "back to rg"
    [ "$(cat "$U/carplaymaps/HMI_BOOT")" = "$NAI+$RG NavActiveIgnore.jar pmcp-rg.jar" ] && ok "set: nai + rg again" || bad "set $(cat "$U/carplaymaps/HMI_BOOT")"
    o=$(unit_boot); [ "$o" = "boot=yes set=$NAI+$RG jars=/X/lsd/jars/NavActiveIgnore.jar:/X/lsd/jars/pmcp-rg.jar" ] && ok "earlier confirmed rg set loads at once" || bad "boot: $o"
    for gone in rgl dn2 kf kf4; do
        run java-on $gone; rc_is 1; expect_out "UNKNOWN_JAVA_PACKAGE_$gone" "$gone not shipped"
    done
    run java-off rg; rc_is 0; run rg-system-off; rc_is 0
    run restore; rc_is 0; run verify; expect_out "PMCP_VERIFY_OK state=STOCK" "restore after lanes: factory"

    fi
    echo "[22] optional native speed-limit reader: confirmed opt-in, persistent mode, disable and removal"
    fresh_unit
    SLP="$W/unit/mnt/persist/pmcp"; SLM="$SLP/native-speedlimit-mode"
    SLL="$W/unit/ramdisk/pmcp-speedlimit.lock"
    before=$(snapshot "$W/unit")
    run speedlimit-status; rc_is 0; expect_out "Saved native speed-limit mode: off (default)" "absent mode defaults off"
    [ "$before" = "$(snapshot "$W/unit")" ] && ok "reader status is read-only" || bad "reader status changed files"
    run speedlimit-mode off; rc_is 0
    [ ! -e "$SLP" ] && ok "disable on factory unit creates no configuration" || bad "disable created persist files"
    mkdir -p "$SLP"
    printf street > "$SLM"
    run speedlimit-status; rc_is 0; expect_out "mode: invalid (reader output is off)" "mode without final LF reported invalid"
    printf 'street\n\n' > "$SLM"
    run speedlimit-status; rc_is 0; expect_out "mode: invalid (reader output is off)" "mode with an extra LF reported invalid"
    printf 'street\n' > "$SLM"
    run speedlimit-status; rc_is 0; expect_out "mode: street" "exact current-road mode reported valid"
    printf 'turnto\n' > "$SLM"
    run speedlimit-status; rc_is 0; expect_out "mode: turnto" "exact next-road mode reported valid"
    printf 'off\n' > "$SLM"
    run speedlimit-status; rc_is 0; expect_out "mode: off" "exact disabled mode reported valid"
    run speedlimit-mode unknown; rc_is 1; expect_out "UNKNOWN_SPEEDLIMIT_MODE" "unknown mode refused"
    run speedlimit-mode turnto; rc_is 1; expect_out "SPEEDLIMIT_NEEDS_JAVA_STATE_STOCK" "enable needs Java install"
    run install map-square; rc_is 0; run java-on nai; rc_is 0
    run speedlimit-mode turnto; rc_is 1; expect_out "SPEEDLIMIT_PACKAGE_NOT_INSTALLED" "enable needs sl package"
    mkdir -p "$SLP"; echo turnto > "$SLM"
    run java-on sl; rc_is 0; expect_out "PMCP_JAVA_ON_OK package=sl" "install optional reader"
    [ ! -e "$SLM" ] && ok "install clears stale mode to off" || bad "reader installed with stale active mode"
    read slset sljars < "$U/carplaymaps/HMI_BOOT"
    slboot=$(cat "$U/carplaymaps/HMI_BOOT")
    run speedlimit-mode turnto; rc_is 1; expect_out "SPEEDLIMIT_CONFIRM_JAVA_SET_FIRST" "enable before trial refused"
    unit_boot > /dev/null
    run speedlimit-mode turnto; rc_is 1; expect_out "SPEEDLIMIT_CONFIRM_JAVA_SET_FIRST" "unconfirmed running trial refused"
    run java-confirm; rc_is 0
    run speedlimit-mode turnto; rc_is 0; expect_out "PMCP_SPEEDLIMIT_MODE_OK mode=turnto" "confirmed running trial can enable"
    [ "$(cat "$SLM")" = turnto ] && [ "$slboot" = "$(cat "$U/carplaymaps/HMI_BOOT")" ] \
        && ok "mode saved without changing Java set" || bad "mode or Java set changed incorrectly"
    unit_boot > /dev/null
    [ "$(cat "$SLM")" = turnto ] && ok "mode survives a confirmed boot" || bad "mode lost at reboot"
    run speedlimit-mode street; rc_is 0
    [ "$(cat "$SLM")" = street ] && ok "CLI can select current-road text" || bad "street mode not saved"
    echo "set=$slset use=no" > "$SLP/last-boot"
    run speedlimit-mode turnto; rc_is 1; expect_out "SPEEDLIMIT_NOT_RUNNING_THIS_SET" "fallback cannot enable despite old ok marker"
    [ "$(cat "$SLM")" = street ] && ok "failed enable preserves saved mode" || bad "failed enable changed mode"
    echo "set=other use=yes" > "$SLP/last-boot"
    run speedlimit-mode turnto; rc_is 1; expect_out "SPEEDLIMIT_NOT_RUNNING_THIS_SET" "stale other-set boot cannot enable"
    echo "set=$slset use=yes" > "$SLP/last-boot"
    touch "$SLP/DISABLED"
    run speedlimit-mode turnto; rc_is 1; expect_out "JAVA_DISABLED_BY_RESCUE_CARD" "rescue-disabled set cannot enable"
    # Disable must still work when the card, firmware and running-set checks all fail.
    echo corrupt > "$W/sd/bin/selftest.bin"
    truncate -s 1 "$W/unit/ifs/lsd.jxe"
    run speedlimit-mode off; rc_is 0; expect_out "PMCP_SPEEDLIMIT_MODE_OK mode=off" "disable bypasses card and firmware checks"
    [ "$(cat "$SLM")" = off ] && ok "fallback disable is persistent" || bad "fallback disable failed"
    printf 'PMCP_NATIVE_SPEEDLIMIT\nvalue=70\n' > "$W/unit/ramdisk/pmcp-speedlimit.state"
    before=$(snapshot "$W/unit")
    run speedlimit-status; rc_is 0; expect_out "value=70" "status shows reader snapshot even during fallback"
    [ "$before" = "$(snapshot "$W/unit")" ] && ok "snapshot viewing is read-only" || bad "snapshot viewer changed files"
    cp "$SDB/pmcp/bin/selftest.bin" "$W/sd/bin/selftest.bin"
    truncate -s 55830309 "$W/unit/ifs/lsd.jxe"
    rm -f "$SLP/DISABLED"
    run speedlimit-mode turnto; rc_is 0
    mkdir "$SLL"; echo owner > "$SLL/owner"
    run speedlimit-mode off; rc_is 1; expect_out "SPEEDLIMIT_LOCK_BUSY" "competing mode action refused"
    [ "$(cat "$SLM")" = turnto ] && [ "$(cat "$SLL/owner")" = owner ] && ok "loser preserves owner's lock and mode" || bad "loser changed lock or mode"
    run java-off sl; rc_is 1; expect_out "SPEEDLIMIT_LOCK_BUSY" "Java removal shares the mode lock"
    rm -rf "$SLL"
    run java-off nai; rc_is 0
    [ "$(cat "$SLM")" = turnto ] && ok "removing another package preserves the mode" || bad "unrelated removal cleared mode"
    run java-off sl; rc_is 0
    [ ! -e "$SLM" ] && [ ! -e "$U/eso/hmi/lsd/jars/pmcp-sl.jar" ] && ok "reader removal clears configuration and jar" || bad "reader removal left state"
    run speedlimit-mode off; rc_is 0
    run java-on sl; rc_is 0; unit_boot > /dev/null; run java-confirm; rc_is 0
    run speedlimit-mode turnto; rc_is 0
    run restore; rc_is 0
    [ ! -e "$SLP" ] && [ ! -e "$SLL" ] && ok "full restore clears mode and lock" || bad "full restore left mode or lock"

done

rm -rf "$W"
echo "FAILED CHECKS: $FAILS"
exit $FAILS
