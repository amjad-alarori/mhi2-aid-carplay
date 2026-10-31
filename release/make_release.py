#!/usr/bin/env python3
"""Pack the ready-made SD cards into one zip for people who just want to install. Host tool.

  python3 -I release/make_release.py BUILD_DIR OUT_DIR

BUILD_DIR is the build/ folder of install.sh (card1-install/, card2-rescue/, sd/BUILD-MANIFEST.txt). Both card
folders are checked against their own manifests first. Output: OUT_DIR/mhi2-aid-carplay-cards-<build id>.zip with

  mhi2-aid-carplay-cards-<build id>/
    README-FIRST.txt            plain-English steps (computer, then car)
    Copy-to-SD-Windows.bat      double-click: copies one card folder to an empty FAT32 card, checks every file
    Copy-to-SD-macOS.command    the same for macOS
    tools/copy-to-sd.ps1
    card1-install/  card2-rescue/
    docs/                        M.I.B. install + backup, full in-car guide

The zip is deterministic (sorted entries, fixed timestamps), so the same build gives the same zip.
"""
import hashlib
import pathlib
import re
import sys
import zipfile

HERE = pathlib.Path(__file__).resolve().parent
PROJ = HERE.parent
CARDS = {"card1-install": "PMCP_CARD_MANIFEST.txt", "card2-rescue": "PMCP_RESCUE_MANIFEST.txt"}
LINE = re.compile(r"^([0-9a-f]{64}) +([0-9]+)  (.+)$")


def sha(data):
    return hashlib.sha256(data).hexdigest()


def check_card(folder, manifest):
    listed = set()
    for l in (folder / manifest).read_text().splitlines():
        m = LINE.match(l)
        if not m:
            continue
        h, size, rel = m.groups()
        data = (folder / rel).read_bytes()
        if sha(data) != h or len(data) != int(size):
            sys.exit("%s/%s differs from its manifest" % (folder.name, rel))
        listed.add(rel)
    present = {p.relative_to(folder).as_posix() for p in folder.rglob("*") if p.is_file()} - {manifest}
    if present != listed:
        sys.exit("%s has unlisted or missing files: %r" % (folder.name, sorted(present ^ listed)[:5]))
    return len(listed)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    build, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    version = (build / "sd/BUILD-MANIFEST.txt").read_text().splitlines()[0]
    if (build / "card1-install/PMCP_CARD_MANIFEST.txt").read_text().splitlines()[0] != version:
        sys.exit("card 1 is from another build than sd/")
    if (build / "card2-rescue/pmcp").exists() or not (build / "card2-rescue/Swdlautorun.txt").exists():
        sys.exit("card 2 is not an armed rescue card")
    if (build / "card1-install/Swdlautorun.txt").exists() or (build / "card1-install/pmcp/ODBLOKUJ_ETAP_B").exists():
        sys.exit("card 1 must not be armed or unlocked")
    files = {}   # path in zip -> (bytes, executable)
    for name, manifest in CARDS.items():
        n = check_card(build / name, manifest)
        print("%s: %d files ok" % (name, n))
        for p in (build / name).rglob("*"):
            if p.is_file():
                files["%s/%s" % (name, p.relative_to(build / name).as_posix())] = (p.read_bytes(), False)
    readme = (HERE / "README-FIRST.txt").read_text().replace("@@VERSION@@", version)
    files["README-FIRST.txt"] = (readme.replace("\n", "\r\n").encode("ascii"), False)   # opens in Notepad too
    readme_pl = (HERE / "README-FIRST.pl.txt").read_text(encoding="utf-8").replace("@@VERSION@@", version)
    files["README-FIRST.pl.txt"] = (readme_pl.replace("\n", "\r\n").encode("utf-8"), False)   # Polish letters: UTF-8
    files["Copy-to-SD-Windows.bat"] = ((HERE / "Copy-to-SD-Windows.bat").read_bytes(), False)
    files["Copy-to-SD-macOS.command"] = ((HERE / "Copy-to-SD-macOS.command").read_bytes(), True)
    files["tools/copy-to-sd.ps1"] = ((HERE / "tools/copy-to-sd.ps1").read_bytes().replace(b"\r\n", b"\n").replace(b"\n", b"\r\n"), False)
    files["docs/01-install-MIB-and-backup.md"] = ((PROJ / "docs/en/01-mib-install-backup.md").read_bytes(), False)
    files["docs/in-car-guide.md"] = ((PROJ / "docs/en/09-in-car-guide.md").read_bytes(), False)
    files["docs/01-instalacja-MIB-i-backup.pl.md"] = ((PROJ / "docs/pl/01-mib-instalacja-backup.md").read_bytes(), False)
    files["docs/tutorial-w-aucie.pl.md"] = ((PROJ / "docs/pl/09-tutorial-w-aucie.md").read_bytes(), False)
    files["LICENSE.txt"] = ((PROJ / "LICENSE").read_bytes(), False)
    top = "mhi2-aid-carplay-cards-" + version.rsplit("-", 1)[1]
    out.mkdir(parents=True, exist_ok=True)
    zpath = out / (top + ".zip")
    if zpath.exists():
        sys.exit("exists: %s" % zpath)
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        dirs = sorted({"/".join(k.split("/")[:i]) for k in files for i in range(1, k.count("/") + 1)})
        for d in dirs:
            i = zipfile.ZipInfo("%s/%s/" % (top, d), date_time=(2026, 1, 1, 0, 0, 0))
            i.external_attr = (0o40755 << 16) | 0x10
            i.create_system = 3
            z.writestr(i, b"")
        for k in sorted(files):
            data, exe = files[k]
            i = zipfile.ZipInfo("%s/%s" % (top, k), date_time=(2026, 1, 1, 0, 0, 0))
            i.compress_type = zipfile.ZIP_DEFLATED
            i.external_attr = (0o100755 if exe else 0o100644) << 16
            i.create_system = 3
            z.writestr(i, data)
    print("%s  %d files  %.1f MB  sha256 %s" % (zpath, len(files), zpath.stat().st_size / 1e6, sha(zpath.read_bytes())))


if __name__ == "__main__":
    main()
