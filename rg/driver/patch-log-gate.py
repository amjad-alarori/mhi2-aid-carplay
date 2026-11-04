#!/usr/bin/env python3
"""pmcp: add the route-guidance log gate (log-gate.S) to our patched MU1161 iAP2 driver. Never modifies the input.

Input  = rg/build.sh output ipod-drvr-iap2.so (Tomasz's B2+B3+B4 chain on our driver), sha256 76926bde...
Output = the same driver plus 76 bytes appended to the injected RX segment at 0xb571c, its PT_LOAD filesz/memsz grown
by that much, and one branch changed: publication_receive_hook's final `b b2_receive_resume` (0xb5568) -> the gate.
Every other byte must stay identical (checked). Usage: patch-log-gate.py IN GATE_BIN OUT
"""
import hashlib, struct, sys

IN_SHA = "76926bde9bdf1e06fdfe57fd324bbd8772bcb2a98a58ac444b4822e25a331b48"
SEG_VADDR, SEG_END = 0xB5000, 0xB571C
BRANCH_AT, BRANCH_OLD, RESUME = 0xB5568, 0xEAFFFEED, 0xB5124
OPEN_PLT, CLOSE_PLT = 0x4CB8, 0x4D3C


def sha(b):
    return hashlib.sha256(b).hexdigest()


def b_to(at, target, link=False):
    delta = target - at - 8
    assert delta % 4 == 0 and -(1 << 25) <= delta < (1 << 25)
    return (0xE << 28) | (0xB000000 if link else 0xA000000) | ((delta >> 2) & 0xFFFFFF)


def main():
    src, gate_path, out = sys.argv[1:4]
    data = open(src, "rb").read()
    gate = open(gate_path, "rb").read()
    assert sha(data) == IN_SHA, "input is not our patched driver 76926bde"
    assert len(data) == SEG_END, "injected segment is not at the end of the file"
    assert len(gate) % 4 == 0 and len(gate) <= 0x1000 - (SEG_END - SEG_VADDR)
    # The gate must be exactly what log-gate.S says: check the branch/call words against the expected targets.
    words = struct.unpack("<%dI" % (len(gate) // 4), gate)
    at = lambda i: SEG_END + 4 * i
    assert words[0] == 0xE92D500F and words[1] == 0xE28F0024 and words[2] == 0xE3A01080   # push; adr r0; O_RDONLY|O_NONBLOCK
    assert words[3] == b_to(at(3), OPEN_PLT, True) and words[4] == 0xE3500000 and words[5] == 0xBA000002
    assert words[6] == b_to(at(6), CLOSE_PLT, True) and words[7] == 0xE8BD500F and words[8] == b_to(at(8), RESUME)
    assert words[9] == 0xE8BD500F and words[10] == 0xE3A00000 and words[11] == 0xE8BD81F0
    assert gate[0x30:0x30 + 26] == b"/dev/shmem/pmcp-rgi-debug\0"
    # The jump being redirected: last instruction of publication_receive_hook.
    assert struct.unpack_from("<I", data, BRANCH_AT)[0] == BRANCH_OLD == b_to(BRANCH_AT, RESUME)
    assert struct.unpack_from("<I", data, BRANCH_AT - 4)[0] == 0xE2828C52      # add r8, r2, #0x5200
    out_data = bytearray(data)
    struct.pack_into("<I", out_data, BRANCH_AT, b_to(BRANCH_AT, SEG_END))
    # Grow the PT_LOAD that maps the injected code.
    phoff, = struct.unpack_from("<I", data, 0x1C)
    phentsize, phnum = struct.unpack_from("<HH", data, 0x2A)
    grown = []
    for i in range(phnum):
        o = phoff + i * phentsize
        p_type, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_flags, p_align = struct.unpack_from("<8I", data, o)
        if p_type == 1 and p_vaddr == SEG_VADDR:
            assert p_offset == SEG_VADDR and p_filesz == p_memsz == SEG_END - SEG_VADDR and p_flags == 5
            struct.pack_into("<II", out_data, o + 16, p_filesz + len(gate), p_memsz + len(gate))
            grown.append((o + 16, o + 20))
    assert len(grown) == 1, "injected PT_LOAD not found exactly once"
    out_data += gate
    # Only the intended bytes differ.
    allowed = set(range(BRANCH_AT, BRANCH_AT + 4))
    for f, m in grown:
        allowed.update(range(f, f + 4)); allowed.update(range(m, m + 4))
    bad = [i for i in range(len(data)) if data[i] != out_data[i] and i not in allowed]
    assert not bad, "unexpected changes at %s" % [hex(i) for i in bad[:8]]
    open(out, "wb").write(out_data)
    print("ipod-drvr-iap2.so log-gate %d bytes sha256=%s" % (len(out_data), sha(bytes(out_data))))


if __name__ == "__main__":
    main()
