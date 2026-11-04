#!/usr/bin/env python3
"""Assemble the pmcp tree for the M.I.B. SD card (SD#2) from pinned inputs. Host tool, read-only on inputs.

  python3 -I build_sd.py OUT_DIR

Every input is checked against its SHA-256 and size before use; the output must not exist yet.
The patched lsd.sh is generated here from the verified factory file, so the unit only copies
a file whose hash is known in advance. Output: OUT_DIR/pmcp/... (installer, payload, one script per GEM button in pmcp/menu/) and
OUT_DIR/esd/Launcher-sda0.esd (the M.I.B. 3.6.0 menu with one pmcp screen appended),
plus OUT_DIR/BUILD-MANIFEST.txt with every output hash.
"""
import hashlib
import os
import pathlib
import shutil
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent  # workspace: upstream/, backup/, archives/ next to this project
PROJ = HERE.parent         # this project (any folder name)
PMCP_BASE_VERSION = "pmcp-0.4.0-mu1161-791"   # release v1.4.0 (rg-main)
PMCP_VERSION = None   # PMCP_BASE_VERSION + "-" + first 8 hex of payload manifest, pmcp.sh and menu (set in main): one id per build

# M.I.B. backup of the unit (folder named after the unit; every file read from it is pinned by sha256 below)
BACKUP = pathlib.Path(os.environ.get("PMCP_BACKUP", REPO / "backup/MU1161")) / "advanced/MU1161-appimg"
MATHSLS = REPO / "upstream/mathsls/MU1161/791_AID12.3/payload"  # git cdd576b02a282853bd764a82b9a94e6474f39052
TUNING = PROJ / "build/mu1161-791/tuning"
# The GEM menu file of the M.I.B. version on the user's SD card (MIB_V3.6.0.zip, esd/Launcher-sda0.esd).
# The unit links engdefs/z_Launcher-sda0.esd to this file on the card, so adding a screen here changes nothing on the unit.
MIB_ESD = (REPO / "archives/mib-3.6.0/Launcher-sda0.esd",
           "22739f7226f36d089e2e0485fe2b6874aba2ee6b7b57c807de7bc25c0fdc9121", 111474)
# Java packages (stage B+): name -> GEM label. Each needs a "JAR_<name>" entry in PAYLOAD.
JAVA_PACKAGES = [("nai", "nai: AID map stays while the iPhone navigates (NavActiveIgnore)"),
                 ("np", "np: CarPlay song title and artist on the AID"),
                 ("rg", "rg: route guidance: arrows, lanes, distance bar, street, ETA (needs Route guidance system)"),
                 ("zoom", "zoom: CarPlay map zoom with the steering wheel arrows"),
                 ("dn", "dn: CarPlay map day/night on the AID (sent again after start)")]
# rg = everything for route guidance in one package (v1.4): Tomasz's port + his lanes, our VW U-turn lanes, his MU1367
# v1.4.3 distance bar / street name / feed recovery, and the maneuver fallbacks (rg/build.sh lanes-uturn-asf-m; the
# experimental branch's rgluasfm, car-tested 2026-11-04). The rg and rglu of v1.3 and the experimental rg variants are
# replaced by java-update (JAVA_OLD below).
# Tried and not shipped (docs/en/14-fast-start-audit.md, branch experimental): day/night v2 and the cluster day/night
# module (no effect on Google Maps), AID fast start kf..kf4, Android Auto.
# No two packages replace the same class (checked in main).
JAVA_ALTERNATIVES = set()
# In-car set (chosen in the car, 2026-10-24): 1 clean map (default), 2 clean card, 3 map with showSpeedLimit (the variant the
# unit has had since 2026-10-23, name kept), 4 clean map 40 columns left. All with url-map-hybrid's area.
VARIANTS = ["map-clean", "card-clean", "url-map-hybrid", "map-clean-l40", "map-square", "map-square-fps40"]
# main GEM button: map-square (chosen 2026-10-25) at 40 fps with an IDR every 5 frames, kept after the lag test drive
# (2026-10-31: no lag difference, no artefacts; IDR every 10 gave artefacts). map-square is 30 fps.
START_VARIANT = "map-square-fps40"

STOCK = {
    "IAP2DRV": (BACKUP / "armle/lib/dll/ipod-drvr-iap2.so", "7149a3e75b1b19e89021841759f420a6eced456b6c697a3dd1f0e436abea0b8c", 739925),
    "IAP2CFG": (BACKUP.parent / "MU1161-system/mm/iap2.cfg", "1539c79dd415eddeb59ea215c7a9b0ec4be3632fe066be3aefdff11bd19cdf37", 5951),
    "LSD": (BACKUP / "eso/hmi/lsd/lsd.sh", "97bbd4ecb51045b34c2a41955d9f53e1f144d174bff1aa8560e911525808e8d8", 16567),
    "DIO": (BACKUP / "eso/bin/apps/dio_manager", "609e42723ab3e36c7be5ceade81e03672ba4acd251f8eeb8b100e074aaf3c250", 686249),
    # Android Auto receiver: never changed by this card; must be the factory file (the experimental card's AA is refused)
    "GAL": (BACKUP / "eso/bin/apps/gal", "3b422d47a16dd473dc426aa3a88348bfee0da0e7585993a3566df242339346f9", 1269219),
}

# key -> (source, sha256, size, path inside payload/)
PAYLOAD = {
    "BRIDGE": (MATHSLS / "profiles/MU1161/791/altscreen-most-bridge",
               "fed7dce45f923384fec47861c448b753913f0561ed7e2a279860a5d13f8a44f4", 67835, "common/altscreen-most-bridge"),
    "SUPERVISOR": (MATHSLS / "common/carplay-cluster-supervisor",
                   "8e6ac3a85f04c3faca4850c9f09021bdd628fa1653d718f9c3db3be9d8057569", 56849, "common/carplay-cluster-supervisor"),
    "SEC": (MATHSLS / "common/libcarplay-security-bridge.so",
            "1cef6a3906ae781710a939246eea6c84b40545c04bdd0fd3b0871f195c7808e9", 52642, "common/libcarplay-security-bridge.so"),
    "PAIR_HELPER": (MATHSLS / "common/carplay-pairing-helper",
                    "ffb7d4df6d1e262f175276d43c8c5de7d54a63701dc3adc91d7e1b70ef7f44f7", 62527, "common/carplay-pairing-helper"),
    "PAIR_CORE": (MATHSLS / "common/libCarPlayPairingCore.so",
                  "90c348f99abcc54b5a486c8394d9a5cf0f484a4b68d91b222ffa6e96cc6e3b0d", 881665, "common/libCarPlayPairingCore.so"),
    "WRAPPER": (MATHSLS / "common/dio_manager.wrapper.sh",
                "8c12f6974adf9c8c9eb746e7d033e7fb35a9605e49c31ff2129e8ba938b2633d", 2063, "common/dio_manager.wrapper.sh"),
    # v2 (2026-10-22, review 2): every hook call guarded, RefCheck against the unit's java.* classes
    "JAR_nai": (PROJ / "build/nai-mu1161-v2/NavActiveIgnore.jar",
            "dbd031ecb28a2ec91c4704e133f4e2126cf1fe11498f673bc2e07fc0b1aaa7ab", 13285, "jars/NavActiveIgnore.jar"),
    "JAR_np": (PROJ / "build/np-mu1161-v2/pmcp-np.jar",
               "6b638868e65a6e573117cbf249850bb29e7b9aac3cd0502c2830652411f1dc23", 17928, "jars/pmcp-np.jar"),
    # rg/build.sh <lsd> <dir> lanes-uturn-asf-m; a file name no earlier card used (java-update keeps the old set intact)
    "JAR_rg": (PROJ / "build/rg-mu1161-lanes-uturn-asf-m/pmcp-rg.jar",
               "13ca11c4e2a5fbe155165071f69fbee0e2b5b318e87fbfc079a9f76fefb62770", 47817, "jars/pmcp-guidance.jar"),
    "JAR_zoom": (PROJ / "build/extras-mu1161-v2/pmcp-zoom.jar",
                 "046f48210dbee3177fbaa2a25f69154b56055f59b074fced1a0202700dd78d7b", 4740, "jars/pmcp-zoom.jar"),
    "JAR_dn": (PROJ / "build/extras-mu1161-v2/pmcp-dn.jar",
               "aabe871e87510177a333f1a76d69015f8bdeb994fba4ad1251e1b7f2b5afbd70", 11421, "jars/pmcp-dn.jar"),
    # Tomasz's driver patch + our log gate: his RGI receive log only with /dev/shmem/pmcp-rgi-debug (rg/driver/)
    "RG_DRIVER": (PROJ / "build/rg-mu1161-lanes-uturn-asf-m/ipod-drvr-iap2-gated.so",
                  "519ea3c5ba08427ea20d62817747af390ac7256bad447da5fcfda388d10b9ed3", 743272, "rg/ipod-drvr-iap2.so"),
    "RG_CFG": (PROJ / "build/rg-mu1161-lanes-uturn-asf-m/iap2.cfg",
               "c61407d9c6cd0d2529afedad0c9a120d5da5a504739e273bbb3dbea1e0b9b491", 6079, "rg/iap2.cfg"),
    # rgi-observer pmcp-r1 (rg/reader/, prebuilt in the repository): a stuck driver read costs one invalid record, not the reader
    "RG_READER": (PROJ / "rg/reader/prebuilt/rgi-observer",
                  "3166df9b91119475f93043ac8c150e2641732e602161839a137a1907d4ef11df", 13552, "rg/rgi-observer"),
}
# Earlier pmcp route guidance files that rg-update may replace in place (pmcp.sh RG_KNOWN): the v1.0-v1.3 driver and
# Tomasz's reader. (kind, sha256, sha1, size): only their hashes go to the card, so no earlier build is needed here.
RG_KNOWN = [
    ("DRIVER", "76926bde9bdf1e06fdfe57fd324bbd8772bcb2a98a58ac444b4822e25a331b48", "7613f35cb8597dbaedd16fd83260a14c7f2d654f", 743196),
    ("READER", "b683cef78828bfab2b8cdf43e4ea82e5d7c16d0d47730936d936e82af6ee08ac", "1b6cb87d2aa1148f28996f72cb00349519b19077", 16606),
]
# Java packages of earlier cards that java-update replaces (pmcp.sh JAVA_OLD): (name, sha256, sha1, size, jar file on the
# unit, successor). v1.2/v1.3 rg and rglu, and the experimental branch's rg variants (rg/build.sh modes base,
# lanes-uturn, and on branch experimental lanes-uturn-aa, -asf, -asf-aa, -asf-m, -asf-m-aa). Only their hashes go to the card.
JAVA_OLD = [
    ("rg", "717fb53c667c612e6f3b483ea93620559eaa23404a2e237d255f5af40798a754", "f748313879a40e3c8d69304dcfbfbbf003a412c6", 34082, "pmcp-rg.jar", "rg"),
    ("rglu", "72ab72214ee91a0d95ba0ec4d57a65cbee95d8ee82cb23af82fcb6b082591a33", "29b4bbcacc1c4251b7a47efd3c11445ba33e41f8", 38529, "pmcp-rglu.jar", "rg"),
    ("rglua", "a9a25b1eb9aeed1347bb9c6c38aef3549dc2416d844c10b203fd175319f62161", "809f18a0deb12667fe651c5309a6be5c63a3849a", 38832, "pmcp-rglua.jar", "rg"),
    ("rgluasf", "a092ef2a617cd63cde454d2bb18e8ea249f374770474ac030e5aea53edc373ed", "4fa0c5b25cbddc70b7c672ce58043fbd8eb3f68d", 47187, "pmcp-rgluasf.jar", "rg"),
    ("rgluasfa", "b3a35c9b40ae4bb5360189178b18218005a194f4585ee491a916bfce539c034d", "385c81be0210bdbd9f599a7739124d528f3d8770", 47510, "pmcp-rgluasfa.jar", "rg"),
    ("rgluasfm", "13ca11c4e2a5fbe155165071f69fbee0e2b5b318e87fbfc079a9f76fefb62770", "517763a46b37afac546ec45e24b72cf15307ad9a", 47817, "pmcp-rgluasfm.jar", "rg"),
    ("rgluasfma", "de39c893d8ea86abe4f57bc350fd7bd2d9b4a79f9023fc28a430cc2a20957ace", "ca03f2696567e24866b30e370159835a2cfae3db", 48161, "pmcp-rgluasfma.jar", "rg"),
]
for name in VARIANTS:
    PAYLOAD["CORE_" + name] = (TUNING / name / "core.so", None, 75099, "core/%s/core.so" % name)

TUNING_SHA = {
    "card-narrow": "3d6b823a92a71db7a79be6e382b754cb09959e71fb1ca6092089c0c4560c9229",
    "card-wide": "d58965ee8f932e905d5c888b7cbdab04cac43a9eb8d92ef6ff629dcfba66bedf",
    "card-narrow-hi": "a1b856b42e5268d810a56ec457d8e8a32370e321dbf34b017396c97f968c5d36",
    "map-diasdio": "4e2777b2d06fec693235828ce31259230e33992a931bb6b0369545e8f9ee230f",
    "map-crop340": "281a0c989d317d66e3243c1969c4c863518ade7bf5e6595121ebef8b93afdac2",
    "map-kf30": "6b581e5bbfa16085f94f36c9bebf395d3fb5ba113098efd9e81b91c39ea91d66",
    # package C (long URLs, build_core.py 2026-10-21)
    "url-card-noeta": "e5c2f37dcf631997bb95e8f3108d3d05e9ddf397225ab3068eff5993263f3324",
    "url-card-noeta-left": "ed63c05c5fa0f6e8fefc140d9257b34aeeb028da7bb4cb06c7ee9a1c36aae5f1",
    "url-card-noeta-right": "55cf67fcd3bbf853c1862b82a26d4b7e959bfc3077f43c6222eeb11c5bd25dcb",
    "url-card-noeta-speed": "0119ed2ae2d4dd900896811ef93caa24ba047c68c7f8dc0e26c08239c7401a64",
    "url-map-speed": "e12eb877cbfcdaea8c5dc7cc21a8fe32c122b07a4c6192629a5b167b97b52393",
    # hybrid mathsls + Tomasz (Tomasz width, 240x144 mm, card below the VW bar), build_core.py 2026-10-22
    "url-card-hybrid": "22afe97e219747969301157d3736c5a60e77418975b0fea75d98648c52c6039e",
    # same card position, safe-area bottom at row 460 (h 352 above every tested blank-card value), review 3 HIGH-1
    "url-card-hybrid-tall": "e6b6dac37b0098f1ab6cf4e48bae7d5ef915c53ed1d056458151127fa8c4a07a",
    # map without card, url-card-hybrid area / bottom row 364 (in-car 2026-10-23: no card in Apple nor Google with /map)
    "url-map-hybrid": "d7236f3065509a9cc3b79b48cc727575a71486e040d33ead7f2eecb0d89e3a3e",
    "url-map-hybrid-hi": "43a9e11775e6508b3580ef9e0a80428a461bbc0b275b1d2af763380722e289c8",
    # url-map-hybrid moved left by 80 / 160 columns (Google marker right of the map-window centre, 2026-10-24)
    "url-map-hybrid-l80": "f8f65a35e1e39082cd6a22dfdf2eb51d7600e4e5cf7addb7a76f52691360c6d8",
    "url-map-hybrid-l160": "a684edd2036c7dd9780ff3ed80822f69d5f6cd41c21993266abbb32489beef7d",
    # final set: clean map / clean card / clean map 40 columns left (url-map-hybrid area), 2026-10-24
    "map-clean": "c5f4870427d6d24bf78908497beb27e4e881d64374b58c564e7395d809efe2f4",
    "card-clean": "a4054ff9f1e7175ef9365e9f51990eb4ed3c58121ccfe4a6651e039e362552ac",
    "map-clean-l40": "0dbbebb0e47826fa39f9a1c28624ee6892b275f4a99865c091e39d43e79578ac",
    # mathsls's area 240/60/320/340 (closer to square) with the clean map URL, 2026-10-24
    "map-square": "f4d83fd2e33e20513e5856da554716e1b6a055a88bf69fe928beb52fadbe8028",
    # map-square latency A/B: maxFPS 40 (base value, as mathsls) / 20 / forced IDR every 10 frames, 2026-10-25
    "map-square-fps40": "f826ff0ab78ca595ef7e0c836ba183ae28c7cb7309f2ef6966d3a0c738a99050",
    "map-square-fps40-kf10": "88aa23c23e0d1ec93ded4c074e8c74681f074adc56ffdbedcb5c59ef833213f9",
    "map-square-fps20": "7d3c6009f8d2613603e70d80d10ed2fb6df2744cef77a068f74f769ee091a93d",
    "map-square-kf10": "a14f5a0b0d7ebe9a7e392549120d31634bf717839325faf36a89c8f8d81e24b5",
}

# Java stage (B and later): one fixed block in lsd.sh, before J9 starts. Which JARs load is read at boot from
# /mnt/app/carplaymaps/HMI_BOOT ("set-id jar jar ...", written by pmcp.sh with a single mv, so the id and the list
# always belong together). Every new set gets one trial boot (marker on /mnt/persist/pmcp); it becomes permanent only
# when the user presses "Potwierdz" in GEM during that boot (pmcp.sh java-confirm checks last-boot). There is no
# automatic confirmation: a running J9 does not prove a working HMI (review 1, findings 2 and 4).
# Never in update mode (RUN_MODE=swdl), so the rescue card always meets a factory HMI (review 1, finding 3).
# Any missing tool or unwritable marker means a factory boot. /mnt/persist/pmcp/DISABLED (rescue card) disables it.
LSD_PRE = r"""# >>> pmcp: CarPlay AID mod. Removing this block gives factory behaviour.
PMCP_DIR=/mnt/app/carplaymaps
PMCP_P=/mnt/persist/pmcp
PMCP_JARS=""
PMCP_SET=""
PMCP_LIST=""
PMCP_USE=no
rm -f $PMCP_P/last-boot 2>/dev/null
if [ "${RUN_MODE}" != swdl ] && [ -s $PMCP_DIR/HMI_BOOT ] && [ ! -e $PMCP_P/DISABLED ] && mkdir -p $PMCP_P 2>/dev/null; then
    read PMCP_SET PMCP_LIST < $PMCP_DIR/HMI_BOOT
    if [ -n "$PMCP_SET" ] && [ -n "$PMCP_LIST" ]; then
        if [ -e "$PMCP_P/ok.$PMCP_SET" ]; then
            PMCP_USE=yes
        elif [ ! -e "$PMCP_P/trial.$PMCP_SET" ] && touch "$PMCP_P/trial.$PMCP_SET" 2>/dev/null && [ -e "$PMCP_P/trial.$PMCP_SET" ]; then
            PMCP_USE=trial
        fi
    fi
    if [ $PMCP_USE != no ]; then
        for PMCP_J in $PMCP_LIST; do
            PMCP_JARS="$PMCP_JARS${PMCP_JARS:+:}$BASE_DIR/lsd/jars/$PMCP_J"
        done
    fi
    echo "set=$PMCP_SET use=$PMCP_USE" > $PMCP_P/last-boot 2>/dev/null
    echo "boot set=$PMCP_SET use=$PMCP_USE jars=${PMCP_JARS:-none}" >> $PMCP_P/boot.log 2>/dev/null
fi
[ -n "$PMCP_JARS" ] && BOOTCLASSPATH="$BOOTCLASSPATH -Xbootclasspath/p:$PMCP_JARS"
# Route guidance reader (package E, Tomasz's rgi-observer): only with the patched driver installed by pmcp and a
# Java set loading; in the background so it can never delay the HMI start.
if [ -n "$PMCP_JARS" ] && [ -x $PMCP_DIR/rg/rgi-observer ] && [ -e $PMCP_DIR/rg/SYSTEM_ON ]; then
    ( $PMCP_DIR/rg/rgi-observer start-live /dev/ipod0/rgi-events /ramdisk/carplay-route-guidance >/dev/null 2>&1 ) &
fi
# <<< pmcp"""


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_pinned(path, want_sha, want_size, label=""):
    data = pathlib.Path(path).read_bytes()
    if len(data) != want_size or (want_sha and sha(data) != want_sha):
        sys.exit("input mismatch: %s %s size=%d sha=%s" % (label, path, len(data), sha(data)))
    return data


def patch_lsd(stock):
    """Insert LSD_PRE before the 'export LD_PRELOAD' that precedes J9; nothing else changes."""
    text = stock.decode("ascii")
    lines = text.split("\n")
    j9 = [i for i, l in enumerate(lines) if l.lstrip().startswith("$J9 ")]
    if len(j9) != 1 or "-Xbootclasspath/p:" in text or "pmcp" in text:
        sys.exit("lsd.sh structure unexpected: J9 lines %r" % j9)
    j = j9[0]
    expect = ['export LD_PRELOAD=/lib/libecpp-ne.so.4:/mnt/app/root/lib-target/libcgdrv.so', 'info "lsd.sh J9 started" ',
              '$J9 $VMOPTIONS $BOOTCLASSPATH -jxe $HMI_JXE &', 'unset LD_PRELOAD']
    if lines[j - 2:j + 2] != expect:
        sys.exit("lsd.sh lines around J9 differ from the MU1161 factory file: %r" % lines[j - 2:j + 2])
    out = lines[:j - 2] + LSD_PRE.split("\n") + lines[j - 2:]
    return "\n".join(out).encode("ascii")


MENU_SCRIPT = """#!/bin/ksh
# pmcp GEM button: %(label)s (generated by build_sd.py)
if [ -f /net/rcc/dev/shmem/backup.mib ] || [ -f /net/rcc/dev/shmem/reboot.mib ] || [ -f /net/rcc/dev/shmem/flash.mib ]; then
    echo "M.I.B. is busy with another task, try again later."
    exit 0
fi
trap '' 2
echo "pmcp: %(label)s"
echo "Do not press Back and do not remove the SD card until PMCP_..._OK or PMCP_FAIL is shown."
/bin/ksh /net/mmx/fs/sda0/pmcp/pmcp.sh %(args)s
trap 2
exit 0
"""


# the diagnostics button runs bin/diag.sh directly: it must work even when pmcp.sh stops at its self test
DIAG_SCRIPT = """#!/bin/ksh
# pmcp GEM button: 0. Diagnostics (generated by build_sd.py)
trap '' 2
/bin/ksh /net/mmx/fs/sda0/pmcp/bin/diag.sh
trap 2
exit 0
"""

# start timeline, read-only like the diagnostics, runs bin/timeline.sh directly
TIMELINE = "timeline"
TIMELINE_SCRIPT = """#!/bin/ksh
# pmcp GEM button: start timeline (generated by build_sd.py)
trap '' 2
/bin/ksh /net/mmx/fs/sda0/pmcp/bin/timeline.sh
trap 2
exit 0
"""

# read-only navigation diagnostics: navigation start markers in /mnt/persist, processes, system log
NAVDIAG = "navdiag"
NAVDIAG_SCRIPT = """#!/bin/ksh
# pmcp GEM button: navigation diagnostics (generated by build_sd.py)
trap '' 2
/bin/ksh /net/mmx/fs/sda0/pmcp/bin/navdiag.sh
trap 2
exit 0
"""


# last route guidance messages from the iPhone and the VW arrow they give, read-only like the diagnostics
RGLAST = "rglast"
RGLAST_SCRIPT = """#!/bin/ksh
# pmcp GEM button: route guidance, last maneuvers (generated by build_sd.py)
trap '' 2
/bin/ksh /net/mmx/fs/sda0/pmcp/bin/rglast.sh
trap 2
exit 0
"""

# "Install all features": the same pmcp.sh actions as the advanced buttons, run one after another, so all Java packages
# land in one set (one trial boot, one Confirm). Stops at the first failure; "already on" counts as done.
ALL_ON_SCRIPT = """#!/bin/ksh
# pmcp GEM button: %(label)s (generated by build_sd.py)
if [ -f /net/rcc/dev/shmem/backup.mib ] || [ -f /net/rcc/dev/shmem/reboot.mib ] || [ -f /net/rcc/dev/shmem/flash.mib ]; then
    echo "M.I.B. is busy with another task, try again later."
    exit 0
fi
trap '' 2
echo "pmcp: %(label)s"
echo "Do not press Back and do not remove the SD card until PMCP_ALL_ON_OK or PMCP_FAIL is shown."
PMCP=/net/mmx/fs/sda0/pmcp/pmcp.sh
NEW=0
for A in %(actions)s; do
    echo "- ${A%%%%_*} ${A#*_}"
    OUT=`/bin/ksh $PMCP ${A%%%%_*} ${A#*_} 2>&1`
    echo "$OUT" | while read L; do case "$L" in PMCP_WARN*) ;; PMCP_*) echo "  $L" ;; esac; done
    case "$OUT" in
        *PMCP_FAIL=*_ALREADY_*) echo "  (already on)" ;;
        *PMCP_FAIL*) echo "PMCP_FAIL=ALL_ON_STOPPED_AT_$A"
                     echo "The steps before this one were done. Take a photo, then use Status, or Remove everything."
                     trap 2; exit 0 ;;
        *PMCP_*_OK*) NEW=1 ;;
        *) echo "PMCP_FAIL=ALL_ON_NO_RESULT_FROM_$A"; trap 2; exit 0 ;;
    esac
done
if [ $NEW = 1 ]; then
    echo "PMCP_ALL_ON_OK"
    echo "Restart the unit (hold the volume knob ~10 s). That first start is a TRIAL."
    echo "If the map and CarPlay work: open this menu again and press 4. Confirm, in that same start."
    echo "Without Confirm the next start is the factory one again."
else
    echo "PMCP_ALL_ON_OK (everything was already on, nothing changed)"
fi
trap 2
exit 0
"""


def menu_entries():
    # (file name, pmcp arguments, GEM label). ASCII only: GEM fonts and the esd parser are not tested with other letters.
    # Main screen: the simple path. Everything else (variants, single packages) is under pmcp_advanced.
    top = [("verify", "verify", "1. Check card and unit (read-only)"),
           ("install-" + START_VARIANT, "install " + START_VARIANT, "2. Install the CarPlay map on the AID"),
           ("all-on", ALL_ON, "3. Install all features or update: map, route guidance, zoom, day/night, song title"),
           ("java-confirm", "java-confirm", "4. Confirm: everything works (only in the first start after 3)"),
           ("java-retry", "java-retry", "5. Try again: the next start is a new trial"),
           ("status", "status", "Status (read-only)"),
           ("restore", "restore", "Remove everything (back to factory files)")]
    adv = [("diag", None, "0. Diagnostics (read-only, photograph the screen)"),
           ("timeline", TIMELINE, "Start timeline: seconds from unit start to CarPlay, MOST, navigation (read-only)"),
           ("rglast", RGLAST, "RG last maneuver: what the iPhone sent and which VW arrow it gives (read-only)"),
           ("navdiag", NAVDIAG, "Navigation diagnostics: why the VW navigation does not start (read-only)"),
           ("aa-remove", "aa-remove", "Remove experimental Android Auto (factory gal back; button 3 does it too)")]
    inst = [("install-" + v, "install " + v, "Install map layout: " + v) for v in VARIANTS if v != START_VARIANT]
    sw = [("switch-" + v, "switch " + v, "Switch map layout to: " + v) for v in VARIANTS]
    rg = [("rg-system-on", "rg-system-on", "Route guidance system on (iAP2 driver, iap2.cfg, reader)"),
          ("rg-system-off", "rg-system-off", "Route guidance system off (factory iAP2 driver and iap2.cfg)"),
          ("rg-update", "rg-update", "Route guidance system update (driver and reader of this card, RG stays on)"),
          ("java-update", "java-update", "Java update: packages of an earlier card -> this card's (rglu -> rg)")]
    java = rg + [("java-on-" + n, "java-on " + n, "On " + label) for n, label in JAVA_PACKAGES] + \
           [("java-off-" + n, "java-off " + n, "Off " + label) for n, label in JAVA_PACKAGES]
    return top, adv, inst, sw, java


# actions of "Install all features or update", in order: an experimental card's Android Auto off (aa-remove), an earlier
# card's RG driver/reader and Java packages replaced by
# this card's (rg-update, java-update), the main map (an older install gets START_VARIANT, already there: skipped), the
# route guidance system (rg needs it), then every package. Steps already done answer *_ALREADY_* and are skipped, so
# the same button brings any earlier pmcp install to this card's set.
ALL_ON = ["aa-remove", "rg-update", "java-update", "switch_" + START_VARIANT, "rg-system-on"] + ["java-on_" + n for n, _ in JAVA_PACKAGES]


def menu_script(args, label):
    if args is None:
        return DIAG_SCRIPT
    if args is TIMELINE:
        return TIMELINE_SCRIPT
    if args is NAVDIAG:
        return NAVDIAG_SCRIPT
    if args is RGLAST:
        return RGLAST_SCRIPT
    if args is ALL_ON:
        return ALL_ON_SCRIPT % dict(label=label, actions=" ".join(a if "_" in a else a + "_" for a in args))
    return MENU_SCRIPT % dict(label=label, args=args)


def esd_block(version, top, adv, inst, sw, java):
    def kv(text):
        return ['keyValue', '    value   String sys 0x00000000 0', '    label   "%s"' % text, '    poll    0', '']
    def sc(name, label):
        return ['script', '    value   sys 1 0x0100 "/net/mmx/fs/sda0/pmcp/menu/%s.sh"' % name, '    label   "%s"' % label, '']
    out = ['', '#' * 91, '#', '# Main -> M.I.B. -> pmcp: CarPlay map on AID (Passat B8 MU1161 / 791), added on the SD card only',
           '#', '#' * 91, 'screen pmcp_CarPlay_AID =>M.I.B.<=', '']
    out += kv(version) + kv("Every action checks all files first and changes nothing on a mismatch. Photograph each result.")
    out += kv("After 2 and after 3: restart the unit (hold the volume knob ~10 s).")
    for n, _, l in top:
        out += sc(n, l)
    out += ['screen pmcp_advanced pmcp_CarPlay_AID', '']
    out += kv("Advanced: diagnostics (read-only), single packages and other map layouts.")
    for n, _, l in adv:
        out += sc(n, l)
    out += ['screen pmcp_other_layouts pmcp_advanced', '']
    for n, _, l in inst:
        out += sc(n, l)
    out += ['screen pmcp_switch_layout pmcp_advanced', '']
    for n, _, l in sw:
        out += sc(n, l)
    out += ['screen pmcp_packages pmcp_advanced', '']
    out += kv("The first start after a change is a trial: if everything works, press 4. Confirm in that start.")
    out += kv("Without Confirm the next start is the factory one (then: 5. Try again).")
    out += kv("Black screen: hold the volume knob ~10 s, the next start loads none of our JARs.")
    for n, _, l in java:
        out += sc(n, l)
    return "\r\n".join(out) + "\r\n"


def main():
    out = pathlib.Path(sys.argv[1])
    if out.exists():
        sys.exit("output exists: %s" % out)
    pm = out / "pmcp"
    (pm / "bin").mkdir(parents=True)
    (pm / "payload").mkdir()
    (out / "esd").mkdir()
    (pm / "menu").mkdir()

    stock = {k: read_pinned(p, h, s, k) for k, (p, h, s) in STOCK.items()}
    rows = []
    for key, (src, h, size, rel) in PAYLOAD.items():
        if h is None:
            h = TUNING_SHA[key[5:]]
        data = read_pinned(src, h, size, key)
        dst = pm / "payload" / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(data)
        rows.append((key, h, size, rel))

    # Java packages are loaded together (one -Xbootclasspath/p list): no two may replace the same class.
    owner = {}
    for key, (src, h, size, rel) in PAYLOAD.items():
        if key.startswith("JAR_"):
            import zipfile
            with zipfile.ZipFile(pm / "payload" / rel) as z:
                for n in z.namelist():
                    if n.endswith(".class"):
                        if n in owner and tuple(sorted((owner[n], key))) not in JAVA_ALTERNATIVES:
                            sys.exit("class %s is in both %s and %s" % (n, owner[n], key))
                        owner[n] = key
    if {k for k in PAYLOAD if k.startswith("JAR_")} != {"JAR_" + n for n, _ in JAVA_PACKAGES}:
        sys.exit("JAVA_PACKAGES and JAR_* payload entries differ")
    # java-update relies on new file names: an earlier card's JAR file is never overwritten while its set is active
    ours = {rel.rsplit("/", 1)[-1] for k, (src, h, size, rel) in PAYLOAD.items() if k.startswith("JAR_")}
    cur = {(k[4:], h[:8]) for k, (src, h, size, rel) in PAYLOAD.items() if k.startswith("JAR_")}
    olds = [(name, h[:8]) for name, h, h1, size, jar, succ in JAVA_OLD]
    if len(set(olds)) != len(olds) or set(olds) & cur or len({o[4] for o in JAVA_OLD}) != len(JAVA_OLD):
        sys.exit("JAVA_OLD: a (name, sha8) twice or equal to this card's package, or a JAR file name twice")
    for name, h, h1, size, jar, succ in JAVA_OLD:
        if len(h1) != 40 or len(h) != 64:
            sys.exit("JAVA_OLD entry %s: bad hash length" % name)
        if jar in ours or not jar.startswith("pmcp-") or ("JAR_" + succ) not in PAYLOAD:
            sys.exit("JAVA_OLD entry %s: file %s reused, outside pmcp-*.jar (rescue card) or no successor" % (name, jar))

    lsd_patched = patch_lsd(stock["LSD"])
    (pm / "payload/lsd/lsd.sh").parent.mkdir(parents=True, exist_ok=True)
    (pm / "payload/lsd/lsd.sh").write_bytes(lsd_patched)
    rows.append(("LSD_JAVA", sha(lsd_patched), len(lsd_patched), "lsd/lsd.sh"))

    selftest = bytes(range(256)) * 3 + b"\n\n\0\r\nend-without-newline"
    (pm / "bin/selftest.bin").write_bytes(selftest)
    shutil.copyfile(HERE / "sd/pmcp/bin/sha256.awk", pm / "bin/sha256.awk")
    shutil.copyfile(HERE / "sd/pmcp/bin/diag.sh", pm / "bin/diag.sh")
    shutil.copyfile(HERE / "sd/pmcp/bin/timeline.sh", pm / "bin/timeline.sh")
    shutil.copyfile(HERE / "sd/pmcp/bin/navdiag.sh", pm / "bin/navdiag.sh")
    shutil.copyfile(HERE / "sd/pmcp/bin/rglast.sh", pm / "bin/rglast.sh")

    manifest = "\n".join("%s %s %d %s" % r for r in rows)
    # SHA-256 -> SHA-1 of the same bytes, for the unit's factory sha1sum (pmcp.sh hash_of/sha1_for)
    pairs = {sha(selftest): hashlib.sha1(selftest).hexdigest()}
    for data in stock.values():
        pairs[sha(data)] = hashlib.sha1(data).hexdigest()
    known = []
    for kind, h, h1, size in RG_KNOWN:
        pairs[h] = h1
        known.append("%s %s %d" % (kind, h, size))
    old = []
    for name, h, h1, size, jar, succ in JAVA_OLD:
        pairs[h] = h1
        old.append("%s %s %d %s %s" % (name, h, size, jar, succ))
    for key, h, size, rel in rows:
        data = (pm / "payload" / rel).read_bytes()
        assert sha(data) == h and len(data) == size, key
        pairs[h] = hashlib.sha1(data).hexdigest()
    hashmap = "\n".join("%s %s" % kv for kv in sorted(pairs.items()))
    # build id: payload manifest, installer template and the whole menu (labels and button scripts)
    menus = menu_entries()
    menu_text = esd_block("@@VERSION@@", *menus) + "".join(n + "\n" + menu_script(a, l) for scr in menus for n, a, l in scr)
    global PMCP_VERSION
    PMCP_VERSION = PMCP_BASE_VERSION + "-" + sha((manifest + "\n" + "\n".join(known) + "\n" + "\n".join(old) + "\n"
                                                   + (HERE / "template/pmcp.sh.in").read_text() + menu_text).encode())[:8]
    tpl = (HERE / "template/pmcp.sh.in").read_text()
    for k, v in {
        "@@PMCP_VERSION@@": PMCP_VERSION, "@@MANIFEST@@": manifest,
        "@@SELFTEST_SHA@@": sha(selftest), "@@SELFTEST_SIZE@@": str(len(selftest)),
        "@@HASHMAP@@": hashmap, "@@RG_KNOWN@@": "\n".join(known), "@@JAVA_OLD@@": "\n".join(old),
        "@@STOCK_GAL_SHA@@": STOCK["GAL"][1], "@@STOCK_GAL_SIZE@@": str(STOCK["GAL"][2]),
        "@@STOCK_LSD_SHA@@": STOCK["LSD"][1], "@@STOCK_LSD_SIZE@@": str(STOCK["LSD"][2]),
        "@@STOCK_DIO_SHA@@": STOCK["DIO"][1], "@@STOCK_DIO_SIZE@@": str(STOCK["DIO"][2]),
        "@@STOCK_DRV_SHA@@": STOCK["IAP2DRV"][1], "@@STOCK_DRV_SIZE@@": str(STOCK["IAP2DRV"][2]),
        "@@STOCK_CFG_SHA@@": STOCK["IAP2CFG"][1], "@@STOCK_CFG_SIZE@@": str(STOCK["IAP2CFG"][2]),
    }.items():
        assert k in tpl, k
        tpl = tpl.replace(k, v)
    assert "@@" not in tpl
    (pm / "pmcp.sh").write_text(tpl)
    for name, args, label in [e for scr in menus for e in scr]:
        script = menu_script(args, label)
        (pm / "menu" / (name + ".sh")).write_text(script)
    esd = read_pinned(*MIB_ESD, label="MIB_ESD").decode("ascii")
    assert "pmcp" not in esd and esd.endswith("\r\n")
    (out / "esd/Launcher-sda0.esd").write_bytes((esd + esd_block(PMCP_VERSION, *menus)).encode("ascii"))

    lines = []
    for p in sorted(out.rglob("*")):
        if p.is_file():
            lines.append("%s  %8d  %s" % (sha(p.read_bytes()), p.stat().st_size, p.relative_to(out)))
    (out / "BUILD-MANIFEST.txt").write_text(PMCP_VERSION + "\n" + "\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
