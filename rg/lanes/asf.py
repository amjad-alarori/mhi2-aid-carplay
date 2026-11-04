# SPDX-License-Identifier: GPL-3.0-or-later
"""Three features of tomasz-twardzicki's MU1367 v1.4.3 (git 1d69473, MU1367/integration/src/guidance) on our staged
lanes + U-turn sources (after apply_lanes.py and uturn.py; package rg, build modes lanes-uturn-asf and -asf-m).

    asf.py STAGED_LANE_DIR LANES_DIR   -> patches the staged LiveModel/LiveBridge/MailboxReader/PatchLive/TestLive,
                                          copies Tomasz's unchanged feature and test files from LANES_DIR

  a  ArrowProgress: the native VW bargraph before a maneuver (DistanceToNextManeuver bargraphInfo), 200 m window,
     2000 m for iAP2 motorway exit types 8/22/23, only for the factory verifiedBapBargraphSetting mains.
  s  RoadName: the current street in the VW turn-to field (7th NavSD stage TurnToInfo.setTurnToInfoStatusData,
     iAP2 0x5201 key 3, fallback: the road of a maneuver proven passed).
  f  FeedRecovery: a mailbox read error no longer blocks guidance until the next unit start; the reader retries after
     1 s from a fresh baseline (fatal only for non-I/O errors), first failure in failure-first.txt (<= 768 B).

Not taken from v1.4.3 (not requested): placeholder arrow (main 13) and realDistance, lane type/description and
ambiguous-branch encoding, LaneEvidence (lane-evidence.txt, unguarded LaneGuidance hooks), ownership-history
diagnostics. FeedRecovery's diagnostic counters stay (FeedRecovery.java is copied unchanged and reads them).
Each replacement must match exactly the given number of times.
"""
import pathlib
import shutil
import sys

lane_dir, src = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])


def patch(text, old, new, what, count=1):
    if text.count(old) != count:
        sys.exit("asf.py: %s: expected text found %d times, want %d" % (what, text.count(old), count))
    return text.replace(old, new)


for name in ("FeedRecovery", "ArrowProgress", "RoadName", "TestArrow", "TestRoad", "TestRecovery"):
    shutil.copy2(src / (name + ".java"), lane_dir / (name + ".java"))

# ---- LiveModel: road text, maneuver type, Fault on validation errors ------------------------------------------
p = lane_dir / "LiveModel.java"
s = p.read_text()
s = patch(s, "        final LaneData[] lanes; final long laneAt;\n",
          "        final LaneData[] lanes; final long laneAt;\n"
          "        public final String currentRoad; public final long roadAt;\n"
          "        public final int maneuverType;\n", "Frame fields")
s = patch(s, """        Frame(boolean a,int m,int d,int distance,int remaining,int seconds,long p,long c,long e,LaneData[] values,long at) {
            lanes=values;laneAt=at;""", """        Frame(boolean a,int m,int d,int distance,int remaining,int seconds,long p,long c,long e,LaneData[] values,long at) {
            this(a,m,d,distance,remaining,seconds,p,c,e,values,at,"",-1);
        }
        Frame(boolean a,int m,int d,int distance,int remaining,int seconds,long p,long c,long e,LaneData[] values,long at,String road,long roadTime) {
            this(a,m,d,distance,remaining,seconds,p,c,e,values,at,road,roadTime,-1);
        }
        Frame(boolean a,int m,int d,int distance,int remaining,int seconds,long p,long c,long e,LaneData[] values,long at,String road,long roadTime,int kind) {
            maneuverType=kind;
            currentRoad=road;roadAt=roadTime;
            lanes=values;laneAt=at;""", "Frame constructors")
s = patch(s, """    private final LaneData.Cache laneCache=new LaneData.Cache();
    private long routeStatusAt=-1;
""", """    private final LaneData.Cache laneCache=new LaneData.Cache();
    public long roadFields, roadNonempty, laneMessages, neutralLanes, neutralBranches;
    private boolean directRoad;
    private long routeStatusAt=-1;
    private String currentRoad=""; private long roadAt=-1;
""", "model fields")
s = patch(s, """    static Message decode(int id, byte[] b, int p, int length) throws IOException {
        require(id==0x5201 || id==0x5202 || id==0x5204);""", """    static Message decode(int id, byte[] b, int p, int length) throws IOException {
        int faultField=-1;
        try {
        require(id==0x5201 || id==0x5202 || id==0x5204);""", "decode try")
s = patch(s, "            require(end-p>=4 && ++count<=256); int n=be16(b,p), key=be16(b,p+2);\n",
          "            require(end-p>=4 && ++count<=256); int n=be16(b,p), key=be16(b,p+2);faultField=key;\n", "fault field")
s = patch(s, "                if (id==0x5201 && (key==4 || key==19)) {",
          "                if (id==0x5201 && (key==3 || key==4 || key==19) || id==0x5202 && key==4) {", "road text kept")
s = patch(s, """        require(id==0x5201 || m.has[1]); return m;
    }""", """        require(id==0x5201 || m.has[1]); return m;
        }catch(java.io.IOException e){throw new FeedRecovery.Fault(id,faultField);}
    }""", "decode catch")
s = patch(s, "        laneCache.clear();routeStatusAt=-1;\n        cache=new Message[32];",
          "        laneCache.clear();routeStatusAt=-1;currentRoad=\"\";roadAt=-1;directRoad=false;\n        cache=new Message[32];",
          "clearCache")
s = patch(s, "    private boolean apply(Message m) {", """    private String passedRoad(Message m) throws IOException {
        // Only a forward transition within the same known route proves that
        // a maneuver road is now behind us. An upcoming road is never enough.
        if(m.id!=0x5201 || !m.has[13] || m.order.length==0 || (state!=1 && state!=6)
            || m.has[1] && m.v[1]!=1 && m.v[1]!=6
            || m.has[19] && source!=null && !equal(source,m.raw[19])
            || m.has[4] && destination!=null && !equal(destination,m.raw[4]))return null;
        for(int j=1;j<order.length;j++)if(order[j]==m.order[0]){
            int passed=order[j-1];
            for(int i=0;i<cache.length;i++)if(cache[i]!=null && cache[i].v[1]==passed)
                return RoadName.decode(cache[i].raw[4]);
            return "";
        }
        return null;
    }
    private boolean apply(Message m) {""", "passedRoad")
s = patch(s, "        if (next!=1 && next!=6) remainingMeters=remainingSeconds=-1;",
          "        if (next!=1 && next!=6) {remainingMeters=remainingSeconds=-1;currentRoad=\"\";roadAt=-1;directRoad=false;}",
          "route end clears road")
s = patch(s, "            messages[i]=decode(id,b,pos+16,length); bytes[i]=copy(b,pos,16+length);",
          "            try {messages[i]=decode(id,b,pos+16,length);}catch(FeedRecovery.Fault e){e.sequence=seq;throw e;} bytes[i]=copy(b,pos,16+length);",
          "fault sequence")
s = patch(s, "                boolean accepted=apply(messages[i]);",
          "                String passed=passedRoad(messages[i]);\n                boolean accepted=apply(messages[i]);", "passed road")
s = patch(s, """                    Message m=messages[i];
                    if (m.id==0x5201 && (state==1 || state==6)) {
                        routeStatusAt=now;""", """                    Message m=messages[i];
                    if(m.id==0x5201 && m.has[3]){roadFields++;if(RoadName.decode(m.raw[3]).length()>0)roadNonempty++;}
                    if(m.id==0x5204){laneMessages++;for(int j=0;j<m.lanes.length;j++)if(m.lanes[j].recommendation==0){neutralLanes++;neutralBranches+=m.lanes[j].sides.length();}}
                    if (m.id==0x5201 && (state==1 || state==6)) {
                        routeStatusAt=now;
                        if(m.has[3]){currentRoad=RoadName.decode(m.raw[3]);roadAt=now;directRoad=currentRoad.length()>0;}
                        else if(passed!=null && !directRoad){currentRoad=passed;roadAt=now;}""", "road on route update")
s = patch(s, "    public Frame frame() {",
          "    private int maneuverType(){Message m=current();return m!=null && m.has[3]?(int)m.v[3]:-1;}\n    public Frame frame() {",
          "maneuverType")
s = patch(s, "remainingSeconds,progress,changed,epoch,laneCache.current(),routeStatusAt);",
          "remainingSeconds,progress,changed,epoch,laneCache.current(),routeStatusAt,currentRoad,roadAt,maneuverType());", "frame()")
p.write_text(s)

# ---- MailboxReader: envelope identity for failure-first.txt (format unchanged) ----------------------------------
p = lane_dir / "MailboxReader.java"
s = p.read_text()
s = patch(s, "    long records;\n", "    long records;\n    long observedSerial=-1,observedKind=-1,observedNonce=-1;\n", "observed fields")
s = patch(s, "    public LiveModel.Frame next(long now) throws IOException {\n",
          "    public LiveModel.Frame next(long now) throws IOException {\n        observedSerial=observedKind=observedNonce=-1;\n",
          "observed reset")
s = patch(s, "        } finally { in.close(); }\n",
          "        } finally { in.close(); }\n        if(size>=32){observedSerial=LiveModel.u32(bytes,12);observedKind=LiveModel.u32(bytes,16);observedNonce=LiveModel.u32(bytes,24) | LiveModel.u32(bytes,28)<<32;}\n",
          "observed values")
p.write_text(s)

# ---- LiveBridge: 7th stage (TurnToInfo), bargraph, road, FeedRecovery reader loop ---------------------------
p = lane_dir / "LiveBridge.java"
s = p.read_text()
s = patch(s, "    final Function[] stages=new Function[6];", "    final Function[] stages=new Function[7];", "stages")
s = patch(s, """    static int slot(int id) { return id==23?0:id==18?1:id==17?2:id==24?3:id==21?4:id==22?5:-1; }
    static final int PROPERTIES=55; // all stages except the lane array""",
          """    String publishedRoad="";
    int publishedBar=-1;
    static int slot(int id) { return id==23?0:id==18?1:id==17?2:id==24?3:id==21?4:id==22?5:id==20?6:-1; }
    static final int PROPERTIES=119; // all stages except the lane array""", "slot/PROPERTIES")
s = patch(s, "refreshPending=63", "refreshPending=127", "refresh mask", count=7)
s = patch(s, "            for (int i=0;i<6;i++) if (INSTANCE.stages[i]==stage) INSTANCE.stages[i]=null;",
          "            for (int i=0;i<7;i++) if (INSTANCE.stages[i]==stage) INSTANCE.stages[i]=null;", "detach loop")
s = patch(s, "        for (int i=0;i<6;i++) if ((refreshPending&(1<<i))!=0 && stages[i]!=null) {",
          "        for (int i=0;i<7;i++) if ((refreshPending&(1<<i))!=0 && stages[i]!=null) {", "refresh loop")
s = patch(s, "            } else if (clearing && (refreshPending&PROPERTIES)==0) {",
          "            } else if (clearing && (refreshPending&(stages[6]==null?55:PROPERTIES))==0) {", "clear without road stage")
s = patch(s, "        if(owned && stages[3]!=null)refreshPending|=8;\n", """        if(owned && stages[3]!=null)refreshPending|=8;
        if(owned){
            int bar=ArrowProgress.remaining(frame,time);
            if(bar!=publishedBar){publishedBar=bar;refreshPending|=2;}
            String road=RoadName.current(frame,time);
            if(!road.equals(publishedRoad)){publishedRoad=road;refreshPending|=64;}
        }
""", "bar/road refresh")
s = patch(s, "        out.bargraphInfo.bargraphOnOff=0; out.bargraphInfo.bargraph=0;\n",
          "        ArrowProgress.fill(out,f,now());\n", "bargraph")
s = patch(s, "    public static boolean destinationDistance(DistanceToDestination_Status out) {", """    public static boolean turnTo(TurnToInfo_Status out) {
        LiveModel.Frame f=INSTANCE.current();if(f==null)return false;
        out.reset();out.turnToInfo.setContent(RoadName.current(f,now()));
        INSTANCE.writes++;return true;
    }
    public static boolean destinationDistance(DistanceToDestination_Status out) {""", "turnTo")
s = patch(s, ".append(\" error=\").append(error).append('\\n');",
          ".append(\" arrow_remaining_percent=\").append(ArrowProgress.remaining(incoming,now())).append(\" arrow_window_m=\").append(ArrowProgress.window(incoming))"
          ".append(\" road_present=\").append(RoadName.current(incoming,now()).length()>0?1:0).append(\" road_at=\").append(incoming==null?-1:incoming.roadAt)"
          ".append(\" road_fields_seen=\").append(productionFeed==null?0:productionFeed.roadFields)"
          ".append(\" feed_errors=\").append(productionFeed==null?0:productionFeed.errors).append(\" feed_recoveries=\").append(productionFeed==null?0:productionFeed.recoveries)"
          ".append(\" feed_fatal=\").append(productionFeed!=null && productionFeed.fatal?1:0).append(\" error=\").append(error).append('\\n');",
          "status fields")
start = s.index("    void runProduction() {")
end = s.index("\n    }\n", s.index("            try { Thread.sleep(100); } catch (InterruptedException e) { incoming=null; mode=0; return; }", start)) + len("\n    }\n")
old = s[start:end]
for must in ('MailboxReader reader=new MailboxReader(ROOT+"/latest.bin");', "error=1;", "if (new File(ROOT).isDirectory()) status(reader.records,error);"):
    if old.count(must) != 1:
        sys.exit("asf.py: runProduction: unexpected body (%s)" % must)
s = s[:start] + """    FeedRecovery productionFeed;
    void runProduction() {
        FeedRecovery feed=new FeedRecovery(ROOT);productionFeed=feed;
        long written=-1;
        runId="1";runSerial++;
        for (;;) {
            try {
                long time=now();
                pollProduction(feed,time,new File(ROOT+"/disabled").exists());
                if(written<0 || time<written || time-written>=1000){
                    if(new File(ROOT).isDirectory())status(feed.reader.records,feed.error);
                    written=time;
                }
            }catch(Throwable t){incoming=null;mode=0;journalAt=-1;feed.failed(t,0);}
            try{Thread.sleep(100);}catch(InterruptedException e){incoming=null;mode=0;return;}
        }
    }
    long feedGeneration=-1;
    void pollProduction(FeedRecovery feed,long time,boolean disabled){
        if(productionFeed!=feed){productionFeed=feed;feedGeneration=-1;}
        if(disabled){feed.pause();incoming=null;mode=0;journalAt=-1;}
        else {
            LiveModel.Frame frame=feed.poll(time);
            if(!feed.live){incoming=null;mode=0;journalAt=-1;}
            if(feed.generation!=feedGeneration){feedGeneration=feed.generation;runSerial++;runId=Long.toString(feedGeneration+1);}
            if(frame!=null)incoming=frame;
            journalAt=feed.recordAt;mode=feed.live?2:0;
            if(mode==0)incoming=null;
        }
    }
""" + s[end:]
p.write_text(s)

# ---- PatchLive: 7th class TurnToInfo (protected fill method); no LaneEvidence hooks -----------------------------
p = lane_dir / "PatchLive.java"
s = p.read_text()
s = patch(s, '''        String[] classes={"ManeuverDescriptor","DistanceToNextManeuver","RGStatus","LaneGuidance","DistanceToDestination","TimeToDestination"};
        String[] methods={"fillManeuverDescriptor","setDistanceToNextManeuverStatusData","setRouteGuidanceStatus","computeFullLaneGuidanceList","setDistanceAndUnit","setTimeInfo"};
        String[] hooks={"descriptor","distance","route","lanes","destinationDistance","destinationTime"};''',
          '''        String[] classes={"ManeuverDescriptor","DistanceToNextManeuver","RGStatus","LaneGuidance","DistanceToDestination","TimeToDestination","TurnToInfo"};
        String[] methods={"fillManeuverDescriptor","setDistanceToNextManeuverStatusData","setRouteGuidanceStatus","computeFullLaneGuidanceList","setDistanceAndUnit","setTimeInfo","setTurnToInfoStatusData"};
        String[] hooks={"descriptor","distance","route","lanes","destinationDistance","destinationTime","turnTo"};''',
          "PatchLive classes")
s = patch(s, "MethodNode fill=method(c,methods[i]); check(fill.desc.endsWith(\")V\") && (fill.access&ACC_PRIVATE)!=0);",
          "MethodNode fill=method(c,methods[i]); check(fill.desc.endsWith(\")V\") && (fill.access&(i==6?ACC_PROTECTED:ACC_PRIVATE))!=0);",
          "PatchLive access")
s = patch(s, 'System.out.println("D3: all six replacements and all helpers target class 46");',
          'System.out.println("D3: all seven replacements and all helpers target class 46");', "PatchLive message")
p.write_text(s)

# ---- TestLive: the 7th stage (as in v1.4.3) --------------------------------------------------------------------
p = lane_dir / "TestLive.java"
s = p.read_text()
s = patch(s, "    static boolean accept=true,setupLane=true;\n",
          "    static boolean accept=true,setupLane=true;\n    static String stockRoad=\"OEM fixture road\";\n", "TestLive stock road")
s = patch(s, '                if (n.equals("getRouteGuidanceState")) return Integer.valueOf(route);',
          '                if (n.equals("getTurnToInfo"))return named(t.getName(),"street");\n'
          '                if (n.equals("getTurnToInfoStreet"))return stockRoad;\n'
          '                if (n.equals("getTurnToInfoSignPost"))return "";\n'
          '                if (n.equals("getRouteGuidanceState")) return Integer.valueOf(route);', "TestLive mocks")
s = patch(s, '        String[] names={"ManeuverDescriptor","DistanceToNextManeuver","RGStatus","DistanceToDestination","TimeToDestination"};',
          '        String[] names={"ManeuverDescriptor","DistanceToNextManeuver","RGStatus","DistanceToDestination","TimeToDestination","TurnToInfo"};',
          "TestLive stages")
s = patch(s, 'check(b.owned && sent.size()==5,"five factory properties published");',
          'check(b.owned && sent.size()==6,"six factory properties published");', "TestLive five->six")
s = patch(s, 'check(!b.owned && b.clearing && sent.size()==5,"shadow releases existing owner");',
          'check(!b.owned && b.clearing && sent.size()==6,"shadow releases existing owner");', "TestLive release six")
p.write_text(s)
print("asf.py: arrow progress, road name and feed recovery staged in %s" % lane_dir)
