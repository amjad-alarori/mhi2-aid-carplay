/* SPDX-License-Identifier: GPL-3.0-or-later */
package com.pmcp.sl;

/** Host-test stand-in for the sl helper (speedlimit/src/com/pmcp/sl/NativeSpeedLimit.java); never packaged. */
public final class NativeSpeedLimit {
    public static String turnToText(String stock) {
        if ("boom".equals(stock)) throw new IllegalStateException("test failure");
        if ("null".equals(stock)) return null;
        return "Limit 50 km/h | " + stock;
    }
    public static String turnToPreview(String stock) {
        return "Limit 50 km/h | " + stock;
    }
}
