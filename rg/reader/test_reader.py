#!/usr/bin/env python3
"""Host tests for the pmcp rgi-observer variant (rg/reader/reader.c).

A hung driver is simulated by SIGSTOP on the worker: from the supervisor's side a stopped worker is exactly a worker
blocked in the device read (no frames). SIGCONT = the driver answers late. SIGKILL of the worker = worker died.
Usage: python3 -I rg/reader/test_reader.py   (needs cc; builds with short test timings)
"""
import os, signal, struct, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
SNAP, STRIDE = 33088, 2064
FAILS = []


def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        FAILS.append(what)


def tlv(tid, data):
    return struct.pack(">HH", 4 + len(data), tid) + data


def snapshot(seq, session=7):
    b = bytearray(SNAP)
    count = min(seq, 16)
    struct.pack_into("<4sIIIIIIIIIII", b, 0, b"RGI1", 1, SNAP, 0, session, seq, count, 0, 0, 1 if seq else 0, 100, 5)
    for s in range(seq - count + 1, seq + 1):
        payload = tlv(1, b"\x01") + tlv(7, struct.pack(">I", 1000 + s))
        at = 64 + ((s - 1) & 15) * STRIDE
        struct.pack_into("<IHHII", b, at, s, 0x5201, len(payload), session, 0)
        b[at + 16:at + 16 + len(payload)] = payload
    return bytes(b)


class Case:
    def __init__(self, binary, work):
        self.binary, self.work = binary, work
        self.source = os.path.join(work, "source")
        self.out = os.path.join(work, "ram")
        self.proc = None

    def write_source(self, seq):
        tmp = self.source + ".tmp"
        with open(tmp, "wb") as f:
            f.write(snapshot(seq))
        os.replace(tmp, self.source)

    def start(self):
        self.proc = subprocess.Popen([self.binary, "serve", self.source, self.out],
                                     stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        return self.proc

    def mailbox(self):
        with open(os.path.join(self.out, "latest.bin"), "rb") as f:
            b = f.read()
        magic, ver, size, serial, kind, detail = struct.unpack_from("<4sIIIII", b, 0)
        assert magic == b"RGM1" and size == len(b)
        return {"serial": serial, "kind": kind, "detail": detail,
                "seq": struct.unpack_from("<I", b, 32 + 20)[0] if kind == 1 else None}

    def status(self):
        with open(os.path.join(self.out, "status.txt")) as f:
            line = f.read().strip()
        d = {}
        for part in line.split()[1:]:
            k, _, v = part.partition("=")
            d[k] = v
        return d

    def wait(self, pred, seconds):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            try:
                if pred():
                    return True
            except (FileNotFoundError, AssertionError, struct.error, ValueError):
                pass
            time.sleep(0.02)
        return False

    def worker(self):
        return int(self.status()["worker"])

    def stop(self):
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=4)
            except subprocess.TimeoutExpired:
                self.proc.kill()


def build(work):
    binary = os.path.join(work, "reader")
    cc = ["cc", "-std=c99", "-O2", "-Wall", "-Wextra", "-Werror",
          "-DSILENT_MS=1000u", "-DKILL_MS=3000u", "-DRESPAWN_MIN_MS=300u", "-DRESPAWN_MAX_MS=1200u",
          os.path.join(HERE, "reader.c"), "-o", binary]
    subprocess.run(cc, check=True)
    return binary


def main():
    with tempfile.TemporaryDirectory(prefix="pmcp-reader-") as work:
        binary = build(work)
        t = Case(binary, work)
        t.write_source(2)
        t.start()
        try:
            check(t.wait(lambda: t.mailbox()["kind"] == 1 and t.mailbox()["seq"] == 2, 3), "A snapshot published (kind 1, seq 2)")
            check(t.status().get("build") == "pmcp-r1", "A status has build=pmcp-r1")
            w1 = t.worker()
            pid_file = open(os.path.join(t.out, "reader.pid")).read().strip()
            check(pid_file == str(t.proc.pid), "A reader.pid = supervisor pid")

            # B: driver hangs 2 s -> one NO_OP after ~1 s, supervisor alive, heartbeat continues, late frames resume.
            os.kill(w1, signal.SIGSTOP)
            t0 = time.monotonic()
            check(t.wait(lambda: t.mailbox()["kind"] == 2 and t.mailbox()["detail"] == 5, 2.5), "B NO_OP (invalidate detail 5) during hang")
            dt = time.monotonic() - t0
            check(0.8 <= dt <= 2.0, "B NO_OP after ~1 s (%.2f s)" % dt)
            s1 = t.mailbox()["serial"]
            check(t.wait(lambda: t.mailbox()["serial"] > s1 and t.mailbox()["kind"] == 2, 2.5), "B heartbeat keeps going, still invalid")
            check(t.proc.poll() is None, "B supervisor still running")
            check(t.status().get("timeouts") == "1", "B status timeouts=1")
            os.kill(w1, signal.SIGCONT)
            time.sleep(0.6)
            check(t.mailbox()["kind"] == 2, "B late frame with the same data does not revive old guidance")
            t.write_source(3)
            check(t.wait(lambda: t.mailbox()["kind"] == 1 and t.mailbox()["seq"] == 3, 2), "B fresh data after the hang -> snapshot seq 3")
            check(t.worker() == w1 and t.status().get("kills") == "0", "B same worker, no kill")

            # C: driver hangs > KILL_MS -> kill, reap, new worker, recovery.
            os.kill(w1, signal.SIGSTOP)
            check(t.wait(lambda: t.status().get("kills") == "1", 5), "C worker killed after the kill deadline")
            check(t.wait(lambda: t.status().get("restarts") == "1" and t.worker() not in (w1, -1), 3), "C new worker started after reap")
            w2 = t.worker()
            try:
                os.kill(w1, 0)
                gone = False
            except ProcessLookupError:
                gone = True
            check(gone, "C old worker reaped (no zombie left)")
            check(t.mailbox()["kind"] == 2, "C guidance still off right after the restart")
            t.write_source(4)
            check(t.wait(lambda: t.mailbox()["kind"] == 1 and t.mailbox()["seq"] == 4, 2), "C new worker delivers fresh data")

            # D: worker dies (pipe EOF) -> invalidate detail 6, restart.
            os.kill(w2, signal.SIGKILL)
            check(t.wait(lambda: t.mailbox()["kind"] == 2 and t.mailbox()["detail"] == 6, 2), "D EOF -> invalidate detail 6")
            check(t.wait(lambda: t.status().get("restarts") == "2" and t.worker() not in (w2, -1), 3), "D replacement worker")
            t.write_source(5)
            check(t.wait(lambda: t.mailbox()["kind"] == 1 and t.mailbox()["seq"] == 5, 2), "D recovery after EOF")
            check(t.status().get("eofs") == "1", "D status eofs=1")

            # E: second start while the first lives -> ALREADY_RUNNING, nothing touched.
            serial_before = t.mailbox()["serial"]
            r = subprocess.run([binary, "serve", t.source, t.out], capture_output=True, text=True, timeout=5)
            check(r.returncode == 0 and "CPMAP_GUIDANCE_ALREADY_RUNNING" in r.stdout, "E second start refused while the first is alive")
            check(open(os.path.join(t.out, "reader.pid")).read().strip() == str(t.proc.pid), "E reader.pid unchanged")
            check(t.mailbox()["serial"] >= serial_before and t.proc.poll() is None, "E first reader unaffected")

            # F: stop command.
            r = subprocess.run([binary, "stop", t.out], capture_output=True, text=True, timeout=6)
            check(r.returncode == 0 and "CPMAP_GUIDANCE_STOPPED" in r.stdout, "F stop confirmed")
            t.proc.wait(timeout=3)
            st = t.status()
            check(st.get("reason") == "1" and t.mailbox()["kind"] == 5, "F END record, reason=1 (stop)")
            check(not os.path.exists(os.path.join(t.out, "reader.pid")), "F reader.pid removed")
        finally:
            t.stop()

        # G: reader killed hard (no cleanup), stale stop file and pid file left -> next start takes the directory over.
        t.write_source(6)
        t.start()
        check(t.wait(lambda: t.mailbox()["kind"] == 1 and t.mailbox()["seq"] == 6, 3), "G restarted on the old directory (stop file removed)")
        w = t.worker()
        t.proc.kill(); t.proc.wait()
        os.kill(w, signal.SIGKILL)
        open(os.path.join(t.out, "stop"), "w").close()
        time.sleep(0.2)
        t.start()
        try:
            check(t.wait(lambda: open(os.path.join(t.out, "reader.pid")).read().strip() == str(t.proc.pid)
                         and t.status().get("polls") != "0" and t.mailbox()["kind"] == 1, 3), "G takeover after a hard kill")
            got = open(os.path.join(t.out, "reader.pid")).read().strip()
            check(got == str(t.proc.pid), "G new reader.pid (%s vs %s)" % (got, t.proc.pid))
            check(t.proc.poll() is None, "G running")
        finally:
            t.stop()

        # H: two starts at the same moment -> exactly one supervisor, the other says ALREADY_RUNNING (review M1).
        for attempt in range(6):
            out = os.path.join(work, "race%d" % attempt)
            ps = [subprocess.Popen([binary, "serve", t.source, out], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
                  for _ in range(2)]
            time.sleep(1.5)
            alive = [p for p in ps if p.poll() is None]
            done = [p for p in ps if p.poll() is not None]
            msg = [p.stdout.read() for p in done]
            ok = len(alive) == 1 and len(done) == 1 and done[0].returncode == 0 and "ALREADY_RUNNING" in msg[0]
            pid_ok = ok and open(os.path.join(out, "reader.pid")).read().strip() == str(alive[0].pid)
            check(ok and pid_ok, "H%d concurrent starts -> one owner with its reader.pid" % attempt)
            for p in alive:
                p.terminate(); p.wait(timeout=4)

        # I: start-live daemon mode, second start-live -> ALREADY_RUNNING, stop then immediate start-live -> new reader.
        live = os.path.join(work, "live")
        r = subprocess.run([binary, "start-live", t.source, live], capture_output=True, text=True, timeout=8)
        check(r.returncode == 0 and "CPMAP_GUIDANCE_STARTED" in r.stdout, "I start-live started")
        first = open(os.path.join(live, "reader.pid")).read().strip()
        r = subprocess.run([binary, "start-live", t.source, live], capture_output=True, text=True, timeout=8)
        check(r.returncode == 0 and "ALREADY_RUNNING" in r.stdout, "I second start-live refused")
        r1 = subprocess.run([binary, "stop", live], capture_output=True, text=True, timeout=8)
        r2 = subprocess.run([binary, "start-live", t.source, live], capture_output=True, text=True, timeout=8)
        check(r1.returncode == 0 and r2.returncode == 0 and "CPMAP_GUIDANCE_STARTED" in r2.stdout, "I stop then immediate start -> new reader")
        c2 = Case(binary, work); c2.out = live
        second = open(os.path.join(live, "reader.pid")).read().strip()
        check(second != first and c2.wait(lambda: c2.status().get("status") in ("running", "stale"), 3), "I new daemon running")
        r = subprocess.run([binary, "stop", live], capture_output=True, text=True, timeout=8)
        check(r.returncode == 0, "I final stop")

        # J: driver file absent -> invalidate detail 1 (open), reader keeps running; file appears -> snapshot.
        miss = Case(binary, work); miss.source = os.path.join(work, "absent"); miss.out = os.path.join(work, "miss")
        miss.start()
        try:
            check(miss.wait(lambda: miss.mailbox()["kind"] == 2 and miss.mailbox()["detail"] == 1, 3), "J absent driver file -> invalidate detail 1")
            time.sleep(1.2)
            check(miss.proc.poll() is None and miss.status().get("restarts") == "0", "J no restarts, still running")
            miss.write_source(9)
            check(miss.wait(lambda: miss.mailbox()["kind"] == 1 and miss.mailbox()["seq"] == 9, 2), "J file appears -> snapshot")
            # K: no change for 5 s -> STALE record (kind 3, detail 5000), status stale.
            check(miss.wait(lambda: miss.mailbox()["kind"] == 3 and miss.mailbox()["detail"] == 5000, 7), "K stale after 5 s without change")
            check(miss.wait(lambda: miss.status().get("status") == "stale", 2), "K status stale")
            # L: heartbeat cadence stays under the Java 1500 ms producer check.
            s0 = miss.mailbox()["serial"]; t0 = time.monotonic()
            miss.wait(lambda: miss.mailbox()["serial"] >= s0 + 4, 6)
            per = (time.monotonic() - t0) / max(1, miss.mailbox()["serial"] - s0)
            check(per < 1.3, "L heartbeat every %.2f s (< 1.5 s)" % per)
        finally:
            miss.stop()

    print("READER FAILED=%d" % len(FAILS))
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
