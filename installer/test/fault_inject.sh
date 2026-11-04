#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Power-loss test for pmcp.sh (from review 1's harness). For every action of a full chain
# (install ... restore), kill pmcp.sh right before its 1st, 2nd, 3rd ... mutating command on the unit (mv/rm/touch,
# fault_inject.inc), then check what the NEXT BOOT would do and that the tool can still recover:
#   - boot: the lsd.sh block of the killed tree is executed; if it loads JARs without a trial (use=yes), HMI_BOOT must
#     be the one from before the action or a set the user confirmed earlier (nothing untested may load permanently);
#   - state is STOCK/VIDEO/JAVA/PARTIAL (never UNKNOWN), and restore (or nothing, for STOCK) gives the factory tree.
#   fault_inject.sh SD_BUILD_DIR SHELL
#   PMCP_FAULT_SCOPE=speedlimit runs native-limit actions with one retained companion package.
set -u
SDB=$(cd "${1:?sd build dir}" && pwd); SH=${2:?shell}
REPO=$(cd "$(dirname "$0")/../../.." && pwd)
H=$(cd "$(dirname "$0")" && pwd)
BK="${PMCP_BACKUP:-$REPO/backup/MU1161}/advanced/MU1161-appimg"
export PMCP_TEST_GAWK="${PMCP_TEST_GAWK:-$REPO/upstream/tools/gawk-3.1.5/gawk}"
W=$(mktemp -d /tmp/pmcp-fi.XXXX)
U="$W/unit/mnt/app"
FAILS=0; CASES=0
bad() { echo "  FAIL $*"; FAILS=$((FAILS+1)); }

fresh_unit() {
    rm -rf "$W/unit" "$W/sd"
    mkdir -p "$W/unit/ifs" "$W/unit/ramdisk" "$U/eso/bin/apps" "$U/eso/hmi/lsd/jars" "$U/armle/usr/bin" "$W/unit/mnt/persist/etc" \
        "$U/armle/lib/dll" "$W/unit/mnt/system/etc/mm"
    cp "$BK/armle/lib/dll/ipod-drvr-iap2.so" "$U/armle/lib/dll/"
    cp "$BK/../MU1161-system/mm/iap2.cfg" "$W/unit/mnt/system/etc/mm/"
    mkfile -n 55830309 "$W/unit/ifs/lsd.jxe" 2>/dev/null || truncate -s 55830309 "$W/unit/ifs/lsd.jxe"
    cp "$BK/eso/bin/apps/dio_manager" "$U/eso/bin/apps/dio_manager"
    cp "$BK/eso/hmi/lsd/lsd.sh" "$U/eso/hmi/lsd/lsd.sh"
    cp "$BK/eso/hmi/lsd/jars/"* "$U/eso/hmi/lsd/jars/"
    echo "factory persist content" > "$W/unit/mnt/persist/etc/ffs3.2ver"
    cp -R "$SDB/pmcp" "$W/sd"
    awk -v inc="$H/fault_inject.inc" '{print} /^unset LD_PRELOAD$/ && !done {while ((getline l < inc) > 0) print l; done=1}' \
        "$W/sd/pmcp.sh" > "$W/sd/pmcp-fi.sh"
}
snapshot() { (cd "$W/unit" && find . -type f ! -path './sdlog/*' -exec shasum -a 256 {} \; | sort -k2); }
mode_digest() {
    _mode_file="$W/unit/mnt/persist/pmcp/native-speedlimit-mode"
    if [ -e "$_mode_file" ]; then shasum -a 256 < "$_mode_file" | cut -d' ' -f1; else echo absent; fi
}
run() { PMCP_TEST_ROOT="$W/unit" $SH "$W/sd/pmcp.sh" "$@" > "$W/out" 2>&1; }
runfi() { rm -f "$W/cnt"; PMCP_KILL_AT=$1 PMCP_FI_CNT=$W/cnt PMCP_FI_LOG=$W/filog PMCP_TEST_ROOT="$W/unit" $SH "$W/sd/pmcp-fi.sh" "${@:2}" > "$W/outfi" 2>&1; }
# the user confirmed the set during its trial boot
confirm_set() {
    [ -s "$U/carplaymaps/HMI_BOOT" ] || return 0
    mkdir -p "$W/unit/mnt/persist/pmcp"; read s rest < "$U/carplaymaps/HMI_BOOT"
    touch "$W/unit/mnt/persist/pmcp/trial.$s" "$W/unit/mnt/persist/pmcp/ok.$s"
    echo "set=$s use=yes" > "$W/unit/mnt/persist/pmcp/last-boot"
}
bootsim() {
    # A physical power loss clears MMX RAM, including a lock left by kill -9 in this harness.
    rm -rf "$W/unit/ramdisk"; mkdir -p "$W/unit/ramdisk"
    rm -rf "$W/bs"; cp -Rp "$W/unit" "$W/bs"; L="$W/bs/mnt/app/eso/hmi/lsd/lsd.sh"
    grep -q '>>> pmcp' "$L" || { echo "boot=factory-lsd"; return; }
    { echo 'BASE_DIR=/X; BOOTCLASSPATH=-Xbootclasspath/a:/ifs/lsd.jxe; RUN_MODE='
      sed -n '/^# >>> pmcp: CarPlay AID mod/,/^# <<< pmcp/p' "$L" \
        | sed -e "s#/mnt/app/carplaymaps#$W/bs/mnt/app/carplaymaps#g" -e "s#/mnt/persist/pmcp#$W/bs/mnt/persist/pmcp#g" \
              -e "s|( .PMCP_DIR/rg/rgi-observer.*) &|:|"
      echo 'echo "boot=$PMCP_USE"'; } > "$W/bs.sh"
    $SH "$W/bs.sh" 2>&1 | tail -1
}
state() { run status; sed -n 's/^Unit state: //p' "$W/out"; }

CHAIN=("install map-clean" "java-on nai" "java-on np" "rg-system-on" "java-on rg" "java-on rglu" "java-on sl" \
       "speedlimit-mode turnto" "speedlimit-mode off" "switch map-clean-l40" "java-off sl" \
       "java-off np" "java-off rglu" "rg-system-off" "java-off nai" "restore")
if [ "${PMCP_FAULT_SCOPE:-all}" = speedlimit ]; then
    CHAIN=("install map-clean" "java-on nai" "java-on sl" "speedlimit-mode turnto" "speedlimit-mode off" "java-off sl" "restore")
fi
fresh_unit; FACTORY=$(snapshot)
for ((t=0; t<${#CHAIN[@]}; t++)); do
    target=${CHAIN[$t]}
    if [ "${PMCP_FAULT_SCOPE:-all}" = speedlimit ]; then
        case "$target" in "java-on sl"|"java-off sl"|"speedlimit-mode "*) ;; *) continue ;; esac
    fi
    fresh_unit
    for ((p=0; p<t; p++)); do
        run ${CHAIN[$p]}; grep -q "_OK" "$W/out" || { echo "prep ${CHAIN[$p]} failed"; cat "$W/out"; exit 99; }; confirm_set
    done
    rm -rf "$W/tpl"; cp -Rp "$W/unit" "$W/tpl"
    before_boot=$(cat "$W/tpl/mnt/app/carplaymaps/HMI_BOOT" 2>/dev/null)
    before_mode=$(mode_digest)
    case "$target" in
        "speedlimit-mode "*) after_mode=$(printf '%s\n' "${target#speedlimit-mode }" | shasum -a 256 | cut -d' ' -f1) ;;
        *) after_mode="$before_mode" ;;
    esac
    n=1
    while :; do
        rm -rf "$W/unit"; cp -Rp "$W/tpl" "$W/unit"
        runfi $n $target
        if ! grep -q "FI_KILLED" "$W/outfi" && grep -q "_OK" "$W/outfi"; then
            echo "[$target] completes after $((n-1)) mutating commands"; break
        fi
        CASES=$((CASES+1))
        killed=$(tail -1 "$W/filog" 2>/dev/null | sed "s#$W##g")
        case "$target" in
            "speedlimit-mode "*)
                now_mode=$(mode_digest)
                [ "$now_mode" = "$before_mode" ] || [ "$now_mode" = "$after_mode" ] \
                    || bad "[$target] kill@$n ($killed): partially published mode file"
                ;;
        esac
        bs=$(bootsim)
        now_boot=$(cat "$U/carplaymaps/HMI_BOOT" 2>/dev/null)
        # use=yes is fine for the set from before the action, or for a set the user had confirmed before (its own ok
        # marker existed before the action, e.g. java-off back to an earlier set); anything else loads untested
        now_id=${now_boot%% *}
        if [ "$bs" = "boot=yes" ] && [ "$now_boot" != "$before_boot" ] && [ ! -e "$W/tpl/mnt/persist/pmcp/ok.$now_id" ]; then
            bad "[$target] kill@$n ($killed): untested set loads without a trial: '$now_boot' (was '$before_boot')"
        fi
        st=$(state)
        case "$st" in
            PARTIAL|VIDEO|JAVA)
                run restore
                if ! grep -q PMCP_RESTORE_OK "$W/out"; then bad "[$target] kill@$n ($killed): restore failed: $(grep PMCP_FAIL "$W/out")"
                elif [ "$(snapshot)" != "$FACTORY" ]; then bad "[$target] kill@$n ($killed): restore left a non-factory tree"
                else res="restore->factory"; fi ;;
            STOCK)
                run install map-clean && run restore
                [ "$(snapshot)" = "$FACTORY" ] && res="STOCK (install+restore ok)" || bad "[$target] kill@$n ($killed): STOCK, tree differs after install+restore" ;;
            *) bad "[$target] kill@$n ($killed): state '$st' (tool locked out)"; res="" ;;
        esac
        echo "[$target] kill@$n ($killed) [$bs] state=$st ${res:-}"
        res=""
        n=$((n+1))
        [ $n -gt 80 ] && { bad "[$target] more than 80 mutating commands"; break; }
    done
done
rm -rf "$W"
echo "FAULT CASES: $CASES, FAILED: $FAILS"
exit $FAILS
