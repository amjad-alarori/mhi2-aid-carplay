#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# One-command installer: builds both SD cards for the CarPlay map on the AID (VW MHI2 MU1161 + AID 791)
# from your own M.I.B. backup, checks every input and output by SHA-256, runs the host tests and, if you
# want, copies the cards onto SD cards. It never touches the car: changes on the head unit happen only
# later, when you press buttons in the green engineering menu (GEM). See docs/en/09-in-car-guide.md.
#
#   ./install.sh                       interactive (recommended)
#   ./install.sh --backup DIR          M.I.B. backup folder of your unit (the folder with MU1161-lsd.jxe)
#   ./install.sh --no-cards            build only, do not offer to write SD cards
#   ./install.sh --skip-host-tests     skip the installer tests (only if gawk 3.1.5 cannot be built)
#   ./install.sh --help
#
# Works on macOS (Intel and Apple Silicon). Linux works for building; card writing there is manual.
# Everything is logged to logs/install-<date>.log in this folder.

set -Eeuo pipefail
umask 022

PROJ=$(cd "$(dirname "$0")" && pwd)
WS=$(dirname "$PROJ")              # workspace: upstream/ and archives/ live next to this repository
BUILD="$PROJ/build"
TOOLS="$WS/upstream/tools"
TOTAL=11
STEP=0
STEP_TITLE="starting"
CARD_WRITING=no
BACKUP=""
NO_CARDS=no
SKIP_TESTS=no

# ---- pinned inputs (every one is checked before use) --------------------------------------------------------------
MIB_URL="https://github.com/Mr-MIBonk/M.I.B._More-Incredible-Bash/archive/refs/tags/V3.6.0.zip"
MIB_SHA=4bfc6e725b5cc60c3c8c73081609dabfe1a2016b5d8671e2438592e673a98086
MIB_ESD_SHA=22739f7226f36d089e2e0485fe2b6874aba2ee6b7b57c807de7bc25c0fdc9121
ASM_URL="https://repo1.maven.org/maven2/org/ow2/asm"
ASM_SHA_asm=adf46d5e34940bdf148ecdd26a9ee8eea94496a72034ff7141066b3eea5c4e9d
ASM_SHA_asm_tree=62f4b3bc436045c1acb5c3ba2d8ec556ec3369093d7f5d06c747eb04b56d52b1
ASM_SHA_asm_analysis=7bc6bcbc21379948a0c8c467fb0f864206e5b818f6bc0b546872f5c9f941556f
ELF_URL="https://files.pythonhosted.org/packages/py3/p/pyelftools/pyelftools-0.31-py3-none-any.whl"
ELF_SHA=f52de7b3c7e8c64c8abc04a79a1cf37ac5fb0b8a49809827130b858944840607
GAWK_URL="https://ftp.gnu.org/gnu/gawk/gawk-3.1.5.tar.gz"
GAWK_SHA=463dcb9d0ca398b1d4f5a332f6cd9cec56441265fca616f2ea1b44d459e9f0f8
LSD_JAR_SHA=573b603a0b79b6c150d6c4363d5db2f9a1b644b21f81ab4a2329d5cdda0f1576   # jxe2jar_run.py output (fixed timestamps)
CORE_BASE=mod/carplay_maps_vc/omonob/payload/profiles/MU1102/791/core.so
# Files of the unit that the build reads, with the exact firmware they must come from (train MHI2_ER_VWG13_P4512, MU1161)
BACKUP_PINS="MU1161-lsd.jxe 201c2f5c3434c43e77e37544a1d90d43e03ab3ea3802306f865dcdf1400f9a8c
advanced/MU1161-appimg/eso/hmi/lsd/lsd.sh 97bbd4ecb51045b34c2a41955d9f53e1f144d174bff1aa8560e911525808e8d8
advanced/MU1161-appimg/eso/bin/apps/dio_manager 609e42723ab3e36c7be5ceade81e03672ba4acd251f8eeb8b100e074aaf3c250
advanced/MU1161-appimg/armle/lib/dll/ipod-drvr-iap2.so 7149a3e75b1b19e89021841759f420a6eced456b6c697a3dd1f0e436abea0b8c
advanced/MU1161-system/mm/iap2.cfg 1539c79dd415eddeb59ea215c7a9b0ec4be3632fe066be3aefdff11bd19cdf37"

# ---- output helpers ------------------------------------------------------------------------------------------------
LOGDIR="$PROJ/logs"
mkdir -p "$LOGDIR"
LOG="$LOGDIR/install-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

say()  { printf '%s\n' "$*"; }
info() { printf '      %s\n' "$*"; }
ok()   { printf '  [ OK ] %s\n' "$*"; }
warn() { printf '  [WARN] %s\n' "$*"; }
hr()   { say "--------------------------------------------------------------------------------------------"; }

step() {
    STEP=$1; STEP_TITLE=$2; shift 2
    say ""; hr
    say "STEP $STEP of $TOTAL: $STEP_TITLE"
    hr
    for l in "$@"; do info "$l"; done
    say ""
}

die() {
    trap - ERR
    say ""; hr
    say "  [FAIL] STEP $STEP of $TOTAL ($STEP_TITLE) did not pass."
    say "         Reason: $1"
    [ -n "${2:-}" ] && say "         What to do: $2"
    if [ "$CARD_WRITING" = yes ]; then
        say "         The SD card may be incomplete. Do NOT put it in the car. Run ./install.sh again with the same card."
    else
        say "         Nothing was changed in your car or on any SD card."
    fi
    say "         Full log: $LOG"
    hr
    exit 1
}
trap 'die "unexpected error (line $LINENO): $BASH_COMMAND" "send the log file to the project issue tracker"' ERR
trap 'say ""; die "stopped by you (Ctrl+C)" "run ./install.sh again whenever you are ready; finished steps are reused"' INT

# run DESCRIPTION CMD...: show what is done and why, print the command, show its output indented
run() {
    local desc=$1; shift
    info "-> $desc"
    printf '         $'; printf ' %q' "$@"; printf '\n'
    local rc=0
    "$@" 2>&1 | sed 's/^/         | /' || rc=$?
    [ $rc -eq 0 ] || die "$desc failed (exit code $rc)" "read the lines marked '|' above, or the log"
}

# run_long DESCRIPTION CMD...: like run, but the (long) output goes to the log only; the last lines are shown
run_long() {
    local desc=$1; shift
    info "-> $desc"
    printf '         $'; printf ' %q' "$@"; printf '\n'
    info "   (detailed output goes to the log; this can take a few minutes)"
    local out rc=0
    out=$(mktemp "${TMPDIR:-/tmp}/pmcp-install.XXXXXX")
    "$@" > "$out" 2>&1 || rc=$?
    { echo "----- output of: $*"; cat "$out"; echo "----- end (exit $rc)"; } >> "$LOG"
    tail -n 4 "$out" | sed 's/^/         | /'
    rm -f "$out"
    [ $rc -eq 0 ] || die "$desc failed (exit code $rc)" "search the log for 'FAIL' to see which check failed"
}

sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }

check_sha() {   # FILE SHA LABEL
    local got
    [ -f "$1" ] || die "$3 is missing: $1"
    got=$(sha256 "$1")
    [ "$got" = "$2" ] || die "$3 has the wrong SHA-256: $got (expected $2)" "the file is damaged or not the pinned version; delete it and run again"
    ok "$3: SHA-256 matches ${2:0:16}..."
}

ask() {         # ask QUESTION -> REPLY (from the terminal; from standard input when there is none)
    printf '  ?  %s ' "$1"
    if { : < /dev/tty; } 2> /dev/null; then
        IFS= read -r REPLY < /dev/tty || REPLY=""
    else
        IFS= read -r REPLY || die "no answer (no terminal)" "run ./install.sh in Terminal"
    fi
    echo "     (answer: $REPLY)" >> "$LOG"
}

ask_yes() {     # ask_yes QUESTION: continue only on y/yes
    ask "$1 [y/N]"
    case "$REPLY" in y|Y|yes|YES|Yes) return 0 ;; esac
    return 1
}

download() {    # URL DEST SHA LABEL: download once, verify, keep
    if [ -f "$2" ] && [ "$(sha256 "$2")" = "$3" ]; then
        ok "$4 already downloaded and verified"
        return
    fi
    mkdir -p "$(dirname "$2")"
    run "download $4" curl -fsSL --retry 3 -o "$2.part" "$1"
    local got; got=$(sha256 "$2.part")
    if [ "$got" != "$3" ]; then
        rm -f "$2.part"
        die "$4 download has the wrong SHA-256: $got (expected $3)" "try again later; if it persists the file on the server changed - do not continue"
    fi
    mv "$2.part" "$2"
    ok "$4 downloaded, SHA-256 matches ${3:0:16}..."
}

# ---- arguments -----------------------------------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --backup) BACKUP=${2:?--backup needs a folder}; shift 2 ;;
        --no-cards) NO_CARDS=yes; shift ;;
        --skip-host-tests) SKIP_TESTS=yes; shift ;;
        -h|--help) sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) say "unknown option: $1 (see ./install.sh --help)"; exit 2 ;;
    esac
done

say ""
say "============================================================================================"
say "  CarPlay map on the Active Info Display - installer builder"
say "  VW MHI2 Discover Pro MU1161 (train MHI2_ER_VWG13_P4512) + AID 12.3\" part 791"
say "============================================================================================"
say "  Log file: $LOG"

# ---- 1. briefing ---------------------------------------------------------------------------------------------------
step 1 "Safety briefing" \
    "This program runs on your computer only. It never connects to your car." \
    "It builds two SD cards from YOUR unit's M.I.B. backup:" \
    "  card 1 'install': M.I.B. 3.6.0 + the CarPlay-on-AID installer, started by you from the GEM menu" \
    "  card 2 'rescue' : undoes the Java changes by itself if the head unit screen stays black" \
    "Every input and output is checked by SHA-256. On any mismatch it stops and changes nothing." \
    "It never formats or erases a disk. It writes only to: this folder, $WS/upstream," \
    "$WS/archives, and the SD cards you pick by typing their name." \
    "" \
    "This modifies the infotainment of a car, at your own risk. It was tested on one car." \
    "It only works for exactly: MU1161, train MHI2_ER_VWG13_P4512, AID part 791 (12.3\")." \
    "Never cross-flash other firmware to make a unit fit."
ask_yes "Does your car have a Discover Pro MHI2 with the 12.3\" Active Info Display (part ...791)?" \
    || die "this installer is only for MHI2 + AID 791" "see the projects under Credits in README.md for other units"
ask_yes "Have you installed M.I.B. 3.6.0 on the unit and made a backup (docs/en/01-mib-install-backup.md)?" \
    || die "an M.I.B. backup of your unit is required" "follow docs/en/01-mib-install-backup.md, then run ./install.sh again"
ask "Type I ACCEPT to confirm you understand the risk and want to continue:"
[ "$REPLY" = "I ACCEPT" ] || die "not confirmed" "run again and type I ACCEPT (capital letters) when ready"
ok "briefing confirmed"

# ---- 2. computer -------------------------------------------------------------------------------------------------
step 2 "Checking your computer" \
    "Looking for the tools the build needs. Nothing is installed or changed here."
OS=$(uname -s)
case "$OS" in
    Darwin) ok "macOS $(sw_vers -productVersion 2>/dev/null) on $(uname -m)" ;;
    Linux) ok "Linux $(uname -r) on $(uname -m) (building works; card writing will be manual)" ;;
    *) die "unsupported system: $OS" "use macOS or Linux" ;;
esac
missing=""
hint() {
    if [ "$OS" = Darwin ]; then
        case "$1" in
            git|make|cc|xxd) echo "xcode-select --install" ;;
            java|javac|javap) echo "brew install openjdk  (then follow brew's note to link it)" ;;
            python3) echo "brew install python" ;;
            *) echo "brew install $1" ;;
        esac
    else
        case "$1" in
            java|javac|javap) echo "install a JDK 11 or newer, e.g. apt install openjdk-17-jdk-headless" ;;
            cc|make) echo "apt install build-essential" ;;
            shasum) echo "apt install perl" ;;
            xxd) echo "apt install xxd (or vim-common)" ;;
            *) echo "apt install $1" ;;
        esac
    fi
}
for t in git curl python3 java javac javap unzip xxd shasum make cc tar sed ksh; do
    if command -v "$t" > /dev/null 2>&1; then
        ok "found $t: $(command -v "$t")"
    else
        warn "missing $t -> install with: $(hint "$t")"
        missing="$missing $t"
    fi
done
[ -z "$missing" ] || die "missing tools:$missing" "install them with the commands shown above, then run ./install.sh again"
pyv=$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')
python3 -c 'import sys; sys.exit(sys.version_info < (3, 8))' || die "Python $pyv is too old" "install Python 3.8 or newer"
python3 -c 'import venv, ensurepip' 2> /dev/null || die "Python $pyv has no venv/ensurepip module" "$( [ "$OS" = Linux ] && echo 'apt install python3-venv' || echo 'brew install python')"
ok "Python $pyv"
jv=$(javac -version 2>&1 | sed -n 's/^javac \([0-9]*\).*/\1/p')
[ -n "$jv" ] && [ "$jv" -ge 11 ] || die "Java compiler $(javac -version 2>&1) is older than 11" "$(hint javac)"
ok "Java compiler version $jv"
gv=$(git --version | awk '{print $3}')
case "$gv" in 1.*|2.[0-9].*|2.1[0-9].*|2.2[0-4].*) die "git $gv is too old (needs 2.25+)" "$(hint git)" ;; esac
ok "git $gv"
SHELLS="$(command -v ksh)"
command -v mksh > /dev/null 2>&1 && SHELLS="$SHELLS $(command -v mksh)" || info "mksh not found: tests run with ksh only (optional: $(hint mksh))"
free_kb=$(df -Pk "$WS" | awk 'NR==2 {print $4}')
[ "$free_kb" -gt 2000000 ] || die "only $((free_kb / 1024)) MB free in $WS" "free at least 2 GB"
ok "$((free_kb / 1024)) MB free in $WS"

# ---- 3. workspace -------------------------------------------------------------------------------------------------
step 3 "Checking the workspace folder" \
    "The build keeps its downloads next to this repository, in: $WS" \
    "It will create (or reuse after checking) only: upstream/ and archives/ there," \
    "and build/, mib/ and logs/ inside $PROJ."
case "$WS" in
    /|"$HOME"|/Users|/home) die "the repository is directly in $WS" \
        "make a dedicated folder first: mkdir ~/mhi2-workspace && cd ~/mhi2-workspace && git clone <this repository>" ;;
esac
other=$(cd "$WS" && ls -A | grep -v -x -e "$(basename "$PROJ")" -e upstream -e archives -e backup -e .DS_Store | head -5 || true)
if [ -n "$other" ]; then
    warn "the workspace folder also holds other things:"
    printf '%s\n' "$other" | sed 's/^/         /'
    info "They are not touched. A dedicated, otherwise empty folder is recommended."
fi
ask_yes "Use $WS as the workspace?" || die "workspace not confirmed" "move this repository into a dedicated folder and run again"
ok "workspace: $WS"

# ---- 4. backup -----------------------------------------------------------------------------------------------------
step 4 "Checking your M.I.B. backup (read-only)" \
    "The build uses files from your own unit, so it can only produce exactly what was tested." \
    "It needs the M.I.B. backup folder, named like MU1161-MHI2_ER_VWG13_P4512-..., which holds" \
    "MU1161-lsd.jxe and advanced/ ('app.img to folder' in the M.I.B. backup menu). Nothing in it is changed."
if [ -z "$BACKUP" ]; then
    cands=$( { ls -d "$WS"/backup/MU1161* /Volumes/*/backup/MU1161* /media/*/*/backup/MU1161* /run/media/*/*/backup/MU1161* 2>/dev/null || true; } | while read -r d; do if [ -f "$d/MU1161-lsd.jxe" ]; then echo "$d"; fi; done)
    if [ -n "$cands" ]; then
        info "Backups found:"
        i=0; while read -r d; do i=$((i + 1)); info "  $i) $d"; done <<< "$cands"
        ask "Pick a number, or type the path of the backup folder:"
        case "$REPLY" in
            ''|*[!0-9]*) BACKUP=$REPLY ;;
            *) BACKUP=$(sed -n "${REPLY}p" <<< "$cands") ;;
        esac
    else
        info "No backup found automatically (looked in $WS/backup/ and on mounted cards)."
        ask "Type (or drag into this window) the path of the backup folder:"
        BACKUP=$REPLY
    fi
fi
BACKUP=$(printf '%s' "$BACKUP" | sed -e "s/^[\"']//" -e "s/[\"'] *$//" -e 's/ *$//' -e 's/\\ / /g')
[ -n "$BACKUP" ] && [ -d "$BACKUP" ] || die "backup folder not found: '$BACKUP'" "give the folder that contains MU1161-lsd.jxe"
BACKUP=$(cd "$BACKUP" && pwd)
info "backup: $BACKUP"
if [ -f "$BACKUP/MU1161-version.txt" ]; then
    train=$(sed -n "s/^Current train = '\(.*\)'.*/\1/p" "$BACKUP/MU1161-version.txt" | tr -d '\r')
    mu=$(sed -n "s/^MainUnit version = '\(.*\)'.*/\1/p" "$BACKUP/MU1161-version.txt" | tr -d '\r')
    info "unit reports: train=$train, main unit version=$mu"
    [ "$train" = MHI2_ER_VWG13_P4512 ] && [ "$mu" = 1161 ] \
        || die "this unit runs $train / MU$mu, not MHI2_ER_VWG13_P4512 / MU1161" "this build only supports MU1161 P4512; never cross-flash to make it fit"
    ok "firmware train MHI2_ER_VWG13_P4512, MU1161"
else
    warn "MU1161-version.txt not in the backup; the file hashes below decide"
fi
[ -d "$BACKUP/advanced/MU1161-appimg" ] || die "advanced/MU1161-appimg is missing in the backup" \
    "make the backup again with the 'app.img to folder' option (docs/en/01-mib-install-backup.md)"
while read -r rel want; do
    check_sha "$BACKUP/$rel" "$want" "backup $rel"
done <<< "$BACKUP_PINS"
ls "$BACKUP"/advanced/MU1161-appimg/eso/hmi/lsd/jars/*.jar > /dev/null 2>&1 || die "backup has no eso/hmi/lsd/jars/*.jar" "make the backup again"
ok "your unit's files are exactly the tested MU1161 firmware"
export PMCP_BACKUP="$BACKUP"

# ---- 5. dependencies -----------------------------------------------------------------------------------------------
step 5 "Downloading the pinned sources and tools" \
    "Everything is fetched at an exact commit or with an exact SHA-256, so the result is reproducible." \
    "Git repositories are fetched sparsely (only the folders the build reads)."
clone_pinned() {    # NAME URL COMMIT DEST SPARSE_PATH...
    local name=$1 url=$2 commit=$3 dest=$4; shift 4
    if [ -e "$dest" ]; then
        local head; head=$(git -C "$dest" rev-parse HEAD 2>/dev/null || echo none)
        [ "$head" = "$commit" ] || die "$dest exists but is at commit $head, not $commit" "move that folder away (do not delete your own work) and run again"
        [ -z "$(git -C "$dest" status --porcelain --untracked-files=no)" ] || die "$dest has local changes" "move that folder away and run again"
        ok "$name: already at pinned commit ${commit:0:10}, no local changes"
        return
    fi
    mkdir -p "$(dirname "$dest")"
    run "fetch $name (sparse clone)" git clone --quiet --filter=blob:none --no-checkout --sparse "$url" "$dest"
    run "limit $name to the folders the build reads" git -C "$dest" sparse-checkout set "$@"
    run "check out $name at the pinned commit" git -C "$dest" -c advice.detachedHead=false checkout --quiet --detach "$commit"
    [ "$(git -C "$dest" rev-parse HEAD)" = "$commit" ] || die "$name is not at $commit after checkout"
    ok "$name at pinned commit ${commit:0:10}"
}
clone_pinned "M.I.B. (base core.so)" https://github.com/Mr-MIBonk/M.I.B._More-Incredible-Bash \
    3a2526a386f54ec7f49bbc32984ef7edb1106d33 "$WS/upstream/mib" "$(dirname "$CORE_BASE")"
clone_pinned "mathsls (MU1161/791 binaries)" https://github.com/mathsls/MHI2-Carplay-Maps \
    cdd576b02a282853bd764a82b9a94e6474f39052 "$WS/upstream/mathsls" MU1161/791_AID12.3/payload
clone_pinned "tomasz-twardzicki (route guidance)" https://github.com/tomasz-twardzicki/MHI2-Carplay-Maps \
    024dd159c4d99890c9b17ea500325e4d2b5dcbde "$WS/upstream/tomasz" MU1427/route-guidance \
    releases/CarPlay_Maps_VC_Full_Toolboxes/VW_SKODA_ALL_CarPlay_Maps_VC_FULL_MQB_Toolbox_V4/Custom/carplay_native_guidance
clone_pinned "luka-dev/jxe2jar (HMI converter)" https://github.com/luka-dev/jxe2jar \
    9eeb45bbf14bf8afe3452c7be96a4d1f0206a286 "$TOOLS/jxe2jar/repo" src

download "$MIB_URL" "$PROJ/mib/downloads/MIB_V3.6.0.zip" "$MIB_SHA" "M.I.B. 3.6.0 zip"
ESD="$WS/archives/mib-3.6.0/Launcher-sda0.esd"
if [ ! -f "$ESD" ]; then
    mkdir -p "$(dirname "$ESD")"
    run "extract the M.I.B. GEM menu file" unzip -q -j "$PROJ/mib/downloads/MIB_V3.6.0.zip" \
        "M.I.B._More-Incredible-Bash-3.6.0/esd/Launcher-sda0.esd" -d "$(dirname "$ESD")"
fi
check_sha "$ESD" "$MIB_ESD_SHA" "M.I.B. 3.6.0 GEM menu"

ASM_DIR="$TOOLS/asm-9.7"
for a in asm asm-tree asm-analysis; do
    v="ASM_SHA_$(echo "$a" | tr - _)"
    download "$ASM_URL/$a/9.7/$a-9.7.jar" "$ASM_DIR/$a-9.7.jar" "${!v}" "ASM $a-9.7.jar"
done
export ASM_DIR

VENV="$TOOLS/venv-elftools"
if [ -x "$VENV/bin/python" ] && [ "$("$VENV/bin/python" -I -c 'import elftools; print(elftools.__version__)' 2>/dev/null)" = 0.31 ]; then
    ok "pyelftools 0.31 environment already present"
else
    [ ! -e "$VENV" ] || die "$VENV exists but does not hold pyelftools 0.31" "move that folder away and run again"
    download "$ELF_URL" "$TOOLS/downloads/pyelftools-0.31-py3-none-any.whl" "$ELF_SHA" "pyelftools 0.31"
    run "create a private Python environment for pyelftools" python3 -m venv "$VENV"
    run "install pyelftools 0.31 from the verified file (offline)" "$VENV/bin/python" -m pip install --quiet --no-index --no-deps \
        "$TOOLS/downloads/pyelftools-0.31-py3-none-any.whl"
    ok "pyelftools 0.31 ready"
fi

GAWK="$TOOLS/gawk-3.1.5/gawk"
if [ "$SKIP_TESTS" = yes ]; then
    warn "--skip-host-tests: gawk 3.1.5 not needed"
elif [ -x "$GAWK" ] && "$GAWK" --version 2>/dev/null | head -1 | grep -q 'GNU Awk 3.1.5'; then
    ok "gawk 3.1.5 (same awk as on the head unit, for the tests) already built"
else
    info "The installer tests need GNU awk 3.1.5, the same version as on the head unit; building it from source."
    download "$GAWK_URL" "$TOOLS/gawk-3.1.5/gawk-3.1.5.tar.gz" "$GAWK_SHA" "gawk 3.1.5 source"
    GSRC=$(mktemp -d "$TOOLS/gawk-3.1.5/src.XXXX")
    run "unpack gawk 3.1.5" tar xzf "$TOOLS/gawk-3.1.5/gawk-3.1.5.tar.gz" -C "$GSRC"
    GCF="-O1 -std=gnu89 -w -Wno-error=implicit-function-declaration -Wno-error=implicit-int -Wno-error=int-conversion -Wno-error=incompatible-pointer-types"
    cc $GCF -x c -c -o /dev/null /dev/null 2>/dev/null || GCF="-O1 -std=gnu89 -w"
    gb=""
    (cd "$GSRC/gawk-3.1.5" && ./configure --disable-nls CFLAGS="$GCF" > ../configure.log 2>&1) || {
        gb="--build=arm-apple-darwin"; [ "$OS" = Linux ] && gb="--build=$(uname -m)-unknown-linux-gnu"
        (cd "$GSRC/gawk-3.1.5" && ./configure --disable-nls $gb CFLAGS="$GCF" > ../configure.log 2>&1)
    } || { cat "$GSRC/configure.log" >> "$LOG"; die "gawk 3.1.5 configure failed" "run again with --skip-host-tests (the build is still checked by hashes), and report the log"; }
    run_long "compile gawk 3.1.5" make -C "$GSRC/gawk-3.1.5" gawk
    cp "$GSRC/gawk-3.1.5/gawk" "$GAWK"
    "$GAWK" --version | head -1 | grep -q 'GNU Awk 3.1.5' || die "the built gawk does not report version 3.1.5"
    rm -rf "$GSRC"
    ok "gawk 3.1.5 built: $GAWK"
fi

# ---- 6. HMI conversion -------------------------------------------------------------------------------------------
step 6 "Converting your unit's HMI (lsd.jxe -> lsd.jar)" \
    "The Java packages are compiled against your unit's own classes. The converted file must be" \
    "byte-identical to the tested one (SHA-256 ${LSD_JAR_SHA:0:16}...)."
if [ -e "$BUILD" ]; then
    old="$PROJ/build.previous-$(date +%Y%m%d-%H%M%S)"
    mv "$BUILD" "$old"
    warn "an earlier build folder was moved to $old (nothing deleted; remove it yourself when not needed)"
fi
mkdir -p "$BUILD"
LSD_JAR="$BUILD/lsd-mu1161.jar"
run_long "convert MU1161-lsd.jxe (about 55 MB)" python3 -I "$PROJ/scripts/jxe2jar_run.py" "$TOOLS/jxe2jar/repo/src" "$BACKUP/MU1161-lsd.jxe" "$LSD_JAR"
check_sha "$LSD_JAR" "$LSD_JAR_SHA" "converted lsd.jar"

# ---- 7. components ------------------------------------------------------------------------------------------------
step 7 "Building the components" \
    "core.so map variants, NavActiveIgnore, now playing, zoom and day/night, route guidance." \
    "Every component checks its inputs, verifies its patched bytes and runs its own host test."
run "core.so map layout variants (from the pinned omonob base)" python3 -I "$PROJ/patches/mu1161/build_core.py" \
    "$WS/upstream/mib/$CORE_BASE" "$BUILD/mu1161-791/tuning"
run_long "NavActiveIgnore.jar" bash "$PROJ/navactiveignore/build.sh" MU1161 "$LSD_JAR" "$BUILD/nai-mu1161-v2"
run_long "pmcp-np.jar (track title and artist)" bash "$PROJ/nowplaying/build.sh" "$LSD_JAR" "$BUILD/np-mu1161-v2"
run_long "pmcp-zoom.jar and pmcp-dn.jar (zoom, day/night)" bash "$PROJ/hmiextras/build.sh" "$LSD_JAR" "$BUILD/extras-mu1161-v2"
run_long "route guidance (pmcp-rg.jar with lanes, distance bar, street and maneuver fallbacks; iAP2 driver, iap2.cfg, reader)" \
    bash "$PROJ/rg/build.sh" "$LSD_JAR" "$BUILD/rg-mu1161-lanes-uturn-asf-m" lanes-uturn-asf-m
ok "all components built"

# ---- 8. installer and card folders ------------------------------------------------------------------------------
step 8 "Assembling the installer and the two card folders" \
    "build_sd.py accepts each component only if its SHA-256 equals the tested build." \
    "card 1 = the unchanged M.I.B. 3.6.0 tree + the installer (nothing starts by itself)" \
    "card 2 = rescue card (starts by itself in update mode; keep it out of the car until needed)"
run_long "assemble the installer (pmcp/ and the GEM menu screen)" python3 -I "$PROJ/installer/build_sd.py" "$BUILD/sd"
VERSION=$(head -1 "$BUILD/sd/BUILD-MANIFEST.txt")
ok "installer version: $VERSION"
run "card 1: install" python3 -I "$PROJ/installer/build_card_install.py" "$BUILD/sd" "$BUILD/card1-install"
run "card 2: rescue" python3 -I "$PROJ/installer/build_rescue.py" "$BUILD/card2-rescue"
ok "card folders: $BUILD/card1-install and $BUILD/card2-rescue"

# ---- 9. tests -----------------------------------------------------------------------------------------------------
step 9 "Testing the installer and the rescue card on a simulated unit" \
    "Every GEM action and the rescue card run against a copy of your unit's files (from your backup)," \
    "with the head unit's shell and awk versions, including power loss at every write step."
if [ "$SKIP_TESTS" = yes ]; then
    warn "host tests skipped (--skip-host-tests)"
else
    export PMCP_RESCUE_SD="$BUILD/card2-rescue"
    # shellcheck disable=SC2086
    run_long "installer and rescue card tests (shells: $SHELLS)" bash "$PROJ/installer/test/run_tests.sh" "$BUILD/sd" $SHELLS
    ok "installer and rescue card tests: 0 failures"
    info "The power-loss test kills the installer on purpose; 'Killed' lines below are expected."
    run_long "power-loss tests (ksh)" bash "$PROJ/installer/test/fault_inject.sh" "$BUILD/sd" "$(command -v ksh)"
    ok "power-loss tests: 0 failures"
fi

# ---- 10. SD cards -------------------------------------------------------------------------------------------------
step 10 "Writing the SD cards (optional)" \
    "Two SEPARATE cards, FAT32 (in Disk Utility: 'MS-DOS (FAT)', scheme 'Master Boot Record')." \
    "This program never formats: format the cards yourself first if needed." \
    "Card 1 may already hold M.I.B. 3.6.0 and your backup/ folder; those are kept. Card 2 must be empty."

vol_field() { diskutil info "$1" 2>/dev/null | sed -n "s/^ *$2: *//p" | head -1; }

write_card() {     # KIND SRC LABEL
    local kind=$1 src=$2 label=$3 vol dev
    if [ "$OS" != Darwin ]; then
        info "Linux: copy the CONTENTS of $src to an empty FAT32 card ($label), then check it with:"
        info "  python3 -I $PROJ/installer/write_card.py verify $kind $src /path/to/card"
        return
    fi
    say ""
    info "Mounted volumes:"
    local found=no
    for v in /Volumes/*; do
        [ -d "$v" ] || continue
        [ "$(vol_field "$v" 'Mount Point')" = / ] && continue
        found=yes
        info "  $(basename "$v"): $(vol_field "$v" 'File System Personality'), $(vol_field "$v" 'Disk Size' | cut -d'(' -f1), $(vol_field "$v" 'Protocol'), $(vol_field "$v" 'Device Location')"
    done
    [ $found = yes ] || info "  (none - insert the card and wait until it appears in Finder)"
    ask "Type the NAME of the card for $label (or press Enter to skip):"
    [ -n "$REPLY" ] || { warn "$label: skipped"; return; }
    vol="/Volumes/$REPLY"
    [ -d "$vol" ] || die "no volume named '$REPLY'" "check the name in Finder and run again"
    dev=$(vol_field "$vol" 'Device Identifier')
    local fs rem loc proto
    fs=$(vol_field "$vol" 'File System Personality'); rem=$(vol_field "$vol" 'Removable Media')
    loc=$(vol_field "$vol" 'Device Location'); proto=$(vol_field "$vol" 'Protocol')
    info "$REPLY: device $dev, $fs, $proto, $loc, $rem"
    [ "$(vol_field "$vol" 'Mount Point')" != / ] || die "$REPLY is your system disk"
    case "$fs" in *FAT32*) ;; *) die "$REPLY is '$fs', not FAT32" "format the card in Disk Utility as MS-DOS (FAT) with Master Boot Record (this erases it)";; esac
    case "$rem/$loc/$proto" in Removable/*|*/External/*|*/*/"Disk Image") ;; *)
        die "$REPLY does not look like a removable card ($rem, $loc, $proto)" "use an SD card in a card reader" ;; esac
    if [ "$kind" = rescue ] && [ -n "${CARD1_DISK:-}" ] && [ "${dev%s*}" = "$CARD1_DISK" ]; then
        die "the rescue card must be a different card than card 1"
    fi
    run "check whether $REPLY can take $label (read-only)" python3 -I "$PROJ/installer/write_card.py" check "$kind" "$src" "$vol"
    ask "Write $label to '$REPLY' now? Type the card name again to confirm:"
    [ "$REPLY" = "$(basename "$vol")" ] || { warn "$label: not confirmed, skipped"; return; }
    CARD_WRITING=yes
    run "write $label" python3 -I "$PROJ/installer/write_card.py" write "$kind" "$src" "$vol"
    run "unmount the card (so the check below reads the card itself, not the computer's cache)" diskutil unmount "$vol"
    run "mount the card again" diskutil mount "$dev"
    vol=$(vol_field "$dev" 'Mount Point')
    run "verify every file on the card" python3 -I "$PROJ/installer/write_card.py" verify "$kind" "$src" "$vol"
    CARD_WRITING=no
    [ "$kind" = install ] && CARD1_DISK=${dev%s*}
    run "eject the card" diskutil eject "$vol"
    ok "$label written, verified and ejected. Label it: $([ "$kind" = install ] && echo 'MIB / INSTALL' || echo 'RESCUE - DO NOT INSERT')"
}

if [ "$NO_CARDS" = yes ]; then
    warn "--no-cards: copy the folders yourself (see the next step)"
else
    info "Insert card 1 (install) now."
    write_card install "$BUILD/card1-install" "card 1 (install)"
    info "Now insert card 2 (rescue), a different, empty card."
    write_card rescue "$BUILD/card2-rescue" "card 2 (rescue)"
fi

# ---- 11. next steps -----------------------------------------------------------------------------------------------
step 11 "Done - what to do next in the car" \
    "Your build: $VERSION (GEM shows this in the header; any other version means stop)."
NEXT="$BUILD/NEXT-STEPS.txt"
cat > "$NEXT" << EOF
CarPlay map on the AID - next steps (build $VERSION)
Full guide with photos: docs/en/09-in-car-guide.md

Cards
  card 1 (install): contents of build/card1-install  -> nothing starts by itself
  card 2 (rescue) : contents of build/card2-rescue   -> starts by itself; keep it OUT of the car until needed
  Only one card in the unit at a time, always slot SD1. Power: charger or engine running. Ignition ON.

On the rescue card log (PMCP_RESCUE_LOG.txt): RESULT=OK = the rescue worked

In the car, one visit, card 1 only (photograph the screen after every action):
  1. Card 1 in SD1. Hold MENU ~10 s -> =>M.I.B.<= -> pmcp_CarPlay_AID. Header = $VERSION.
     "1. Check card and unit (read-only)" -> expect PMCP_VERIFY_OK state=STOCK.
  2. "2. Install the CarPlay map on the AID" -> PMCP_INSTALL_OK. Restart (volume knob ~10 s).
     Start guidance in Apple/Google Maps, AID view = navigation map. No picture: iPhone Settings > General >
     CarPlay > this car > Forget This Car, reconnect. No map: stop here.
  3. "3. Install all features: arrows, ETA, zoom, song title" -> PMCP_ALL_ON_OK. Restart: trial start.
  4. Test. Everything works: "4. Confirm: everything works" in the SAME start. Then restart once more: done.
     Without Confirm the next start is factory again (safe). Black screen: hold the volume knob ~10 s.
  Undo everything: "Remove everything (back to factory files)".
Card 2 (rescue) only for an emergency after Confirm: insert it, wait, remove it when the normal screen is back.
It disarms itself after use; re-arm it on a computer (rename _Swdlautorun.txt to Swdlautorun.txt).

Log of this build: $LOG
EOF
sed 's/^/      /' "$NEXT"
say ""
ok "these steps are saved in $NEXT"
ok "finished. Log: $LOG"
