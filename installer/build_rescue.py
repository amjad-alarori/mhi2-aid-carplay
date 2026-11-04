#!/usr/bin/env python3
"""Build the pmcp rescue card (a separate SD card) from the pinned M.I.B. 3.6.0 zip. Host tool.

  python3 -I build_rescue.py OUT_DIR

Output = the M.I.B. 3.6.0 tree exactly as in the zip, with three changes:
  - _Swdlautorun.txt renamed to Swdlautorun.txt (armed: the unit enters update mode by itself);
  - Launcher/stuff.sh: our rescue runs first and saves its log last; M.I.B.'s own lines are unchanged;
  - pmcp-rescue/pmcp-rescue.sh added, plus PMCP_RESCUE_README.txt.
metainfo2.txt and Launcher/final/finalScript.sh (SHA1 checked by metainfo2) stay untouched; stuff.sh is
outside metainfo2's reach (M.I.B.'s own comment in stuff.sh). The card carries no pmcp installer.
"""
import hashlib
import pathlib
import sys
import zipfile

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent
PROJ = HERE.parent         # this project (any folder name)
ZIP = PROJ / "mib/downloads/MIB_V3.6.0.zip"
ZIP_SHA = "4bfc6e725b5cc60c3c8c73081609dabfe1a2016b5d8671e2438592e673a98086"
PREFIX = "M.I.B._More-Incredible-Bash-3.6.0/"
STUFF_SHA = "bac7f77c6b267f438a57d1dca92550d9ead0e4ad5b4c8505e480b180e0096964"
FINAL_SHA1 = "ba391875e14a8794b683cc02556990fcb555fe08"

STUFF_HEAD = """# >>> pmcp rescue card: undo our HMI start changes first, without any redirect (see pmcp-rescue.sh)
if [ -f ${2}/pmcp-rescue/pmcp-rescue.sh ]; then
\t/bin/ksh ${2}/pmcp-rescue/pmcp-rescue.sh ${1} ${2}
fi
# <<< pmcp
"""
STUFF_TAIL = """
# >>> pmcp rescue card: the card is writable now (M.I.B. remounted it), move the RAM log there
if [ -f ${2}/pmcp-rescue/pmcp-rescue.sh ]; then
\t/bin/ksh ${2}/pmcp-rescue/pmcp-rescue.sh --save-log ${2}
fi
# <<< pmcp
"""

README = """CARD 2 - RESCUE: CarPlay map on the AID (VW MHI2 MU1161, M.I.B. 3.6.0)
========================================================================

When: after "Install all features" the head unit screen stays black or keeps restarting, and
holding the volume knob ~10 s does not help (normally an unconfirmed start falls back to factory
by itself; this card is the second safety net).

What it does: insert it in slot SD1 and wait up to 60 s. The unit enters update mode by itself
(answer Continue if asked; do NOT pull the card while it updates). It then:
  1. puts back the factory lsd.sh,
  2. removes our Java files (NavActiveIgnore.jar, pmcp-*.jar),
  3. writes /mnt/persist/pmcp/DISABLED (nothing of ours loads at start),
  4. puts back the factory iAP2 driver and iap2.cfg if the route guidance system was on.
The map picture stays. Afterwards, in the green menu: "Remove everything (back to factory files)".
The unit also re-installs M.I.B. 3.6.0 on the way, as when M.I.B. was installed.

When the normal screen is back: remove the card. Its result is in PMCP_RESCUE_LOG.txt on this
card ("RESULT=OK").

After each use M.I.B. disarms the card (Swdlautorun.txt -> _Swdlautorun.txt), so it cannot loop.
To re-arm it: on a computer run the copy helper and choose 3, or rename _Swdlautorun.txt back to
Swdlautorun.txt yourself.

This must be a SEPARATE card. Do not copy pmcp/ onto it. Keep it OUT of the car until needed.
"""


def sha(b, algo="sha256"):
    return hashlib.new(algo, b).hexdigest()


def main():
    out = pathlib.Path(sys.argv[1])
    if out.exists():
        sys.exit("output exists: %s" % out)
    data = ZIP.read_bytes()
    if sha(data) != ZIP_SHA:
        sys.exit("M.I.B. zip is not the pinned 3.6.0")
    with zipfile.ZipFile(ZIP) as z:
        names = [n for n in z.namelist() if n.startswith(PREFIX)]
        for n in names:
            rel = n[len(PREFIX):]
            if not rel:
                continue
            dst = out / rel
            if n.endswith("/"):
                dst.mkdir(parents=True, exist_ok=True)
                continue
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(z.read(n))
    stuff = (out / "Launcher/stuff.sh").read_bytes()
    if sha(stuff) != STUFF_SHA:
        sys.exit("stuff.sh differs from M.I.B. 3.6.0")
    if sha((out / "Launcher/final/finalScript.sh").read_bytes(), "sha1") != FINAL_SHA1:
        sys.exit("finalScript.sh differs from metainfo2")
    text = stuff.decode("ascii")
    first, rest = text.split("\n", 1)
    assert first == "#!/bin/ksh"
    (out / "Launcher/stuff.sh").write_bytes((first + "\n" + STUFF_HEAD + rest + STUFF_TAIL).encode("ascii"))
    arm = out / "_Swdlautorun.txt"
    if not arm.exists() or (out / "Swdlautorun.txt").exists():
        sys.exit("unexpected autorun files in the zip")
    arm.rename(out / "Swdlautorun.txt")
    (out / "pmcp-rescue").mkdir()
    (out / "pmcp-rescue/pmcp-rescue.sh").write_bytes((HERE / "rescue/pmcp-rescue.sh").read_bytes())
    (out / "PMCP_RESCUE_README.txt").write_text(README)
    if (out / "pmcp").exists():
        sys.exit("rescue card must not contain the pmcp installer")
    lines = []
    for p in sorted(out.rglob("*")):
        if p.is_file():
            lines.append("%s  %8d  %s" % (sha(p.read_bytes()), p.stat().st_size, p.relative_to(out)))
    (out / "PMCP_RESCUE_MANIFEST.txt").write_text("\n".join(lines) + "\n")
    print("files:", len(lines))
    for l in lines:
        if any(k in l for k in ("stuff.sh", "pmcp-rescue", "Swdlautorun", "metainfo2", "finalScript")):
            print(l)


if __name__ == "__main__":
    main()
