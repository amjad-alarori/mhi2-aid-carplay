#!/usr/bin/env python3
"""Build MU1161/791 core.so variants from the shared 791 build (sha256 00b48a8f...).

The base is the core.so shipped for MU1102/791 and MU1367/791 (omonob, before v1.2.0),
which issue omonob#5 reports working unchanged on MU1161 (lsd.jxe 55,830,309 bytes)
with AID 791. No AES-offset change: that fix is for MU1427's older libairplay only.

Every patch site is checked against its stock instruction before writing, values are
written as `mov rD, #rotated-imm8` when encodable, else ARMv7 `movw rD, #imm16` (only 430;
rD taken from the stock instruction), and nothing
is written unless the input hash is exactly the expected base.

Sources of the patch sites:
  maxFPS 0x2a70, keyframe 0x4370/0x452c, URL 0x8130, safe area 0x2b94..0x2ba4:
      tomasz-twardzicki/MHI2-Carplay-Maps MU1427/791_AID12.3/tuning/patch-core-tuning.py
  keyframe 5, maxFPS 30, safe-area height as movw:
      diasdio via ramasauskas/MHI2-Carplay-Maps patches/mu1367-791-artifact-fix

Usage: build_core.py base_core.so out_dir
"""
import hashlib
import json
import pathlib
import struct
import sys

BASE_SHA = "00b48a8fe876e6ff405124b87ed9eace1bcb079220ff7f02b866f42676477a4a"
BASE_SIZE = 75099

# name -> (file offset, stock instruction)
SITES = {
    "max_fps":  [(0x2A70, 0xE3A02028)],                        # mov r2, #40
    "keyframe": [(0x4370, 0xE3A02014), (0x452C, 0xE3A02014)],  # mov r2, #20 (check, log)
    "x":        [(0x2BA4, 0xE3A000A0)],                        # mov r0, #160
    "y":        [(0x2B94, 0xE3A01014)],                        # mov r1, #20
    "w":        [(0x2B98, 0xE3A02E1E)],                        # mov r2, #480
    "h":        [(0x2B9C, 0xE3A03F6E)],                        # mov r3, #440
    # declared physical size of the 800x480 cluster screen in mm (keys widthPhysical/heightPhysical, strings 0x80e0/
    # 0x80f0, via set_int); mathsls sets 240x144 here (same sites, only the immediate differs). UNVERIFIED whether
    # this changes the card size: mathsls's README also says iOS keeps the cluster at @2x (400x240 pt).
    "phys_w":   [(0x2AD0, 0xE3A020A0)],                        # mov r2, #160
    "phys_h":   [(0x2AF0, 0xE3A02060)],                        # mov r2, #96
}
# Must stay untouched on MU1161/MU1367 (MU1427-only AES fix site).
AES_SITE = (0x5284, 0xE2880F72)                                # add r0, r8, #0x1c8

URL_OFF, URL_LEN = 0x8130, 32
# Long URLs may use 0x8130..0x8193 (100 bytes incl. NUL): the strings after the 32-byte slot are only
# printf text for log_status/log_object (disassembly); "safeArea" at 0x8194 stays.
URL_LONG_LEN = 0x64
URL_REGION_SHA = "4507e174af5a15409f11f8c26bc2446948681ff3c07b29de7636eb00950b493d"
URLS = {"map": b"maps:/car/instrumentcluster/map",
        "map-card": b"maps:/car/instrumentcluster",
        # Parameter names from harman-f (MU1440). There, query strings did not break
        # the cluster, but only showETA=yes (Waze) was observed; showETA=no and showSpeedLimit are untested values.
        "card-noeta": b"maps:/car/instrumentcluster?showETA=no",
        "card-noeta-left": b"maps:/car/instrumentcluster?showETA=no&maneuverLayout=leftAligned",
        "card-noeta-right": b"maps:/car/instrumentcluster?showETA=no&maneuverLayout=rightAligned",
        "card-noeta-speed": b"maps:/car/instrumentcluster?showETA=no&showSpeedLimit=yes",
        "map-speed": b"maps:/car/instrumentcluster/map?showSpeedLimit=yes"}

VIEW_W, VIEW_H = 800, 480

# First in-car test set for MU1161 + AID 791. In Tomasz's MU1427 tests (160x96 mm) a safe-area height of 312 gave
# a blank card and 240 no card; his final card height is 364, mathsls's (240x144 mm) is 340. Card variants keep
# h >= 340, except url-card-hybrid (296), which relies on the unverified density assumption (see phys_w).
VARIANTS = {
    "card-narrow":   dict(max_fps=30, keyframe=5, url="map-card", area=(200, 80, 400, 380)),
    "card-wide":     dict(max_fps=30, keyframe=5, url="map-card", area=(160, 80, 480, 380)),
    "card-narrow-hi": dict(max_fps=30, keyframe=5, url="map-card", area=(200, 64, 400, 364)),
    "map-diasdio":   dict(max_fps=30, keyframe=5, url="map",      area=(160, 20, 480, 430)),
    "map-crop340":   dict(max_fps=30, keyframe=5, url="map",      area=(160, 20, 480, 340)),
    # A/B against diasdio's keyframe 5: harman-f's proposal of fewer periodic IDRs
    # (OMONOB_791_30FPS_1S_IDR_TEST_PLAN). Use with the patched bridge.
    "map-kf30":      dict(max_fps=30, keyframe=30, url="map",     area=(160, 20, 480, 430)),
    # Package C: iPhone map parameters (long URLs). Card variants keep h >= 364 (see above).
    "url-card-noeta":       dict(max_fps=30, keyframe=5, url="card-noeta",       area=(200, 80, 400, 380)),
    "url-card-noeta-left":  dict(max_fps=30, keyframe=5, url="card-noeta-left",  area=(160, 80, 480, 380)),
    "url-card-noeta-right": dict(max_fps=30, keyframe=5, url="card-noeta-right", area=(160, 80, 480, 380)),
    "url-card-noeta-speed": dict(max_fps=30, keyframe=5, url="card-noeta-speed", area=(200, 80, 400, 380)),
    "url-map-speed":        dict(max_fps=30, keyframe=5, url="map-speed",        area=(160, 20, 480, 430)),
    # Hybrid mathsls + Tomasz: Tomasz's default width (x 200, w 400) with mathsls's 240x144 mm density (lower card,
    # ~56 px), moved down so the card starts below the VW distance/time bar (stream row ~111 on our AID photo),
    # iPhone ETA off because the VW bar shows it (package E). Card top = safe y + 4 = 112. With big dials the card
    # corners touch the dials in the page model (-1 px, model accuracy +-15 px), as with Tomasz's default (-4 px).
    # (First version 2026-10-21 had mathsls's width, x 240 w 320: a6533a68...)
    "url-card-hybrid":      dict(max_fps=30, keyframe=5, url="card-noeta",       area=(200, 108, 400, 296), phys=(240, 144)),
    # Same card position (the card hangs from the safe-area top), bottom at row 460 like Tomasz's final layout, so the
    # height (352) is above every tested blank-card value without relying on the density assumption. Start here.
    "url-card-hybrid-tall": dict(max_fps=30, keyframe=5, url="card-noeta",       area=(200, 108, 400, 352), phys=(240, 144)),
    # Map without the card (2026-10-23 in the car: url-map-speed showed no card in Apple Maps nor Google Maps; ETA and
    # distance come from the native VW bar, package rg). url-map-speed's area (bottom row 450) put Google's position
    # marker too low; url-card-hybrid's area (bottom 404) had it fully visible. "-hi" moves the bottom up to row 364.
    "url-map-hybrid":       dict(max_fps=30, keyframe=5, url="map-speed",        area=(200, 108, 400, 296), phys=(240, 144)),
    "url-map-hybrid-hi":    dict(max_fps=30, keyframe=5, url="map-speed",        area=(200, 108, 400, 256), phys=(240, 144)),
    # 2026-10-24 photos (url-map-hybrid, Google Maps): the marker sits ~150-165 stream columns right of the map-window
    # centre (column 400, both dial layouts, aid-frame-map.html). Same area moved left by 80 and by 160 columns.
    "url-map-hybrid-l80":   dict(max_fps=30, keyframe=5, url="map-speed",        area=(120, 108, 400, 296), phys=(240, 144)),
    "url-map-hybrid-l160":  dict(max_fps=30, keyframe=5, url="map-speed",        area=(40, 108, 400, 296), phys=(240, 144)),
    # Final in-car set (user, 2026-10-24): url-map-hybrid's area with clean URLs (showSpeedLimit showed nothing),
    # the same with the iPhone card, and the clean map moved slightly (40 columns) left.
    "map-clean":            dict(max_fps=30, keyframe=5, url="map",              area=(200, 108, 400, 296), phys=(240, 144)),
    "card-clean":           dict(max_fps=30, keyframe=5, url="map-card",         area=(200, 108, 400, 296), phys=(240, 144)),
    "map-clean-l40":        dict(max_fps=30, keyframe=5, url="map",              area=(160, 108, 400, 296), phys=(240, 144)),
    # mathsls's MU1161/791 layout (area 240/60/320/340, 240x144 mm, mathsls commit 0bd8e31) with the clean map URL: narrower and
    # taller (closer to square) than map-clean, centred on column 400 (user, 2026-10-24).
    "map-square":           dict(max_fps=30, keyframe=5, url="map",              area=(240, 60, 320, 340), phys=(240, 144)),
    # Latency A/B on map-square (map ~1 s behind the head unit, user 2026-10-25). The 791 decoder is the bottleneck
    # (omonob#10: Tomasz's 40 -> 30 fps removed lag; forced IDRs are 13-76 KB against ~1.4 KB P-frames).
    # fps20: fewer frames for the decoder (KelvinPH tested 20 fps on MU1367/791); kf10: half the forced IDRs;
    # fps40: the base core's own value, kept on purpose by omonob (v1.2.0) and mathsls (same car: B8 MU1161/791, "no lag").
    "map-square-fps40":     dict(max_fps=40, keyframe=5, url="map",              area=(240, 60, 320, 340), phys=(240, 144)),
    # fps40-kf10: 40 fps declared with half the forced IDRs (user's question: lighter than 30 fps + IDR every 5?).
    "map-square-fps40-kf10": dict(max_fps=40, keyframe=10, url="map",            area=(240, 60, 320, 340), phys=(240, 144)),
    "map-square-fps20":     dict(max_fps=20, keyframe=5, url="map",              area=(240, 60, 320, 340), phys=(240, 144)),
    "map-square-kf10":      dict(max_fps=30, keyframe=10, url="map",             area=(240, 60, 320, 340), phys=(240, 144)),
}


def encode(stock, value):
    """Same encodings as the in-car tested builds: unchanged values keep the stock
    instruction, otherwise `mov rD, #rotated-imm` (Tomasz), else `movw rD, #imm16`
    (diasdio's height 430)."""
    if not 0 <= value <= 0xFFFF:
        sys.exit("value %d out of range" % value)
    if decode(stock) == value:
        return stock
    for rot in range(16):
        imm8 = ((value << 2 * rot) | (value >> (32 - 2 * rot))) & 0xFFFFFFFF if rot else value
        if imm8 <= 0xFF:
            return (stock & 0xFFFFF000) | (rot << 8) | imm8
    rd = (stock >> 12) & 0xF
    return 0xE3000000 | ((value >> 12) << 16) | (rd << 12) | (value & 0xFFF)


def decode(ins):
    """Immediate of `mov rD, #rot-imm` (E3A0....) or `movw rD, #imm16` (E30.....)."""
    if ins & 0xFFF00000 == 0xE3A00000:
        rot, imm8 = (ins >> 8) & 0xF, ins & 0xFF
        return ((imm8 >> 2 * rot) | (imm8 << (32 - 2 * rot))) & 0xFFFFFFFF if rot else imm8
    if ins & 0xFFF00000 == 0xE3000000:
        return ((ins >> 16) & 0xF) << 12 | (ins & 0xFFF)
    sys.exit("not a mov/movw immediate: %08x" % ins)


def word(d, off):
    return struct.unpack_from("<I", d, off)[0]


def build(base, spec):
    d = bytearray(base)
    x, y, w, h = spec["area"]
    if w < 1 or h < 1 or x + w > VIEW_W or y + h > VIEW_H:
        sys.exit("safe area %r outside %dx%d" % (spec["area"], VIEW_W, VIEW_H))
    pw, ph = spec.get("phys", (160, 96))
    values = {"max_fps": spec["max_fps"], "keyframe": spec["keyframe"],
              "x": x, "y": y, "w": w, "h": h, "phys_w": pw, "phys_h": ph}
    for name, sites in SITES.items():
        for off, stock in sites:
            if word(d, off) != stock:
                sys.exit("unexpected instruction at %#x" % off)
            struct.pack_into("<I", d, off, encode(stock, values[name]))
    if d[URL_OFF:URL_OFF + URL_LEN] != URLS["map"] + b"\0":
        sys.exit("unexpected cluster URL at %#x" % URL_OFF)
    url = URLS[spec["url"]]
    if len(url) < URL_LEN:
        d[URL_OFF:URL_OFF + URL_LEN] = url.ljust(URL_LEN, b"\0")
    else:
        if hashlib.sha256(bytes(d[URL_OFF:URL_OFF + URL_LONG_LEN])).hexdigest() != URL_REGION_SHA:
            sys.exit("unexpected bytes in the long URL region")
        if len(url) >= URL_LONG_LEN or b"\0" in url:
            sys.exit("URL too long: %d > %d" % (len(url), URL_LONG_LEN - 1))
        d[URL_OFF:URL_OFF + URL_LONG_LEN] = url.ljust(URL_LONG_LEN, b"\0")
    return bytes(d)


def verify(base, out, spec):
    """Re-read every site and require that only the intended bytes changed."""
    assert len(out) == len(base)
    url = URLS[spec["url"]]
    allowed = set(range(URL_OFF, URL_OFF + (URL_LEN if len(url) < URL_LEN else URL_LONG_LEN)))
    for sites in SITES.values():
        for off, _ in sites:
            allowed.update(range(off, off + 4))
    diff = [i for i in range(len(base)) if base[i] != out[i]]
    assert all(i in allowed for i in diff), "bytes changed outside patch sites"
    assert word(out, AES_SITE[0]) == AES_SITE[1], "AES site modified"
    x, y, w, h = spec["area"]
    pw, ph = spec.get("phys", (160, 96))
    want = {"max_fps": spec["max_fps"], "keyframe": spec["keyframe"],
            "x": x, "y": y, "w": w, "h": h, "phys_w": pw, "phys_h": ph}
    for name, sites in SITES.items():
        for off, stock in sites:
            ins = word(out, off)
            assert ins & 0xF000 == stock & 0xF000, "register changed at %#x" % off
            assert decode(ins) == want[name], (name, decode(ins))
    region = out[URL_OFF:URL_OFF + (URL_LEN if len(url) < URL_LEN else URL_LONG_LEN)]
    assert region.rstrip(b"\0") == url and region[len(url)] == 0
    assert out[0x8194:0x819d] == b"safeArea\0", "safeArea key touched"


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, out_dir = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    base = src.read_bytes()
    if len(base) != BASE_SIZE or hashlib.sha256(base).hexdigest() != BASE_SHA:
        sys.exit("unexpected base core.so (size %d, sha256 %s), nothing written"
                 % (len(base), hashlib.sha256(base).hexdigest()))
    if word(base, AES_SITE[0]) != AES_SITE[1]:
        sys.exit("base AES site differs, nothing written")
    built = {}
    for name, spec in VARIANTS.items():
        out = build(base, spec)
        verify(base, out, spec)
        built[name] = out
    manifest = {"base_sha256": BASE_SHA, "variants": {}}
    for name, out in built.items():
        path = out_dir / name / "core.so"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(out)
        sha = hashlib.sha256(out).hexdigest()
        manifest["variants"][name] = dict(VARIANTS[name], sha256=sha, size=len(out))
        print("%-15s %s" % (name, sha))
    (out_dir / "MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
