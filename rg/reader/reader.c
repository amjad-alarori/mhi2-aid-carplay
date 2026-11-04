/* SPDX-License-Identifier: GPL-3.0-or-later
 * Continuous guidance RAM feed, adapted from the tested C4 reader. Separate process; no driver writes or HMI output.
 * A supervised worker contains all potentially blocking device operations.
 *
 * pmcp variant for MU1161 (rg/reader): derived from tomasz-twardzicki/MHI2-Carplay-Maps
 * MU1427/route-guidance/release/reader.c (source sha256 fa4b4ed6..., binary rgi-observer b683cef7...).
 * Changes, all in the supervisor; worker, snapshot validation and the RGM1 mailbox format are unchanged:
 *  - A silent worker no longer ends the reader. After SILENT_MS without a frame the supervisor records one
 *    INVALIDATE (detail WORKER_TIMEOUT) and keeps running with heartbeats; a late frame resumes the feed.
 *  - After KILL_MS without a frame, or on pipe EOF/error, the worker is killed and a new one is started only
 *    after waitpid(WNOHANG) has confirmed the old one is gone, with a growing delay. The supervisor never
 *    blocks on the worker: non-blocking pipe, select() with a 100 ms timeout, kill(), waitpid(WNOHANG), fork().
 *  - Mailbox/status write errors are counted and retried at the next record instead of ending the reader.
 *  - One supervisor per output directory: an fcntl write lock on reader.lock held for the supervisor's life (released
 *    by the kernel on death, not inherited by workers). An existing directory is reused when that lock is free.
 *    /ramdisk on MU1161 is fs-qnx4 (devb-ram), which supports record locks; without them the reader does not start
 *    and writes lock-error.txt. Never delete the directory or reader.lock while a reader runs.
 *  - The pipe is drained before deadlines are evaluated, so a delayed supervisor does not mistake a waiting frame
 *    for a hung worker.
 *  - status.txt carries restart/timeout/kill/EOF/write-error/reap counters after the original fields.
 */
#define _POSIX_C_SOURCE 200809L
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/select.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <errno.h>

#define SNAP 33088u
#define SLOTS 16u
#define STRIDE 2064u
#define POLL_MS 100u
#ifndef SILENT_MS
#define SILENT_MS 1000u
#endif
#ifndef KILL_MS
#define KILL_MS 10000u
#endif
#ifndef RESPAWN_MIN_MS
#define RESPAWN_MIN_MS 1000u
#endif
#ifndef RESPAWN_MAX_MS
#define RESPAWN_MAX_MS 16000u
#endif
#ifndef STALE_MS
#define STALE_MS 5000u
#endif
#define HEARTBEAT_MS 1000u
#define BUILD "pmcp-r1"

/* RGJ1 records: snapshot, invalidate, stale, heartbeat, end. */
enum { SNAPSHOT=1, INVALIDATE=2, STALE=3, HEARTBEAT=4, END=5 };
enum { SOURCE_OPEN=1, SOURCE_READ=2, SHORT_READ=3, BAD_SNAPSHOT=4,
       WORKER_TIMEOUT=5, WORKER_EOF=6 };
enum { DURATION=0, STOP=1, CAPACITY=2, WORKER_FAILED=3, OUTPUT_FAILED=4 };
static volatile sig_atomic_t stopping;
static unsigned char frame[8 + SNAP], compact[SNAP], retained[SNAP];
static unsigned retained_kind=2, retained_detail=1;
static size_t retained_size;
static uint32_t serial;

static uint32_t u32(const unsigned char *p) {
    return (uint32_t)p[0] | (uint32_t)p[1]<<8 | (uint32_t)p[2]<<16 | (uint32_t)p[3]<<24;
}
static unsigned u16(const unsigned char *p) { return p[0] | (unsigned)p[1]<<8; }
static unsigned be16(const unsigned char *p) { return (unsigned)p[0]<<8 | p[1]; }
static void put32(unsigned char *p, uint32_t v) {
    unsigned i; for (i=0; i<4; ++i) p[i]=(unsigned char)(v>>(8*i));
}
static uint64_t now_ms(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts)) return UINT64_MAX;
    return (uint64_t)ts.tv_sec*1000u + (unsigned long)ts.tv_nsec/1000000u;
}
static void signal_stop(int sig) { (void)sig; stopping=1; }
static int write_all(int fd, const void *data, size_t length) {
    const unsigned char *p=data;
    while (length) {
        ssize_t n=write(fd,p,length);
        if (n<0 && errno==EINTR) continue;
        if (n<=0) return -1;
        p+=n; length-=(size_t)n;
    }
    return 0;
}

/* Validate the complete envelope before journaling any slot. Semantic field
 * widths, UTF-8 and state transitions are checked by the host decoder. */
static size_t pack_snapshot(const unsigned char *b) {
    uint32_t seq=u32(b+20), count=u32(b+24), session=u32(b+16);
    unsigned i, p; size_t used=64;
    if (memcmp(b,"RGI1",4) || u32(b+4)!=1 || u32(b+8)!=SNAP ||
        (u32(b+12)&1) || u32(b+28)>1 || u32(b+32) || u32(b+36)>1 ||
        u32(b+44)>=1000000000u || count!=(seq<SLOTS?seq:SLOTS) ||
        (!u32(b+36) && seq) || (u32(b+36) && !session)) return 0;
    for (i=48; i<64; i+=4) if (u32(b+i)) return 0;
    memcpy(compact,b,64);
    for (i=0; i<count; ++i) {
        uint32_t s=seq-count+1+i;
        const unsigned char *slot=b+64+((s-1)&15)*STRIDE;
        unsigned id=u16(slot+4), length=u16(slot+6), tlvs=0;
        if (u32(slot)!=s || u32(slot+8)!=session || u32(slot+12) ||
            length>2048 || (id!=0x5201 && id!=0x5202 && id!=0x5204)) return 0;
        for (p=0; p<length;) {
            unsigned n;
            if (length-p<4 || ++tlvs>256) return 0;
            n=be16(slot+16+p);
            if (n<4 || n>length-p) return 0;
            p+=n;
        }
        memcpy(compact+used,slot,16+length); used+=16+length;
    }
    return used;
}

static void worker(int output, const char *source) {
    struct timespec delay={0,POLL_MS*1000000u};
    signal(SIGTERM,SIG_DFL); signal(SIGINT,SIG_DFL); signal(SIGPIPE,SIG_DFL);
    for (;;) {
        int fd=open(source,O_RDONLY|O_NONBLOCK), saved=0; ssize_t n=0;
        if (fd<0) saved=errno;
        else {
            do { n=read(fd,frame+8,SNAP); } while (n<0 && errno==EINTR);
            if (n<0) { saved=errno; n=0; }
            /* The supervisor's deadline includes close as well as open/read. */
            if (close(fd) && !saved) saved=errno;
        }
        put32(frame,(uint32_t)saved);
        put32(frame+4,fd<0?SOURCE_OPEN:(saved?SOURCE_READ:(n==SNAP?0:SHORT_READ)));
        if (saved || n!=SNAP) memset(frame+8,0,SNAP);
        {
            size_t at;
            /* Keep individual writes within POSIX's minimum atomic pipe
             * capacity; do not depend on a large QNX pipe write completing. */
            for (at=0; at<sizeof(frame); at+=512) {
                size_t n=sizeof(frame)-at; if (n>512) n=512;
                if (write_all(output,frame+at,n)) _exit(1);
            }
        }
        delay.tv_sec=0; delay.tv_nsec=POLL_MS*1000000u;
        if (nanosleep(&delay,NULL) && errno!=EINTR) _exit(1);
    }
}

struct journal { uint32_t bytes; uint64_t started; };
static int record(struct journal *j, unsigned kind, unsigned detail,
                  const unsigned char *payload, size_t n) {
    unsigned char h[32]={0}; int fd, failed;
    if (kind!=HEARTBEAT) {
        retained_kind=kind; retained_detail=detail; retained_size=n;
        if (n) memcpy(retained,payload,n);
    }
    if (retained_size>SNAP || serial==UINT32_MAX) return -1;
    memcpy(h,"RGM1",4); put32(h+4,1); put32(h+8,(uint32_t)(32+retained_size));
    put32(h+12,++serial); put32(h+16,retained_kind); put32(h+20,retained_detail);
    put32(h+24,(uint32_t)j->started); put32(h+28,(uint32_t)(j->started>>32));
    fd=open("latest.tmp",O_WRONLY|O_CREAT|O_TRUNC,0600);
    if (fd<0) return -1;
    failed=write_all(fd,h,sizeof(h)) || (retained_size && write_all(fd,retained,retained_size));
    if (close(fd)) failed=1;
    if (failed) { unlink("latest.tmp"); return -1; }
    if (rename("latest.tmp","latest.bin")) return -1;
    j->bytes=(uint32_t)(32+retained_size);
    return 0;
}

/* Supervisor counters, reported after the original status fields. */
static struct { uint32_t restarts, timeouts, kills, eofs, write_errors, spawn_errors; long worker; uint64_t killed_at; } c;
static int lock_fd=-1;

static int status_file(const char *state, uint32_t polls,
                       uint32_t good, uint32_t bad, uint32_t seq,
                       uint32_t bytes, unsigned reason, uint64_t now) {
    FILE *f=fopen("status.tmp","w"); int failed;
    unsigned long reaping=c.killed_at && now>=c.killed_at?(unsigned long)(now-c.killed_at):0;
    if (!f) return -1;
    failed=fprintf(f,"RG status=%s polls=%u valid=%u invalid=%u sequence=%u bytes=%u reason=%u"
                   " build=%s restarts=%u timeouts=%u kills=%u eofs=%u write_errors=%u spawn_errors=%u"
                   " worker=%ld reaping_ms=%lu\n",
                   state,(unsigned)polls,(unsigned)good,(unsigned)bad,(unsigned)seq,(unsigned)bytes,reason,
                   BUILD,(unsigned)c.restarts,(unsigned)c.timeouts,(unsigned)c.kills,(unsigned)c.eofs,
                   (unsigned)c.write_errors,(unsigned)c.spawn_errors,c.worker,reaping)<0;
    if (fclose(f)) failed=1;
    return failed?-1:rename("status.tmp","status.txt");
}

/* Start a worker on a fresh non-blocking pipe. Never waits for the device.
 * Returns 0 with a pipe, 1 when the pipe setup failed after fork (worker killed, still to be reaped), -1 on failure. */
static int spawn(const char *source, int inherited, pid_t *child, int *fd) {
    int channel[2], flags; pid_t pid;
    if (pipe(channel)) return -1;
    pid=fork();
    if (pid<0) { close(channel[0]); close(channel[1]); return -1; }
    if (!pid) {
        close(channel[0]); if (inherited>=0) close(inherited); if (lock_fd>=0) close(lock_fd);
        worker(channel[1],source); _exit(1);
    }
    close(channel[1]);
    *child=pid;
    flags=fcntl(channel[0],F_GETFL);
    if (flags<0 || fcntl(channel[0],F_SETFL,flags|O_NONBLOCK)<0) {
        close(channel[0]); kill(pid,SIGKILL); *fd=-1; return 1;
    }
    *fd=channel[0]; return 0;
}

static void pace(void) {
    struct timespec delay={0,POLL_MS*1000000u};
    nanosleep(&delay,NULL);
}

static int observe(const char *source, unsigned seconds, int ready) {
    int fd=-1, result=0, reason=DURATION, stale=0, silent=0, killed=0, spawned;
    int last_error=-1, last_reason=-1;
    pid_t child=-1; size_t have=0;
    uint32_t polls=0, good=0, bad=0, sequence=0, backoff=RESPAWN_MIN_MS;
    unsigned char last_header[64]={0};
    uint64_t now=now_ms(), received=now, progress=now, changed=now, heartbeat=now, respawn_at=0;
    struct journal j;
    if (now==UINT64_MAX) return 1;
    j.started=now; j.bytes=16;
    spawned=spawn(source,ready,&child,&fd);
    if (spawned<0) return 1;
    killed=spawned>0;
    if (killed) c.killed_at=now;
    c.worker=(long)child;
    {
        FILE *f=fopen("reader.tmp","w"); int failed=!f;
        if (f) { if (fprintf(f,"%ld\n",(long)getpid())<0) failed=1; if (fclose(f)) failed=1; }
        if (failed || rename("reader.tmp","reader.pid") ||
            status_file("running",0,0,0,0,j.bytes,0,now)) { reason=OUTPUT_FAILED; result=1; goto done; }
    }
    if (ready>=0) { unsigned char ok=1; (void)write_all(ready,&ok,1); close(ready); ready=-1; }
    /* Output setup can take longer than the device deadline. Start that
     * deadline when the supervisor is ready to drain the worker pipe. */
    received=now_ms();
    if (received==UINT64_MAX) { reason=WORKER_FAILED; result=1; goto done; }
    changed=heartbeat=progress=received;
    while (!stopping && access("stop",F_OK)) {
        int lost=0;
        /* 1. Drain everything the worker has written before judging it. */
        while (fd>=0) {
            ssize_t n=read(fd,frame+have,sizeof(frame)-have);
            if (n<0 && errno==EINTR) continue;
            if (n<0 && errno==EAGAIN) break;
            if (n<=0) { lost=WORKER_EOF; ++c.eofs; break; }
            have+=(size_t)n; progress=now_ms();   /* any byte = the worker is alive (it writes only after its device read) */
            if (have<sizeof(frame)) continue;
            have=0; received=now_ms(); ++polls; silent=0; backoff=RESPAWN_MIN_MS;
            if (received==UINT64_MAX) break;
            {
                int error=(int)u32(frame), why=(int)u32(frame+4), failed=0;
                size_t len=why?0:pack_snapshot(frame+8);
                if (!len) {
                    ++bad;
                    if (!why) why=BAD_SNAPSHOT;
                    if (why!=last_reason || error!=last_error) {
                        unsigned char e[4]; put32(e,(unsigned)error);
                        failed=record(&j,INVALIDATE,(unsigned)why,e,4);
                    }
                    last_reason=why; last_error=error;
                } else {
                    ++good;
                    /* Recovery of a read alone is not fresh guidance. After an
                     * invalidation/stale deadline, an unchanged header must not
                     * replay the old window and revive the previous route. */
                    if (memcmp(last_header,frame+8,64)) {
                        failed=record(&j,SNAPSHOT,0,compact,len);
                        memcpy(last_header,frame+8,64); sequence=u32(frame+28);
                        changed=received; stale=0;
                    }
                    last_reason=last_error=-1;
                }
                if (failed) ++c.write_errors;
            }
        }
        now=now_ms();
        if (now==UINT64_MAX || now<j.started) { result=1; reason=WORKER_FAILED; break; }
        if (seconds && now-j.started>=(uint64_t)seconds*1000) break;

        /* 2. Worker supervision. Nothing here can wait for the device or the worker. */
        if (!lost && child>0 && !killed && now-received>=KILL_MS && now-progress>=KILL_MS) { lost=WORKER_TIMEOUT; ++c.kills; }
        if (lost || (child>0 && !killed && !silent && now-received>=SILENT_MS && now-progress>=SILENT_MS)) {
            if (!silent) {
                /* NO_OP: guidance off once; the reader stays up and keeps its heartbeat. */
                if (record(&j,INVALIDATE,lost==WORKER_EOF?WORKER_EOF:WORKER_TIMEOUT,NULL,0)) ++c.write_errors;
                silent=1; last_reason=last_error=-1;
                if (!lost) ++c.timeouts;
            }
        }
        if (lost && child>0 && !killed) {
            kill(child,SIGKILL); killed=1; c.killed_at=now;
            if (fd>=0) { close(fd); fd=-1; }
            have=0;
        }
        if (child>0 && killed) {
            pid_t r=waitpid(child,NULL,WNOHANG);
            if (r==child || (r<0 && errno==ECHILD)) {
                child=-1; c.worker=-1; c.killed_at=0; respawn_at=now+backoff;
                backoff=backoff>=RESPAWN_MAX_MS/2?RESPAWN_MAX_MS:backoff*2;
            }
        }
        if (child<0 && now>=respawn_at) {
            spawned=spawn(source,-1,&child,&fd);
            if (spawned<0) {
                child=-1; ++c.spawn_errors; respawn_at=now+backoff;
                backoff=backoff>=RESPAWN_MAX_MS/2?RESPAWN_MAX_MS:backoff*2;
            } else {
                ++c.restarts; c.worker=(long)child; killed=spawned>0; have=0;
                if (killed) c.killed_at=now;
                received=progress=now;   /* fresh deadline for the new worker; guidance stays off until fresh data */
            }
        }

        if (now-changed>=STALE_MS && !stale) {
            if (record(&j,STALE,STALE_MS,NULL,0)) ++c.write_errors;
            stale=1;
        }
        if (now-heartbeat>=HEARTBEAT_MS) {
            heartbeat=now;
            if (record(&j,HEARTBEAT,sequence,NULL,0)) ++c.write_errors;
            if (status_file(retained_kind==STALE?"stale":retained_kind!=SNAPSHOT?"unavailable":"running",
                            polls,good,bad,sequence,j.bytes,0,now)) ++c.write_errors;
        }

        /* 3. Wait at most POLL_MS for the worker (or just pace the loop). */
        if (fd<0) { pace(); continue; }
        {
            fd_set fds; struct timeval timeout={0,POLL_MS*1000}; int rc;
            FD_ZERO(&fds); FD_SET(fd,&fds);
            rc=select(fd+1,&fds,NULL,NULL,&timeout);
            if (rc<0 && errno!=EINTR) {
                /* Broken pipe descriptor: treat like a lost worker on the next pass. */
                close(fd); fd=-1; have=0;
                if (child>0 && !killed) { kill(child,SIGKILL); killed=1; c.killed_at=now; ++c.kills; }
                if (!silent) {
                    if (record(&j,INVALIDATE,WORKER_EOF,NULL,0)) ++c.write_errors;
                    silent=1; last_reason=last_error=-1;
                }
            }
        }
    }
    if (stopping || !access("stop",F_OK)) reason=STOP;
done:
    if (ready>=0) close(ready);
    /* Do not use blocking waitpid: even a failed device request cannot keep
     * the supervisor alive indefinitely during shutdown. */
    if (child>0) {
        unsigned i; struct timespec delay={0,10000000};
        kill(child,SIGKILL);
        for (i=0;i<20;++i) {
            if (waitpid(child,NULL,WNOHANG)!=0) break;
            nanosleep(&delay,NULL);
        }
    }
    if (fd>=0) close(fd);
    if (record(&j,END,(unsigned)reason,NULL,0)) result=1;
    if (status_file("ended",polls,good,bad,sequence,j.bytes,(unsigned)reason,now_ms())) result=1;
    {
        char line[32]; long pid=0; FILE *f=fopen("reader.pid","r");
        if (f) { if (fgets(line,sizeof(line),f)) pid=strtol(line,NULL,10); fclose(f); }
        if (pid==(long)getpid()) unlink("reader.pid");
    }
    return result;
}

static int status_ended(void) {
    char line[64]; FILE *f=fopen("status.txt","r"); int ended=0;
    if (f) { ended=fgets(line,sizeof(line),f) && !strncmp(line,"RG status=ended ",16); fclose(f); }
    return ended;
}

/* Claim the output directory. 0 = ours (new or taken over), 1 = a live reader owns it, -1 = error.
 * The claim is an fcntl write lock on reader.lock (never unlinked), held until this process ends. A reader that is
 * still finishing a stop (status=ended) is waited for, so stop followed by start does not lose the reader. */
static int enter_output(const char *dir) {
    struct flock fl; unsigned i;
    if (mkdir(dir,0700) && errno!=EEXIST) return -1;
    if (chdir(dir)) return -1;
    lock_fd=open("reader.lock",O_RDWR|O_CREAT,0600);
    if (lock_fd<0) return -1;
    for (i=0;;++i) {
        memset(&fl,0,sizeof(fl)); fl.l_type=F_WRLCK; fl.l_whence=SEEK_SET;
        if (!fcntl(lock_fd,F_SETLK,&fl)) break;
        if (errno!=EAGAIN && errno!=EACCES) {
            /* No record locks on this filesystem: fail closed, but leave the reason where diagnostics look. */
            FILE *f=fopen("lock-error.txt","w"); int saved=errno;
            if (f) { fprintf(f,"RG lock_errno=%d\n",saved); fclose(f); }
            return -1;
        }
        if (i>=30 || !status_ended()) { close(lock_fd); lock_fd=-1; return 1; }
        pace();
    }
    unlink("stop"); unlink("latest.tmp"); unlink("status.tmp"); unlink("reader.tmp");
    unlink("latest.bin"); unlink("status.txt"); unlink("reader.pid"); unlink("lock-error.txt");
    return 0;
}

int main(int argc, char **argv) {
    char *tail; unsigned long seconds; int start, ack[2], entered; pid_t pid;
    if (argc==3 && !strcmp(argv[1],"stop")) {
        unsigned i; int fd;
        if (chdir(argv[2])) return 1;
        fd=open("stop",O_CREAT|O_WRONLY,0600);
        if (fd<0 || close(fd)) return 1;
        for (i=0;i<30;++i) {
            struct timespec delay={0,100000000};
            if (status_ended()) { puts("CPMAP_GUIDANCE_STOPPED"); return 0; }
            nanosleep(&delay,NULL);
        }
        fputs("CPMAP_GUIDANCE_FAIL=STOP_NOT_CONFIRMED\n",stderr); return 1;
    }
    if (argc==4 && (!strcmp(argv[1],"serve") || !strcmp(argv[1],"start-live"))) {
        start=!strcmp(argv[1],"start-live"); seconds=0;
        if (argv[2][0]!='/') return 2;
    } else {
        if (argc!=5 || ((start=strcmp(argv[1],"start")==0)==0 && strcmp(argv[1],"run"))) {
            fputs("usage: guidance-reader serve|start-live ABSOLUTE_SOURCE RAM_DIR\n",stderr); return 2;
        }
        seconds=strtoul(argv[4],&tail,10);
        if (!*argv[4] || *tail || seconds<1 || seconds>600 || argv[2][0]!='/') return 2;
    }
    umask(077); signal(SIGPIPE,SIG_IGN); signal(SIGCHLD,SIG_DFL);
    signal(SIGTERM,signal_stop); signal(SIGINT,signal_stop);
    if (!start) {
        entered=enter_output(argv[3]);
        if (entered<0) { perror("output directory"); return 1; }
        if (entered>0) { puts("CPMAP_GUIDANCE_ALREADY_RUNNING"); return 0; }
        return observe(argv[2],(unsigned)seconds,-1);
    }
    /* The lock must be taken by the daemon itself (fcntl locks are not inherited across fork). */
    if (pipe(ack)) return 1;
    pid=fork();
    if (pid<0) { close(ack[0]); close(ack[1]); return 1; }
    if (pid) {
        fd_set fds; struct timeval timeout={5,0}; unsigned char ok=0; int rc;
        close(ack[1]); FD_ZERO(&fds); FD_SET(ack[0],&fds);
        rc=select(ack[0]+1,&fds,NULL,NULL,&timeout);
        if (rc>0 && read(ack[0],&ok,1)==1 && (ok==1 || ok==2)) {
            close(ack[0]); puts(ok==1?"CPMAP_GUIDANCE_STARTED":"CPMAP_GUIDANCE_ALREADY_RUNNING"); return 0;
        }
        close(ack[0]); kill(pid,SIGTERM); return 1;
    }
    close(ack[0]);
    if (setsid()<0) _exit(1);
    entered=enter_output(argv[3]);
    if (entered<0) { perror("output directory"); _exit(1); }
    if (entered>0) { unsigned char two=2; (void)write_all(ack[1],&two,1); _exit(0); }
    {
        int fd=open("/dev/null",O_RDWR);
        if (fd<0) _exit(1);
        if (dup2(fd,0)<0 || dup2(fd,1)<0 || dup2(fd,2)<0) _exit(1);
        if (fd>2) close(fd);
    }
    _exit(observe(argv[2],(unsigned)seconds,ack[1]));
}
