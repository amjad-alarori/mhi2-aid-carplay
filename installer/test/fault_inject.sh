#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Power-loss test for pmcp.sh (from review 1's harness). For every action of a full chain
# (install ... restore), kill pmcp.sh right before its 1st, 2nd, 3rd ... mutating command on the unit (mv/rm/touch,
# fault_inject.inc), then check what the NEXT BOOT would do and that the tool can still recover:
#   - boot: the lsd.sh block of the killed tree is executed; if it loads JARs without a trial (use=yes), HMI_BOOT must
#     be the one from before the action or a set the user confirmed earlier (nothing untested may load permanently);
#   - state is STOCK/VIDEO/JAVA/PARTIAL (never UNKNOWN), and restore (or nothing, for STOCK) gives the factory tree.
#   fault_inject.sh SD_BUILD_DIR SHELL
set -u
SDB=$(cd "${1:?sd build dir}" && pwd); SH=${2:?shell}
REPO=$(cd "$(dirname "$0")/../../.." && pwd)
H=$(cd "$(dirname "$0")" && pwd)
BK="${PMCP_BACKUP:-$REPO/backup/MU1161}/advanced/MU1161-appimg"
export PMCP_TEST_GAWK="$REPO/upstream/tools/gawk-3.1.5/gawk"
W=$(mktemp -d /tmp/pmcp-fi.XXXX)
U="$W/unit/mnt/app"
FAILS=0; CASES=0
bad() { echo "  FAIL $*"; FAILS=$((FAILS+1)); }

fresh_unit() {
    rm -rf "$W/unit" "$W/sd"
    mkdir -p "$W/unit/ifs" "$U/eso/bin/apps" "$U/eso/hmi/lsd/jars" "$U/armle/usr/bin" "$W/unit/mnt/persist/etc" \
        "$U/armle/lib/dll" "$W/unit/mnt/system/etc/mm"
    cp "$BK/armle/lib/dll/ipod-drvr-iap2.so" "$U/armle/lib/dll/"
    cp "$BK/../MU1161-system/mm/iap2.cfg" "$W/unit/mnt/system/etc/mm/"
    mkfile -n 55830309 "$W/unit/ifs/lsd.jxe" 2>/dev/null || truncate -s 55830309 "$W/unit/ifs/lsd.jxe"
    cp "$BK/eso/bin/apps/dio_manager" "$U/eso/bin/apps/dio_manager"
    cp "$BK/eso/bin/apps/gal" "$U/eso/bin/apps/gal"
    cp "$BK/eso/hmi/lsd/lsd.sh" "$U/eso/hmi/lsd/lsd.sh"
    cp "$BK/eso/hmi/lsd/jars/"* "$U/eso/hmi/lsd/jars/"
    echo "factory persist content" > "$W/unit/mnt/persist/etc/ffs3.2ver"
    cp -R "$SDB/pmcp" "$W/sd"
    awk -v inc="$H/fault_inject.inc" '{print} /^unset LD_PRELOAD$/ && !done {while ((getline l < inc) > 0) print l; done=1}' \
        "$W/sd/pmcp.sh" > "$W/sd/pmcp-fi.sh"
}
snapshot() { (cd "$W/unit" && find . -type f ! -path './sdlog/*' -exec shasum -a 256 {} \; | sort -k2); }
# "v13:ACTION": the v1.3.0 release card (an earlier install that rg-update / java-update bring to this card); not a target
V13="${PMCP_V13_SD:-$SDB/../sd-v1.3.0}/pmcp/pmcp.sh"
# "exp:ACTION": the last experimental card (Android Auto), likewise only to prepare a unit
EXP="${PMCP_EXP_SD:-$SDB/../sd-ab9fb348}/pmcp/pmcp.sh"
[ -f "$V13" ] && [ -f "$EXP" ] || { echo "earlier cards missing: $V13 $EXP"; exit 99; }
run() { case "$1" in v13:*) _a=${1#v13:}; shift; PMCP_TEST_ROOT="$W/unit" $SH "$V13" $_a "$@" > "$W/out" 2>&1 ;;
                     exp:*) _a=${1#exp:}; shift; PMCP_TEST_ROOT="$W/unit" $SH "$EXP" $_a "$@" > "$W/out" 2>&1 ;;
                     *) PMCP_TEST_ROOT="$W/unit" $SH "$W/sd/pmcp.sh" "$@" > "$W/out" 2>&1 ;; esac; }
runfi() { rm -f "$W/cnt"; PMCP_KILL_AT=$1 PMCP_FI_CNT=$W/cnt PMCP_FI_LOG=$W/filog PMCP_TEST_ROOT="$W/unit" $SH "$W/sd/pmcp-fi.sh" "${@:2}" > "$W/outfi" 2>&1; }
# the user confirmed the set during its trial boot
confirm_set() {
    [ -s "$U/carplaymaps/HMI_BOOT" ] || return 0
    mkdir -p "$W/unit/mnt/persist/pmcp"; read s rest < "$U/carplaymaps/HMI_BOOT"
    touch "$W/unit/mnt/persist/pmcp/trial.$s" "$W/unit/mnt/persist/pmcp/ok.$s"
}
bootsim() {
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

CHAIN=("v13:install map-clean" "v13:java-on nai" "v13:rg-system-on" "v13:java-on rglu" "rg-update" "java-update" "java-on np" \
       "switch map-clean-l40" "java-off np" "java-off rg" "rg-system-off" "java-off nai" "restore" \
       "install map-square-fps40" "rg-system-on" "java-on rg" "java-on zoom" "restore" \
       "exp:install map-clean" "exp:aa-on gamma" "aa-remove" "exp:aa-on most" "restore")
fresh_unit; FACTORY=$(snapshot)
for ((t=0; t<${#CHAIN[@]}; t++)); do
    target=${CHAIN[$t]}
    case "$target" in v13:*|exp:*) continue ;; esac
    fresh_unit
    for ((p=0; p<t; p++)); do
        run ${CHAIN[$p]}; grep -q "_OK" "$W/out" || { echo "prep ${CHAIN[$p]} failed"; cat "$W/out"; exit 99; }; confirm_set
    done
    rm -rf "$W/tpl"; cp -Rp "$W/unit" "$W/tpl"
    before_boot=$(cat "$W/tpl/mnt/app/carplaymaps/HMI_BOOT" 2>/dev/null)
    n=1
    while :; do
        rm -rf "$W/unit"; cp -Rp "$W/tpl" "$W/unit"
        runfi $n $target
        if ! grep -q "FI_KILLED" "$W/outfi" && grep -q "_OK" "$W/outfi"; then
            echo "[$target] completes after $((n-1)) mutating commands"; break
        fi
        CASES=$((CASES+1))
        killed=$(tail -1 "$W/filog" 2>/dev/null | sed "s#$W##g")
        bs=$(bootsim)
        now_boot=$(cat "$U/carplaymaps/HMI_BOOT" 2>/dev/null)
        # use=yes is fine for the set from before the action, or for a set the user had confirmed before (its own ok
        # marker existed before the action, e.g. java-off back to an earlier set); anything else loads untested
        now_id=${now_boot%% *}
        if [ "$bs" = "boot=yes" ] && [ "$now_boot" != "$before_boot" ] && [ ! -e "$W/tpl/mnt/persist/pmcp/ok.$now_id" ]; then
            bad "[$target] kill@$n ($killed): untested set loads without a trial: '$now_boot' (was '$before_boot')"
        fi
        if [ "$target" = rg-update ]; then
            # an interrupted update is finished by running it again
            run rg-update; grep -q "PMCP_RG_UPDATE_OK\|RG_UPDATE_ALREADY_CURRENT" "$W/out" && run status && grep -q "Route guidance system: on" "$W/out" \
                || bad "[$target] kill@$n ($killed): rg-update again did not finish: $(grep PMCP_FAIL "$W/out")"
        fi
        if [ "$target" = java-update ]; then
            # an interrupted Java update is finished by running it again
            run java-update; grep -q "PMCP_JAVA_UPDATE_OK\|JAVA_UPDATE_ALREADY_CURRENT" "$W/out" && run status && grep -q "Unit state: JAVA" "$W/out" \
                && ! grep -q "earlier card\|unused JAR" "$W/out" \
                || bad "[$target] kill@$n ($killed): java-update again did not finish: $(grep PMCP_FAIL "$W/out")"
        fi
        # Android Auto must never be left dead: gal is the factory file, or a wrapper with a verified factory copy
        GALH=$(shasum -a 256 < "$U/eso/bin/apps/gal" | cut -d' ' -f1)
        if [ "$GALH" != 3b422d47a16dd473dc426aa3a88348bfee0da0e7585993a3566df242339346f9 ] \
            && [ "$(shasum -a 256 < "$U/carplaymaps/aa/gal.real" 2>/dev/null | cut -d' ' -f1)" != 3b422d47a16dd473dc426aa3a88348bfee0da0e7585993a3566df242339346f9 ]; then
            bad "[$target] kill@$n ($killed): gal is not factory and no verified factory copy (Android Auto dead)"
        fi
        # experimental AA left over (killed aa-remove, or restore before its AA step finished): aa-remove finishes it
        if run status && grep -q "Android Auto of an experimental card is installed" "$W/out"; then
            run aa-remove; grep -q PMCP_AA_REMOVE_OK "$W/out" || bad "[$target] kill@$n ($killed): aa-remove again did not finish: $(grep PMCP_FAIL "$W/out")"
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
