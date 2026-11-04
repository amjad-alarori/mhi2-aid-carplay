#!/usr/bin/env python3
"""Assemble the complete pmcp INSTALL card (card 1) from the pinned M.I.B. 3.6.0 zip + a verified build_sd.py output. Host tool.

  python3 -I build_card_install.py SD_BUILD_DIR OUT_DIR

Output = the M.I.B. 3.6.0 tree exactly as in the zip (autorun stays DISARMED: _Swdlautorun.txt), plus
  - pmcp/ and esd/Launcher-sda0.esd from SD_BUILD_DIR (every file checked against its BUILD-MANIFEST.txt first);
  - BUILD-MANIFEST.txt (copied), PMCP_INSTRUKCJA.txt, PMCP_CARD_MANIFEST.txt (hash of every file on the card).
Nothing on this card runs by itself: the installer is started from GEM, one action (batch) at a time.
The rescue card (build_rescue.py) is a separate card; this script refuses anything that would mix the two.
"""
import hashlib
import pathlib
import shutil
import sys
import zipfile

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent
PROJ = HERE.parent         # this project (any folder name)
ZIP = PROJ / "mib/downloads/MIB_V3.6.0.zip"
ZIP_SHA = "4bfc6e725b5cc60c3c8c73081609dabfe1a2016b5d8671e2438592e673a98086"
PREFIX = "M.I.B._More-Incredible-Bash-3.6.0/"
MIB_ESD_SHA = "22739f7226f36d089e2e0485fe2b6874aba2ee6b7b57c807de7bc25c0fdc9121"   # = build_sd.py MIB_ESD

README = """CARD 1 - INSTALL: CarPlay map on the AID (VW MHI2 MU1161, AID 791) - build %(ver)s
====================================================================================

This is M.I.B. 3.6.0 plus the CarPlay-on-AID installer. Nothing starts by itself
(_Swdlautorun.txt is disarmed - do NOT rename it). Everything runs from the green menu (GEM):

  Card in slot SD1. Hold MENU ~10 s -> =>M.I.B.<= -> pmcp_CarPlay_AID
  The header must show: %(ver)s

  1. Check card and unit (read-only)        -> PMCP_VERIFY_OK state=STOCK
  2. Install the CarPlay map on the AID     -> restart (volume knob ~10 s), check the map
  3. Install all features                   -> restart: this first start is a TRIAL
  4. Confirm: everything works              -> press it in that same start; restart; done
     (no Confirm, or black screen: restart again -> factory start, nothing to fix)
  Remove everything (back to factory files) -> undo it all

Photograph each result (the card is read-only in GEM, there is no log file).
Do not copy the rescue card (pmcp-rescue/, Swdlautorun.txt) onto this card.
"""


def sha(b):
    return hashlib.sha256(b).hexdigest()


def main():
    sdb, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    if out.exists():
        sys.exit("output exists: %s" % out)
    # 1. the installer build: exactly the files of its BUILD-MANIFEST.txt, nothing more, nothing less
    man = (sdb / "BUILD-MANIFEST.txt").read_text().splitlines()
    ver, entries = man[0], [l.split() for l in man[1:] if l.strip()]
    if not ver.startswith("pmcp-0.4.1-mu1161-791-"):
        sys.exit("unexpected build version: %s" % ver)
    listed = set()
    for h, size, rel in entries:
        data = (sdb / rel).read_bytes()
        if sha(data) != h or len(data) != int(size):
            sys.exit("build file differs from its manifest: %s" % rel)
        listed.add(rel)
    present = {str(p.relative_to(sdb)) for p in sdb.rglob("*") if p.is_file()} - {"BUILD-MANIFEST.txt"}
    if present != listed:
        sys.exit("build dir has unlisted/missing files: %r" % sorted(present ^ listed))
    if not all(r.startswith("pmcp/") or r == "esd/Launcher-sda0.esd" for r in listed):
        sys.exit("build contains files outside pmcp/ and esd/Launcher-sda0.esd")
    if "pmcp/ODBLOKUJ_ETAP_B" in listed:
        sys.exit("stage B must not be unlocked in a build")
    # 2. the M.I.B. 3.6.0 tree, unchanged
    if sha(ZIP.read_bytes()) != ZIP_SHA:
        sys.exit("M.I.B. zip is not the pinned 3.6.0")
    with zipfile.ZipFile(ZIP) as z:
        for n in z.namelist():
            rel = n[len(PREFIX):] if n.startswith(PREFIX) else None
            if not rel:
                continue
            dst = out / rel
            if n.endswith("/"):
                dst.mkdir(parents=True, exist_ok=True)
                continue
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(z.read(n))
    if sha((out / "esd/Launcher-sda0.esd").read_bytes()) != MIB_ESD_SHA:
        sys.exit("M.I.B. menu file is not the one build_sd.py extends")
    if (out / "Swdlautorun.txt").exists() or not (out / "_Swdlautorun.txt").exists():
        sys.exit("M.I.B. autorun is not in the disarmed state")
    if (out / "pmcp").exists() or (out / "pmcp-rescue").exists() or (out / "pmcp-ratunek").exists():
        sys.exit("unexpected pmcp files in the M.I.B. zip")
    # 3. overlay: our menu screen (M.I.B. menu + one appended screen) and the installer
    for rel in sorted(listed):
        dst = out / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(sdb / rel, dst)
    if not (out / "esd/Launcher-sda0.esd").read_bytes().startswith((REPO / "archives/mib-3.6.0/Launcher-sda0.esd").read_bytes()):
        sys.exit("our menu file does not start with the unchanged M.I.B. menu")
    (out / "PMCP_INSTRUKCJA.txt").write_text(README % {"ver": ver})
    shutil.copyfile(sdb / "BUILD-MANIFEST.txt", out / "BUILD-MANIFEST.txt")   # run_tests.sh reads it from the card root
    # 4. final guards and the card manifest
    for bad in ("Swdlautorun.txt", "pmcp-rescue", "PMCP_RESCUE_README.txt", "pmcp-ratunek", "PMCP_RATUNEK_README.txt",
                "pmcp/ODBLOKUJ_ETAP_B"):
        if (out / bad).exists():
            sys.exit("install card must not contain %s" % bad)
    lines = ["%s  %8d  %s" % (sha(p.read_bytes()), p.stat().st_size, p.relative_to(out))
             for p in sorted(out.rglob("*")) if p.is_file()]
    (out / "PMCP_CARD_MANIFEST.txt").write_text(ver + "\n" + "\n".join(lines) + "\n")
    print(ver, "files:", len(lines))


if __name__ == "__main__":
    main()
