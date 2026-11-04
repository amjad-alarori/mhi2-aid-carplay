#!/usr/bin/env python3
"""Emulates the log gate in the real patched driver bytes (unicorn, ARM). Usage:
   <python with unicorn> -I rg/driver/test_log_gate.py ORIGINAL.so GATED.so
Starts at publication_receive_hook (0xb5544) with a B2 frame on the stack, stubs publication_enqueue / open / close,
and checks: flag absent -> returns to the B2 caller with r0=0, r4-r8/sp restored, no logging block entered;
flag present -> reaches the original logging block (0xb5124) in exactly the state the unpatched driver reaches it."""
import struct, sys
from unicorn import Uc, UC_ARCH_ARM, UC_MODE_ARM, UC_HOOK_CODE
from unicorn.arm_const import *

WRAPPER, ENQUEUE, RESUME, OPEN, CLOSE = 0xB5544, 0xB5450, 0xB5124, 0x4CB8, 0x4D3C
STACK, RET = 0x200000, 0x300000
FAILS = []
REGS = [UC_ARM_REG_R0, UC_ARM_REG_R1, UC_ARM_REG_R2, UC_ARM_REG_R3, UC_ARM_REG_R4, UC_ARM_REG_R5, UC_ARM_REG_R6,
        UC_ARM_REG_R7, UC_ARM_REG_R8, UC_ARM_REG_R12, UC_ARM_REG_SP, UC_ARM_REG_LR, UC_ARM_REG_CPSR]


def check(c, what):
    print(("ok   " if c else "FAIL ") + what)
    if not c:
        FAILS.append(what)


def run(path, flag, fd=7):
    data = open(path, "rb").read()
    uc = Uc(UC_ARCH_ARM, UC_MODE_ARM)
    uc.mem_map(0, 0xB6000 + 0x1000)
    uc.mem_write(0, data[:0x26D88])                       # text PT_LOAD (offset == vaddr)
    uc.mem_write(0xB5000, data[0xB5000:])                 # injected RX PT_LOAD
    uc.mem_map(STACK - 0x10000, 0x20000)
    uc.mem_map(RET, 0x1000)
    calls = {"open": 0, "close": 0, "enqueue": 0, "path": None}
    # B2 receive_hook state: caller's r4-r8 saved by push {r4-r8, lr}; working r4..r8; r2 = low ID byte.
    caller = {UC_ARM_REG_R4: 0x44, UC_ARM_REG_R5: 0x55, UC_ARM_REG_R6: 0x66, UC_ARM_REG_R7: 0x77, UC_ARM_REG_R8: 0x88}
    sp = STACK - 24
    uc.mem_write(sp, struct.pack("<6I", 0x44, 0x55, 0x66, 0x77, 0x88, RET))
    for r, v in {UC_ARM_REG_R0: 0x1000, UC_ARM_REG_R1: 0x2000, UC_ARM_REG_R2: 1, UC_ARM_REG_R3: 0x3333,
                 UC_ARM_REG_R4: 0xD00, UC_ARM_REG_R5: 0xE00, UC_ARM_REG_R6: 0xF00, UC_ARM_REG_R7: 40,
                 UC_ARM_REG_R8: 0x8888, UC_ARM_REG_R12: 0xC0C0, UC_ARM_REG_SP: sp, UC_ARM_REG_LR: 0xBADBAD}.items():
        uc.reg_write(r, v)

    def hook(uc, addr, size, _):
        if addr == ENQUEUE:
            calls["enqueue"] += 1
            uc.reg_write(UC_ARM_REG_PC, uc.reg_read(UC_ARM_REG_LR))
        elif addr == OPEN:
            calls["open"] += 1
            p = uc.mem_read(uc.reg_read(UC_ARM_REG_R0), 64).split(b"\0")[0]
            calls["path"] = (p, uc.reg_read(UC_ARM_REG_R1))
            uc.reg_write(UC_ARM_REG_R0, fd if flag else 0xFFFFFFFF)
            uc.reg_write(UC_ARM_REG_PC, uc.reg_read(UC_ARM_REG_LR))
        elif addr == CLOSE:
            calls["close"] += 1
            calls["closed_fd"] = uc.reg_read(UC_ARM_REG_R0)
            uc.reg_write(UC_ARM_REG_R0, 0)
            uc.reg_write(UC_ARM_REG_PC, uc.reg_read(UC_ARM_REG_LR))
        elif addr in (RESUME, RET):
            uc.emu_stop()
    uc.hook_add(UC_HOOK_CODE, hook)
    uc.emu_start(WRAPPER, 0, count=200)
    state = {r: uc.reg_read(r) for r in REGS}
    # Condition flags (NZCV) differ after the gate's `cmp`; only mode/state bits must match. main() checks that the
    # logging block sets or ignores the flags before any conditional instruction (it calls ipod_log first).
    state[UC_ARM_REG_CPSR] &= 0x0FFFFFFF
    state["stack"] = bytes(uc.mem_read(STACK - 0x80, 0x80))
    return uc.reg_read(UC_ARM_REG_PC), state, calls, caller, sp


def main():
    original, gated = sys.argv[1:3]
    code = open(gated, "rb").read()
    block = struct.unpack_from("<8I", code, RESUME)          # 0xb5124 .. the first bl ipod_log
    first_bl = next(i for i, w in enumerate(block) if (w >> 24) & 0xF == 0xB)
    check(all(w >> 28 == 0xE for w in block[:first_bl + 1]), "logging block: no conditional instruction before its first call")
    pc0, s0, c0, _, sp = run(original, False)
    check(pc0 == RESUME and c0["open"] == 0, "original driver: wrapper goes straight to the logging block")
    pc, s, c, caller, _ = run(gated, False)
    check(pc == RET, "flag absent: returns to the B2 caller")
    check(s[UC_ARM_REG_R0] == 0, "flag absent: r0 = 0 (handled), like the B2 epilogue")
    check(all(s[r] == v for r, v in caller.items()), "flag absent: caller r4-r8 restored")
    check(s[UC_ARM_REG_SP] == sp + 24, "flag absent: stack balanced")
    check(c["open"] == 1 and c["close"] == 0 and c["enqueue"] == 1, "flag absent: published once, one open, no close")
    check(c["path"] == (b"/dev/shmem/pmcp-rgi-debug", 0x80), "open(\"/dev/shmem/pmcp-rgi-debug\", O_RDONLY|O_NONBLOCK)")
    pc, s, c, _, _ = run(gated, True)
    check(pc == RESUME, "flag present: continues into the original logging block")
    diff = sorted(str(k) for k in s0 if s[k] != s0[k])
    check(not diff, "flag present: registers and stack identical to the unpatched driver at that point %s" % diff)
    check(c["open"] == 1 and c["close"] == 1 and c["closed_fd"] == 7 and c["enqueue"] == 1, "flag present: fd closed")
    check(s[UC_ARM_REG_R8] == 0x5201, "r8 = message ID 0x5201 (replaced add kept)")
    pc, s, c, _, _ = run(gated, True, fd=0)
    check(pc == RESUME and c["close"] == 1 and c["closed_fd"] == 0 and s == s0, "flag present, fd 0: closed, same state")
    print("LOG GATE FAILED=%d" % len(FAILS))
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
