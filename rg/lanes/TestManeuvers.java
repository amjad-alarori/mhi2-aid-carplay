/* pmcp m (maneuvers.py): strict map() unchanged where it maps, harman-f fallbacks only where it showed no arrow.
 * SPDX-License-Identifier: GPL-3.0-or-later */
package com.cpmap.rgi;

public final class TestManeuvers {
    static int checks;
    static void check(boolean yes,String why){checks++;if(!yes)throw new RuntimeException(why);}
    static final int X=Integer.MIN_VALUE;   // field absent
    static LiveModel.Message m(int type,int junction,int side,int angle){
        LiveModel.Message m=new LiveModel.Message(); int[] ids={3,9,8,11}; int[] v={type,junction,side,angle};
        for(int i=0;i<4;i++) if(v[i]!=X){m.has[ids[i]]=true;m.v[ids[i]]=v[i];}
        return m;
    }
    static void is(int type,int junction,int side,int angle,int main,int direction,String why){
        int[] r=LiveModel.map(m(type,junction,side,angle));
        check(r[0]==main&&r[1]==direction,why+" (got "+r[0]+"/"+r[1]+")");
    }
    static void vectors(){
        // 1. Everything the strict map maps is identical to mapStrict (all types, junctions, sides, angle samples).
        int[] js={X,0,1,2,255}, ss={X,0,1,2}, as={X,0,-1,1,-10,10,-22,22,-23,23,-45,45,-67,67,-68,68,-90,90,-112,112,-113,113,
            -135,135,-179,179,-180,180,-181,181,1000,-1000};
        // Pairs the strict map can produce = symbols already proven on the cluster.
        java.util.Hashtable proven=new java.util.Hashtable();
        for(int t=-1;t<=55;t++)for(int a=0;a<js.length;a++)for(int b=0;b<ss.length;b++)for(int c=0;c<as.length;c++){
            int[] strict=LiveModel.mapStrict(m(t,js[a],ss[b],as[c])); proven.put(strict[0]+"/"+strict[1],"");
        }
        for(int t=-1;t<=55;t++)for(int a=0;a<js.length;a++)for(int b=0;b<ss.length;b++)for(int c=0;c<as.length;c++){
            LiveModel.Message msg=m(t,js[a],ss[b],as[c]); int[] strict=LiveModel.mapStrict(msg), r=LiveModel.map(msg);
            if(strict[0]!=0) check(r[0]==strict[0]&&r[1]==strict[1],"strict mapping kept t="+t);
            check(proven.containsKey(r[0]+"/"+r[1]),"only symbol pairs the strict map already uses: "+r[0]+"/"+r[1]+" t="+t);
            if((t==20||t==21)&&r[0]==13) check(r[1]!=0,"end of road turn never straight");
            if(t==51&&(as[c]==X||as[c]==1000||as[c]==-1000||as[c]==181||as[c]==-181)) check(r[0]==0,"highway change without angle stays empty");
        }
        // 2. Fallbacks (harman-f) where the strict map showed nothing.
        is(11,X,X,X,13,0,"start of route without angle -> straight");
        is(11,0,0,90,13,192,"start of route with angle unchanged (strict)");
        is(16,X,X,1000,13,0,"ferry exit with sentinel angle -> straight");
        is(51,X,X,X,0,0,"highway change without angle stays empty (user)");
        is(1,X,X,X,13,64,"left turn without junction");
        is(2,1,X,X,21,192,"right at a roundabout -> roundabout, exit right");
        is(1,1,0,X,21,64,"left at a roundabout -> roundabout, exit left (3rd exit of a 4-arm)");
        is(1,1,1,X,22,64,"left at a roundabout, left-hand traffic -> 22");
        is(3,1,X,X,21,0,"straight at a roundabout -> roundabout, exit ahead");
        is(47,1,X,X,21,96,"sharp left at a roundabout");
        is(4,1,X,X,21,128,"U-turn at a roundabout junction -> roundabout U-turn");
        is(6,1,X,X,13,192,"roundabout entry without side (not a turn type) -> harman-f");
        is(24,1,X,X,3,64,"destination left at a roundabout junction");
        is(1,255,X,X,13,64,"invalid junction 255 = absent");
        is(2,1,0,45,21,224,"roundabout: a known angle that agrees picks the exact exit");
        is(1,1,0,-135,21,96,"roundabout: sharp-left exit from the angle");
        is(1,1,0,90,0,0,"roundabout: angle against the type -> no arrow");
        is(3,1,0,10,21,0,"roundabout: straight with a small angle");
        is(3,1,0,40,0,0,"roundabout: straight but the angle says a turn -> no arrow");
        is(14,1,0,X,0,0,"keep right inside a roundabout without angle -> no arrow");
        is(22,1,0,X,0,0,"highway off-ramp at a roundabout without angle -> no arrow");
        is(23,1,0,60,21,208,"highway off-ramp right at a roundabout with an agreeing angle");
        is(8,1,0,X,0,0,"ramp at a roundabout without angle -> no arrow");
        is(9,1,0,-30,21,16,"ramp at a roundabout with an angle -> that exit (16 bins)");
        is(50,1,0,X,21,224,"slight right (a real turn) at a roundabout without angle");
        is(3,X,X,X,13,0,"straight ahead without junction");
        is(20,X,X,-30,13,32,"left at end, slight angle, no junction");
        is(20,X,X,-10,13,32,"left at end, small angle: slight, never straight");
        is(21,X,X,150,13,160,"right at end, sharp");
        is(21,X,X,X,13,192,"right at end without junction");
        is(47,X,X,X,13,96,"sharp left without junction");
        is(50,X,X,X,13,224,"slight right without junction");
        is(4,X,X,X,25,64,"U-turn without side -> right-hand traffic, left loop");
        is(4,X,1,X,25,192,"U-turn left-hand traffic (strict: junction missing)");
        is(6,0,X,X,13,192,"roundabout entry without side -> right-hand traffic");
        is(7,0,0,X,26,192,"roundabout exit with junction 0 -> exit right");
        is(19,X,X,X,21,128,"U-turn at roundabout without junction/side");
        is(8,0,0,X,13,224,"off ramp without angle -> slight right");
        is(9,0,1,0,13,32,"on ramp angle 0, left-hand traffic -> slight left");
        is(24,1,X,X,3,64,"destination left, odd junction");
        is(25,X,X,X,3,192,"destination right, no junction");
        // 3. Not taken: roundabout exits without an angle, unknown types, no type.
        for(int t=28;t<=46;t++){is(t,1,0,X,0,0,"roundabout exit "+t+" without angle stays empty");is(t,X,X,X,0,0,"roundabout exit "+t+" without anything stays empty");}
        is(54,0,0,0,0,0,"unknown type");
        is(-1,0,0,0,0,0,"negative type");
        int[] none=LiveModel.map(new LiveModel.Message()); check(none[0]==0&&none[1]==0,"no type field");
        check(LiveModel.map(null)[0]==0,"null message");
    }
    static void frame()throws Exception{
        // End to end through the model: start of route (type 11, no exit angle) is the current maneuver.
        TestLanes.Feed f=new TestLanes.Feed();
        f.add(0x5201,TestLanes.join(TestLanes.join(TestLanes.tlv(0,TestLanes.u16(16)),TestLanes.tlv(1,new byte[]{1})),TestLanes.tlv(13,TestLanes.u16(5))));
        f.add(0x5202,TestLanes.join(TestLanes.join(TestLanes.tlv(0,TestLanes.u16(16)),TestLanes.tlv(1,TestLanes.u16(5))),TestLanes.tlv(3,new byte[]{11})));
        LiveModel.Frame fr=f.read();
        check(fr.active&&fr.main==13&&fr.direction==0,"start of route shows a straight arrow at once (got "+fr.main+"/"+fr.direction+")");
    }
    public static void main(String[] args)throws Exception{
        vectors(); frame();
        System.out.println("MANEUVERS_PASS "+checks);
    }
}
