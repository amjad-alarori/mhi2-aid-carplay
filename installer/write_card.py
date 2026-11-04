#!/usr/bin/env python3
"""Copy a built card folder onto a mounted SD card, fail-closed. Host tool, used by install.sh.

  python3 -I write_card.py check  install|rescue SRC CARD   read-only: may this card take this folder?
  python3 -I write_card.py write  install|rescue SRC CARD   check, then copy (only after check passed)
  python3 -I write_card.py verify install|rescue SRC CARD   re-read every file on the card against the manifest

SRC is build/card1-install (manifest PMCP_CARD_MANIFEST.txt) or build/card2-rescue (PMCP_RESCUE_MANIFEST.txt).
Rules:
  - nothing on the card is ever deleted or formatted; only files listed in the manifest are written;
  - install card: the card is empty, or holds exactly the M.I.B. 3.6.0 tree (a backup/ folder of the unit may
    stay next to it and is never touched); a card with pmcp/, pmcp-rescue/ (pmcp-ratunek/ before v1.4) or an armed Swdlautorun.txt is refused;
  - rescue card: the card must be empty, and the armed Swdlautorun.txt is written last, so a card that was pulled
    half-way never starts by itself;
  - every file is written to a temporary name, fsync'd and renamed; AppleDouble "._" files that macOS adds next to
    files written here are removed (only those, recognised by their magic bytes).
"""
import hashlib
import os
import pathlib
import shutil
import sys

MANIFEST = {"install": "PMCP_CARD_MANIFEST.txt", "rescue": "PMCP_RESCUE_MANIFEST.txt"}
# Written by macOS / Windows on any FAT volume; never ours, never read by the unit.
SYSTEM_DIRS = (".fseventsd", ".Spotlight-V100", ".Trashes", ".TemporaryItems", "System Volume Information")
# Files of the M.I.B. git tree that the zip carries but users often do not copy; tolerated if missing.
GIT_ONLY = {".git-blame-ignore-revs", ".gitattributes", ".github/FUNDING.yml",
            ".github/ISSUE_TEMPLATE/bug_report.md", ".gitignore"}
MIB_ESD_SHA = "22739f7226f36d089e2e0485fe2b6874aba2ee6b7b57c807de7bc25c0fdc9121"   # M.I.B. 3.6.0 esd/Launcher-sda0.esd
APPLEDOUBLE = b"\x00\x05\x16\x07"
# install card files outside pmcp/ that replace or add to the M.I.B. tree
OVERLAY = {"BUILD-MANIFEST.txt", "PMCP_INSTRUKCJA.txt", "esd/Launcher-sda0.esd"}


def say(msg):
    print(msg, flush=True)


def stop(msg):
    say("REFUSED: " + msg)
    say("Nothing was written to the card.")
    sys.exit(1)


def hf(p):
    s = hashlib.sha256()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            s.update(c)
    return s.hexdigest()


def load(kind, src):
    lines = (src / MANIFEST[kind]).read_text().splitlines()
    if kind == "install":
        ver, lines = lines[0], lines[1:]
    else:
        ver = "rescue card"
    ent = [l.split(None, 2) for l in lines if l.strip()]
    for h, size, rel in ent:
        if hf(src / rel) != h or (src / rel).stat().st_size != int(size):
            stop("the built folder changed after it was built: %s (run install.sh again)" % rel)
    return ver, ent


def card_files(card):
    out = []
    for p in card.rglob("*"):
        rel = p.relative_to(card)
        if rel.parts[0] in SYSTEM_DIRS or p.name.startswith("._"):
            continue
        if p.is_file():
            out.append(str(rel))
    return sorted(out)


def check(kind, src, card):
    if not card.is_dir() or not os.path.ismount(card) or card.resolve() == pathlib.Path("/"):
        stop("%s is not a mounted card" % card)
    ver, ent = load(kind, src)
    need = sum(int(s) for _, s, _ in ent) + (src / MANIFEST[kind]).stat().st_size
    free = shutil.disk_usage(card).free
    say("  card: %s, free %.1f MB, needed %.1f MB" % (card, free / 1e6, need / 1e6))
    if free < need + 4_000_000:
        stop("not enough free space on the card")
    present = card_files(card)
    if kind == "rescue":
        if present:
            stop("the rescue card must be an EMPTY card, found %d files, e.g. %s" % (len(present), present[:3]))
        say("  ok: card is empty")
        return ver, ent, ent
    # install card
    for bad in ("Swdlautorun.txt", "pmcp", "pmcp-rescue", "PMCP_RESCUE_README.txt", "pmcp-ratunek", "PMCP_RATUNEK_README.txt",
                "PMCP_CARD_MANIFEST.txt"):
        if (card / bad).exists():
            stop("the card already holds %s. Use an empty card, or a card with only M.I.B. 3.6.0 on it." % bad)
    if not present:
        say("  ok: card is empty")
        return ver, ent, ent
    mib = [e for e in ent if not e[2].startswith("pmcp/") and e[2] not in OVERLAY]
    known = {e[2] for e in ent}
    extra = [r for r in present if r not in known and not r.startswith("backup/")]
    if extra:
        stop("the card holds files that are not M.I.B. 3.6.0, e.g. %s. Use an empty card." % extra[:3])
    esd = card / "esd/Launcher-sda0.esd"
    if not esd.is_file() or hf(esd) != MIB_ESD_SHA:
        stop("esd/Launcher-sda0.esd on the card is not the M.I.B. 3.6.0 menu. Use an empty card.")
    for h, size, rel in mib:
        p = card / rel
        if not p.exists():
            if rel in GIT_ONLY:
                continue
            stop("M.I.B. file missing on the card: %s. Use an empty card." % rel)
        if hf(p) != h:
            stop("M.I.B. file on the card differs from M.I.B. 3.6.0: %s. Use an empty card." % rel)
    keep = sum(1 for r in present if r.startswith("backup/"))
    say("  ok: card holds M.I.B. 3.6.0 (%d files verified)%s" % (len(mib), ", backup/ with %d files left untouched" % keep if keep else ""))
    ours_ent = [e for e in ent if e not in mib]
    return ver, ent, ours_ent


def copy_one(src, dst, created):
    d = dst.parent
    todo = []
    while not d.exists():
        todo.append(d)
        d = d.parent
    for d in reversed(todo):
        d.mkdir()
        created.append(d)
    tmp = dst.with_name(dst.name + ".pmcp-tmp")
    shutil.copyfile(src, tmp)            # contents only: no extended attributes
    with open(tmp, "rb+") as f:
        os.fsync(f.fileno())
    os.replace(tmp, dst)
    created.append(dst)


def drop_appledouble(created):
    n = 0
    for p in created:
        ad = p.with_name("._" + p.name)
        if ad.is_file() and ad.stat().st_size <= 65536:
            with open(ad, "rb") as f:
                if f.read(4) == APPLEDOUBLE:
                    ad.unlink()
                    n += 1
    return n


def write(kind, src, card):
    ver, ent, todo = check(kind, src, card)
    say("  writing %d files for: %s" % (len(todo) + 1, ver))
    created = []
    order = [e for e in todo if e[2] != "Swdlautorun.txt"] + [e for e in todo if e[2] == "Swdlautorun.txt"]
    for i, (h, size, rel) in enumerate(order + [[None, None, MANIFEST[kind]]], 1):
        copy_one(src / rel, card / rel, created)
        if i % 50 == 0:
            say("    %d / %d files" % (i, len(order) + 1))
    os.sync()
    n = drop_appledouble(created)
    os.sync()
    say("  written: %d files%s" % (len(order) + 1, ", removed %d macOS ._ metadata files" % n if n else ""))


def verify(kind, src, card):
    ver, ent = load(kind, src)
    bad = []
    for h, size, rel in ent:
        p = card / rel
        if not p.exists():
            if kind == "install" and rel in GIT_ONLY:
                continue
            bad.append("missing " + rel)
        elif p.stat().st_size != int(size) or hf(p) != h:
            bad.append("differs " + rel)
    if hf(card / MANIFEST[kind]) != hf(src / MANIFEST[kind]):
        bad.append("differs " + MANIFEST[kind])
    if kind == "install" and ((card / "Swdlautorun.txt").exists() or (card / "pmcp/ODBLOKUJ_ETAP_B").exists()):
        bad.append("install card must not hold Swdlautorun.txt or pmcp/ODBLOKUJ_ETAP_B")
    if kind == "rescue" and ((card / "pmcp").exists() or not (card / "Swdlautorun.txt").exists()):
        bad.append("rescue card must hold Swdlautorun.txt and no pmcp/")
    # macOS metadata next to the files we write (the whole card for the rescue card, which starts empty); ._ files
    # that were already on a user's M.I.B. card are theirs and stay
    ours = [rel for _, _, rel in ent if kind == "rescue" or rel.startswith("pmcp/") or rel in OVERLAY]
    junk = [rel for rel in ours if (card / rel).with_name("._" + pathlib.PurePath(rel).name).exists()]
    if (card / "pmcp").is_dir():
        junk += [str(p.relative_to(card)) for p in (card / "pmcp").rglob("._*")]
    if junk:
        bad.append("macOS ._ files on the card: %s" % junk[:3])
    if bad:
        say("VERIFY FAILED (%d problems):" % len(bad))
        for b in bad[:20]:
            say("    " + b)
        sys.exit(1)
    say("  ok: all %d files on the card match the build (%s)" % (len(ent), ver))


def main():
    if len(sys.argv) != 5 or sys.argv[1] not in ("check", "write", "verify") or sys.argv[2] not in MANIFEST:
        sys.exit(__doc__)
    action, kind, src, card = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3]), pathlib.Path(sys.argv[4])
    {"check": check, "write": write, "verify": verify}[action](kind, src, card)


if __name__ == "__main__":
    main()
