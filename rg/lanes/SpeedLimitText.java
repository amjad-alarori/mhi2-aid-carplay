/* SPDX-License-Identifier: GPL-3.0-or-later */
package com.cpmap.rgi;

/**
 * Optional native VW speed-limit prefix for the turn-to text that rg writes (TurnToInfo, shown in the AID top bar and
 * in the right dial). The limit comes from the optional sl package (speedlimit/, after amjad-alarori's PR #3): rg looks
 * it up by name, so rg builds and runs unchanged without sl, and with sl in mode off the text stays as it is. Every
 * failure returns the road text unchanged. The result is cut to the factory 75-byte budget at a character boundary.
 */
final class SpeedLimitText {
    static final String HELPER="com.pmcp.sl.NativeSpeedLimit";
    private static boolean resolved;
    private static java.lang.reflect.Method text, preview;

    private SpeedLimitText() {}

    /** On the BAP fill path: the text that goes to TurnToInfo (sl records its filter diagnostics). */
    static String apply(String road) { return call(true, road); }

    /** On rg's refresh loop: the same text without sl's diagnostics, to notice when a refresh is due. */
    static String preview(String road) { return call(false, road); }

    private static synchronized void resolve() {
        if (resolved) return;
        resolved=true;
        try {
            Class c=Class.forName(HELPER);
            // no class literal: helpers target class version 46, where LDC of a class is not allowed
            Class[] one=new Class[]{Class.forName("java.lang.String")};
            text=c.getMethod("turnToText", one);
            preview=c.getMethod("turnToPreview", one);
        } catch (Throwable absent) {
            text=null; preview=null;
        }
    }

    private static String call(boolean full, String road) {
        try {
            resolve();
            java.lang.reflect.Method m=full?text:preview;
            if (m==null) return road;
            Object out=m.invoke(null, new Object[]{road});
            return out instanceof String?fit((String) out):road;
        } catch (Throwable failure) {
            return road;
        }
    }

    static String fit(String s) throws java.io.UnsupportedEncodingException {
        byte[] b=s.getBytes("UTF-8");
        if (b.length<=RoadName.MAX_BYTES) return s;
        int n=RoadName.MAX_BYTES;
        while (n>0 && (b[n]&0xC0)==0x80) n--;   // b[n] is the first byte left out: never split a character
        return new String(b, 0, n, "UTF-8").trim();
    }

    static synchronized void resetForTest() { resolved=false; text=null; preview=null; }
    static synchronized boolean linkedForTest() { resolve(); return text!=null && preview!=null; }
}
