/* SPDX-License-Identifier: GPL-3.0-or-later */
package com.cpmap.rgi;

/** SpeedLimitText: TestSpeedLimitText absent (no sl) | fake (rg/lanes/slfake) | real (speedlimit's pmcp-sl.jar, mode off). */
public final class TestSpeedLimitText {
    static int checks;
    static void check(boolean ok, String what) { checks++; if (!ok) throw new AssertionError(what); }
    static int bytes(String s) throws Exception { return s.getBytes("UTF-8").length; }

    public static void main(String[] args) throws Exception {
        if ("real".equals(args[0])) {
            // the real sl JAR on the classpath, mode file absent (= off): linked, and the text stays unchanged
            check(SpeedLimitText.linkedForTest(), "rg finds turnToText and turnToPreview in the real sl helper");
            check(SpeedLimitText.apply("Main").equals("Main") && SpeedLimitText.preview("Main").equals("Main"), "mode off: unchanged");
            System.out.println("SPEED_LIMIT_TEXT_PASS mode=real checks=" + checks);
            return;
        }
        boolean fake="fake".equals(args[0]);
        SpeedLimitText.resetForTest();
        String road="Inowrocławska";
        if (!fake) {
            check(SpeedLimitText.apply(road).equals(road), "without sl the road text is unchanged");
            check(SpeedLimitText.preview(road).equals(road), "without sl the preview is unchanged");
            check(SpeedLimitText.apply("").equals(""), "without sl an empty road stays empty");
        } else {
            check(SpeedLimitText.apply(road).equals("Limit 50 km/h | " + road), "prefix from sl");
            check(SpeedLimitText.preview(road).equals("Limit 50 km/h | " + road), "preview from sl");
            check(SpeedLimitText.apply("boom").equals("boom"), "sl failure gives the road text");
            check(SpeedLimitText.apply("null").equals("null"), "sl null gives the road text");
            StringBuffer longRoad=new StringBuffer();
            while (bytes(longRoad.toString())<RoadName.MAX_BYTES-1) longRoad.append("ą");   // 2-byte letters
            String out=SpeedLimitText.apply(longRoad.toString());
            check(bytes(out)<=RoadName.MAX_BYTES && out.startsWith("Limit 50 km/h | ą"), "cut to the 75-byte budget");
            check(out.equals(new String(out.getBytes("UTF-8"), "UTF-8")) && out.indexOf('�')<0, "no split character");
        }
        check(SpeedLimitText.fit("abc").equals("abc"), "short text kept");
        StringBuffer ascii=new StringBuffer(); for (int i=0;i<80;i++) ascii.append('a');
        check(bytes(SpeedLimitText.fit(ascii.toString()))==RoadName.MAX_BYTES, "ASCII cut at exactly 75 bytes");
        StringBuffer euro=new StringBuffer(); for (int i=0;i<30;i++) euro.append('€');   // 3-byte letters, 90 bytes
        String cut=SpeedLimitText.fit(euro.toString());
        check(bytes(cut)==75 && cut.indexOf('�')<0, "3-byte letters cut at a character boundary");
        System.out.println("SPEED_LIMIT_TEXT_PASS mode=" + args[0] + " checks=" + checks);
    }
}
