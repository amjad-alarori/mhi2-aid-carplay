/* SPDX-License-Identifier: GPL-3.0-or-later
 * pmcp (MU1161): debug gate for the route-guidance receive log of tomasz-twardzicki's MU1427 B2 hook.
 *
 * The B2 hook (driver-hooks.S receive_guidance) logs every 0x5201/0x5202/0x5204 message with ipod_log and a
 * byte-by-byte ipod_print_bytes (one ipod_log/stdio write per byte) at level 0, so mm-ipod writes it to
 * /dev/shmem/iap2.log always, on the iAP2 receive thread. This gate runs instead of the jump back into that
 * logging block (publication_receive_hook's final `b b2_receive_resume`, after the guidance message has already
 * been published to /dev/ipod0/rgi-events):
 *   /dev/shmem/pmcp-rgi-debug exists -> continue into the original logging (unchanged behaviour);
 *   otherwise                        -> return 0 from the B2 hook exactly like its own epilogue, without logging.
 * State on entry (B2 frame): push {r4-r8, lr} done by receive_hook; r8 = message ID; sp as at b2_receive_resume.
 * open/close are the driver's own PLT imports; addresses are given by patch-log-gate.py (--defsym).
 */
.syntax unified
.arch armv7-a
.arm
.text
.global pmcp_log_gate
pmcp_log_gate:
    push {r0-r3, ip, lr}
    adr r0, debug_path
    mov r1, #0x80               /* O_RDONLY|O_NONBLOCK (QNX 000200): never wait on an odd flag file (FIFO, link) */
    bl open_plt
    cmp r0, #0
    blt no_log
    bl close_plt
    pop {r0-r3, ip, lr}
    b b2_receive_resume         /* original logging */
no_log:
    pop {r0-r3, ip, lr}
    mov r0, #0                  /* B2 handled the message: same result as its own epilogue */
    pop {r4-r8, pc}
debug_path:
    .asciz "/dev/shmem/pmcp-rgi-debug"
    .balign 4
