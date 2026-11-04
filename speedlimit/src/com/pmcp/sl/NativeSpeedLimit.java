/* SPDX-License-Identifier: GPL-3.0-or-later */
package com.pmcp.sl;

import de.vw.mib.bap.mqbab2.common.api.APIFactory;
import de.vw.mib.bap.mqbab2.common.api.APIFactoryInterface;
import de.vw.mib.bap.mqbab2.common.api.smartphoneintegration.SmartphoneIntegrationService;
import de.vw.mib.bap.mqbab2.common.api.stages.BAPStage;
import de.vw.mib.bap.mqbab2.navsd.functions.CurrentPositionInfo;
import de.vw.mib.bap.mqbab2.navsd.functions.TurnToInfo;
import de.vw.mib.genericevents.ThreadSwitchingTarget;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import org.dsi.ifc.trafficregulation.SpeedLimitInfo;
import org.dsi.ifc.trafficregulation.TrafficSignInformation;

/** Captures the native map limit and supplies the selected navigation text. */
public final class NativeSpeedLimit {
    static final String STATE_PATH = "/ramdisk/pmcp-speedlimit.state";
    static final String MODE_PATH = "/mnt/persist/pmcp/native-speedlimit-mode";
    static final long WRITE_INTERVAL_MS = 1000L;

    private static volatile Snapshot latest;
    private static volatile OutputMode outputMode = new OutputMode(false, false);
    private static volatile Services services;
    private static volatile FilterDiagnostics streetDiagnostics;
    private static volatile FilterDiagnostics turnToDiagnostics;
    private static volatile StatusDiagnostics currentStatusDiagnostics;
    private static volatile StatusDiagnostics turnToStatusDiagnostics;
    private static volatile ConnectionDiagnostics connectionDiagnostics;
    private static volatile String refreshErrorClass = "";
    private static volatile int refreshEnqueued;
    private static volatile String turnToRefreshErrorClass = "";
    private static volatile int turnToRefreshEnqueued;
    private static final RefreshGate REFRESH_GATE = new RefreshGate();
    private static final RefreshGate TURNTO_REFRESH_GATE = new RefreshGate();

    static {
        try {
            Thread writer = new Thread(new Runnable() {
                public void run() {
                    writeLoop();
                }
            }, "pmcp-native-speedlimit");
            writer.setDaemon(true);
            writer.start();
        } catch (Throwable ignored) {
            // Capturing data must never prevent the factory callback from running.
        }
    }

    private NativeSpeedLimit() {
    }

    /**
     * Called by a guarded hook at the entry of updateCurrentTrafficSign.
     * Only immutable primitive values cross to the writer thread. The DSI DTO is
     * never retained, changed or used from a background thread.
     */
    public static void observe(TrafficSignInformation info, int validity) {
        try {
            latest = new Snapshot(info, validity, System.currentTimeMillis());
        } catch (Throwable ignored) {
            latest = null;
        }
    }

    public static void register(CurrentPositionInfo target) {
        try {
            registerStage(REFRESH_GATE, target);
        } catch (Throwable ignored) {
            // Factory output remains available when registration fails.
        }
    }

    public static void unregister(CurrentPositionInfo target) {
        try {
            if (REFRESH_GATE.unregister(target) && !TURNTO_REFRESH_GATE.registered()) {
                services = null;
            }
        } catch (Throwable ignored) {
            // Factory output remains available when registration fails.
        }
    }

    public static void registerTurnTo(TurnToInfo target) {
        try {
            registerStage(TURNTO_REFRESH_GATE, target);
        } catch (Throwable ignored) {
            // Factory output remains available when registration fails.
        }
    }

    public static void unregisterTurnTo(TurnToInfo target) {
        try {
            if (TURNTO_REFRESH_GATE.unregister(target) && !REFRESH_GATE.registered()) {
                services = null;
            }
        } catch (Throwable ignored) {
            // Factory output remains available when registration fails.
        }
    }

    private static void registerStage(RefreshGate gate, Object target) {
        if (target == null) {
            return;
        }
        if (services == null) {
            try {
                // Both factory getters can initialize ASL observers. Resolve
                // them here on the native BAP lifecycle thread only.
                APIFactoryInterface factory = APIFactory.getAPIFactory();
                SmartphoneIntegrationService smartphone = factory.getSmartphoneIntegrationService();
                ThreadSwitchingTarget threading = factory.getThreadSwitchingService();
                if (smartphone != null && threading != null) {
                    services = new Services(smartphone, threading);
                }
            } catch (Throwable ignored) {
                // Capturing data continues while visible output stays off.
            }
        }
        gate.register(target);
    }

    /** Called on the existing output path with its original street text. */
    public static String streetText(String stock) {
        try {
            OutputMode mode = outputMode;
            return filterText(stock, latest, mode.street, carPlayActive(), mode.conflict,
                    System.currentTimeMillis(), false);
        } catch (Throwable failure) {
            recordFilterFailure(stock, failure, false);
            return stock;
        }
    }

    public static String turnToText(String stock) {
        try {
            OutputMode mode = outputMode;
            return filterText(stock, latest, mode.turnTo, carPlayActive(), mode.conflict,
                    System.currentTimeMillis(), true);
        } catch (Throwable failure) {
            recordFilterFailure(stock, failure, true);
            return stock;
        }
    }

    public static boolean currentStatusResult(boolean stock) {
        try {
            currentStatusDiagnostics = new StatusDiagnostics(currentStatusDiagnostics, stock, System.currentTimeMillis());
        } catch (Throwable ignored) {
            // The factory result remains the caller's result.
        }
        return stock;
    }

    public static boolean turnToStatusResult(boolean stock) {
        try {
            turnToStatusDiagnostics = new StatusDiagnostics(turnToStatusDiagnostics, stock, System.currentTimeMillis());
        } catch (Throwable ignored) {
            // The factory result remains the caller's result.
        }
        return stock;
    }

    static String filterStreet(String stock, Snapshot sample, boolean enabled, boolean active, long now) {
        return filterText(stock, sample, enabled, active, false, now, false);
    }

    static String filterText(String stock, Snapshot sample, boolean enabled, boolean active,
            boolean conflict, long now, boolean turnTo) {
        String result = renderStreet(stock, sample, enabled && active && !conflict, now);
        String reason = conflict ? "output_mode_conflict"
                : (enabled ? (active ? status(sample, now) : "carplay_inactive") : "disabled");
        boolean decorated = "valid".equals(reason);
        try {
            FilterDiagnostics record = new FilterDiagnostics(turnTo ? turnToDiagnostics : streetDiagnostics, now,
                    decorated ? "decorated" : reason, decorated ? limitText(sample) : "",
                    stock == null ? -1 : stock.length(), result == null ? -1 : result.length(), "");
            if (turnTo) {
                turnToDiagnostics = record;
            } else {
                streetDiagnostics = record;
            }
        } catch (Throwable ignored) {
            // Recording diagnostics cannot change the string returned to BAP.
        }
        return result;
    }

    private static void recordFilterFailure(String stock, Throwable failure, boolean turnTo) {
        try {
            FilterDiagnostics record = new FilterDiagnostics(turnTo ? turnToDiagnostics : streetDiagnostics, System.currentTimeMillis(),
                    "exception", "", stock == null ? -1 : stock.length(),
                    stock == null ? -1 : stock.length(), errorClass(failure));
            if (turnTo) {
                turnToDiagnostics = record;
            } else {
                streetDiagnostics = record;
            }
        } catch (Throwable ignored) {
            // The guard can still return the original street string.
        }
    }

    private static boolean carPlayActive() {
        try {
            Services cached = services;
            if (cached == null) {
                connectionDiagnostics = new ConnectionDiagnostics(-1, System.currentTimeMillis(), "services_unavailable");
                return false;
            }
            int type = cached.smartphone.getSmarphoneIntegrationActiveConnectionType();
            connectionDiagnostics = new ConnectionDiagnostics(type, System.currentTimeMillis(), "");
            return type == 2;
        } catch (Throwable failure) {
            try {
                connectionDiagnostics = new ConnectionDiagnostics(-2, System.currentTimeMillis(), errorClass(failure));
            } catch (Throwable ignored) {
                // Keep the last diagnostic value if allocation also fails.
            }
            return false;
        }
    }

    static String renderStreet(String stock, Snapshot sample, boolean enabled, long now) {
        if (!enabled || !"valid".equals(status(sample, now))) {
            return stock;
        }
        String text = limitText(sample);
        if (stock == null || stock.length() == 0) {
            return text;
        }
        return new StringBuffer(text).append(" | ").append(stock).toString();
    }

    static String limitText(Snapshot sample) {
        return new StringBuffer("Limit ").append(sample.speedLimit)
                .append(sample.speedUnit == 0 ? " km/h" : " mph").toString();
    }

    static String status(Snapshot sample, long now) {
        if (sample == null) {
            return "no_sample";
        }
        if (sample.validity != 1) {
            return "invalid_event";
        }
        if (!sample.signPresent) {
            return "no_sign_info";
        }
        if (!sample.limitPresent) {
            return "no_limit_info";
        }
        if (sample.speedLimitType != 1) {
            return "unsupported_limit_type";
        }
        if (sample.speedLimit <= 0 || sample.speedLimit >= 1000) {
            return "limit_unknown";
        }
        if (sample.speedUnit != 0 && sample.speedUnit != 1) {
            return "unit_unknown";
        }
        if (now < sample.sampleMs) {
            return "clock_reversed";
        }
        // This DSI attribute represents the current native property. Its
        // unchanged value remains current until a later event replaces it.
        return "valid";
    }

    /** Reads only the small, explicit mode file, with all failures disabling output. */
    static OutputMode readMode(File modeFile) {
        FileInputStream stream = null;
        try {
            if (!modeFile.isFile()) {
                return new OutputMode(false, false);
            }
            stream = new FileInputStream(modeFile);
            byte[] bytes = new byte[16];
            int count = 0;
            while (count < bytes.length) {
                int read = stream.read(bytes, count, bytes.length - count);
                if (read < 0) {
                    break;
                }
                if (read == 0) {
                    throw new java.io.IOException("Mode read made no progress");
                }
                count += read;
            }
            stream.close();
            stream = null;
            if (count < bytes.length) {
                String value = new String(bytes, 0, count, "US-ASCII");
                if ("street\n".equals(value)) {
                    return new OutputMode(true, false);
                }
                if ("turnto\n".equals(value)) {
                    return new OutputMode(false, true);
                }
            }
        } catch (Throwable ignored) {
            // A missing, unreadable or malformed setting always disables output.
        } finally {
            if (stream != null) {
                try {
                    stream.close();
                } catch (Throwable ignored) {
                    // The failed read has already selected the off state.
                }
            }
        }
        return new OutputMode(false, false);
    }

    private static void writeLoop() {
        File state = new File(STATE_PATH);
        File modeFile = new File(MODE_PATH);
        for (;;) {
            outputMode = readMode(modeFile);
            Snapshot sample = latest;
            long now = System.currentTimeMillis();
            boolean active = carPlayActive();
            OutputMode mode = outputMode;
            try {
                String visible = renderStreet("", sample, mode.street && !mode.conflict && active, now);
                requestRefresh(REFRESH_GATE, visible, false);
                String turnToVisible = renderStreet("", sample, mode.turnTo && !mode.conflict && active, now);
                requestRefresh(TURNTO_REFRESH_GATE, turnToVisible, true);
            } catch (Throwable ignored) {
                // The next pass retries while the factory output path stays usable.
            }
            try {
                writeState(state, stateText(sample, mode.street, active, now));
            } catch (Throwable ignored) {
                // Publishing diagnostics is independent of the display refresh.
            }
            try {
                Thread.sleep(WRITE_INTERVAL_MS);
            } catch (InterruptedException interrupted) {
                outputMode = new OutputMode(false, false);
                return;
            } catch (Throwable ignored) {
                outputMode = new OutputMode(false, false);
                return;
            }
        }
    }

    private static void requestRefresh(RefreshGate gate, String visible, boolean turnTo) {
        RefreshTicket ticket = gate.request(visible);
        if (ticket == null) {
            return;
        }
        try {
            Services cached = services;
            if (cached == null) {
                recordRefreshError(turnTo, "services_unavailable");
                gate.finish(ticket, false);
                return;
            }
            cached.threading.enqueue(new RefreshTask(gate, ticket, turnTo));
            if (turnTo) {
                turnToRefreshEnqueued++;
            } else {
                refreshEnqueued++;
            }
        } catch (Throwable failure) {
            recordRefreshError(turnTo, errorClass(failure));
            gate.finish(ticket, false);
        }
    }

    private static void recordRefreshError(boolean turnTo, String error) {
        if (turnTo) {
            turnToRefreshErrorClass = error;
        } else {
            refreshErrorClass = error;
        }
    }

    static void writeState(File state, String text) throws java.io.IOException {
        File temporary = new File(new StringBuffer(state.getPath()).append(".new").toString());
        FileOutputStream stream = null;
        try {
            stream = new FileOutputStream(temporary);
            stream.write(text.getBytes("US-ASCII"));
            stream.flush();
        } finally {
            if (stream != null) {
                stream.close();
            }
        }
        if (!temporary.renameTo(state)) {
            // Some hosts cannot rename over an existing file. The fallback can
            // leave a brief missing-file window, but only complete files publish.
            if (!state.isFile() || !state.delete() || !temporary.renameTo(state)) {
                throw new java.io.IOException("Speed-limit state rename failed");
            }
        }
    }

    /** The current file is bounded and includes raw values for invalid events. */
    static String stateText(Snapshot sample, boolean enabled, long now) {
        return stateText(sample, enabled, false, now);
    }

    static String stateText(Snapshot sample, boolean enabled, boolean carPlay, long now) {
        StringBuffer text = new StringBuffer("schema=pmcp-native-speedlimit-v1\n");
        append(text, "heartbeat_ms", now);
        append(text, "display_enabled", enabled ? 1 : 0);
        OutputMode mode = outputMode;
        append(text, "turnto_enabled", mode.turnTo ? 1 : 0);
        text.append("output_mode=").append(new OutputMode(enabled, mode.turnTo).name()).append('\n');
        append(text, "carplay_active", carPlay ? 1 : 0);
        text.append("freshness_policy=native_event\n");
        append(text, "bap_services_ready", services == null ? 0 : 1);
        long[] refresh = REFRESH_GATE.diagnostics();
        append(text, "stage_registered", refresh[0]);
        append(text, "refresh_pending", refresh[1]);
        append(text, "refresh_errors", refresh[2]);
        append(text, "refresh_requested", refresh[3]);
        append(text, "refresh_started", refresh[4]);
        append(text, "refresh_completed", refresh[5]);
        append(text, "refresh_discarded", refresh[6]);
        append(text, "refresh_enqueued", refreshEnqueued);
        text.append("refresh_last_error_class=").append(refreshErrorClass).append('\n');
        long[] turnToRefresh = TURNTO_REFRESH_GATE.diagnostics();
        append(text, "turnto_stage_registered", turnToRefresh[0]);
        append(text, "turnto_refresh_pending", turnToRefresh[1]);
        append(text, "turnto_refresh_errors", turnToRefresh[2]);
        append(text, "turnto_refresh_requested", turnToRefresh[3]);
        append(text, "turnto_refresh_started", turnToRefresh[4]);
        append(text, "turnto_refresh_completed", turnToRefresh[5]);
        append(text, "turnto_refresh_discarded", turnToRefresh[6]);
        append(text, "turnto_refresh_enqueued", turnToRefreshEnqueued);
        text.append("turnto_refresh_last_error_class=").append(turnToRefreshErrorClass).append('\n');
        ConnectionDiagnostics connection = connectionDiagnostics;
        append(text, "connection_type_raw", connection == null ? -1 : connection.type);
        append(text, "connection_last_read_ms", connection == null ? 0L : connection.readMs);
        text.append("connection_error_class=").append(connection == null ? "" : connection.error).append('\n');
        appendFilterDiagnostics(text, streetDiagnostics, "street_", "last_filter_");
        appendFilterDiagnostics(text, turnToDiagnostics, "turnto_", "turnto_last_filter_");
        appendStatusDiagnostics(text, currentStatusDiagnostics, "current_status_");
        appendStatusDiagnostics(text, turnToStatusDiagnostics, "turnto_status_");
        text.append("status=").append(status(sample, now)).append('\n');
        append(text, "snapshot_present", sample == null ? 0 : 1);
        if (sample == null) {
            return text.toString();
        }
        append(text, "last_sample_ms", sample.sampleMs);
        append(text, "sample_age_ms", now >= sample.sampleMs ? now - sample.sampleMs : -1L);
        append(text, "event_validity", sample.validity);
        append(text, "event_validity_raw", sample.rawValidity);
        append(text, "sign_present", sample.signPresent ? 1 : 0);
        append(text, "limit_present", sample.limitPresent ? 1 : 0);
        append(text, "speed_limit_raw", sample.speedLimit);
        append(text, "speed_limit_type_raw", sample.speedLimitType);
        append(text, "speed_unit_raw", sample.speedUnit);
        append(text, "highest_priority_sign_raw", sample.highestPrioritySign);
        append(text, "second_priority_sign_raw", sample.secondPrioritySign);
        append(text, "traffic_sign_one_raw", sample.signOne);
        append(text, "traffic_sign_two_raw", sample.signTwo);
        append(text, "traffic_sign_three_raw", sample.signThree);
        append(text, "sign_one_source_raw", sample.sourceOne);
        append(text, "sign_two_source_raw", sample.sourceTwo);
        append(text, "sign_three_source_raw", sample.sourceThree);
        append(text, "variant_raw", sample.variant);
        return text.toString();
    }

    static void append(StringBuffer text, String key, long value) {
        text.append(key).append('=').append(value).append('\n');
    }

    private static void appendFilterDiagnostics(StringBuffer text, FilterDiagnostics filter,
            String counterPrefix, String lastPrefix) {
        append(text, new StringBuffer(counterPrefix).append("filter_calls").toString(), filter == null ? 0L : filter.calls);
        append(text, new StringBuffer(counterPrefix).append("filter_decorated").toString(), filter == null ? 0L : filter.decorated);
        append(text, new StringBuffer(counterPrefix).append("filter_failures").toString(), filter == null ? 0L : filter.failures);
        append(text, new StringBuffer(lastPrefix).append("ms").toString(), filter == null ? 0L : filter.calledMs);
        text.append(lastPrefix).append("reason=").append(filter == null ? "never_called" : filter.reason).append('\n');
        text.append(lastPrefix).append("output_prefix=").append(filter == null ? "" : filter.outputPrefix).append('\n');
        append(text, new StringBuffer(lastPrefix).append("input_length").toString(), filter == null ? -1 : filter.inputLength);
        append(text, new StringBuffer(lastPrefix).append("output_length").toString(), filter == null ? -1 : filter.outputLength);
        text.append(lastPrefix).append("error_class=").append(filter == null ? "" : filter.error).append('\n');
    }

    static String errorClass(Throwable failure) {
        try {
            String name = failure.getClass().getName();
            return name.length() > 120 ? name.substring(0, 120) : name;
        } catch (Throwable ignored) {
            return "unknown_error";
        }
    }

    private static void appendStatusDiagnostics(StringBuffer text, StatusDiagnostics record, String prefix) {
        append(text, new StringBuffer(prefix).append("calls").toString(), record == null ? 0L : record.calls);
        append(text, new StringBuffer(prefix).append("true_results").toString(), record == null ? 0L : record.trueResults);
        append(text, new StringBuffer(prefix).append("false_results").toString(), record == null ? 0L : record.falseResults);
        append(text, new StringBuffer(prefix).append("last_result").toString(), record == null ? -1 : (record.lastResult ? 1 : 0));
        append(text, new StringBuffer(prefix).append("last_ms").toString(), record == null ? 0L : record.calledMs);
    }

    private static final class StatusDiagnostics {
        final long calls;
        final long trueResults;
        final long falseResults;
        final boolean lastResult;
        final long calledMs;

        StatusDiagnostics(StatusDiagnostics previous, boolean result, long now) {
            calls = (previous == null ? 0L : previous.calls) + 1L;
            trueResults = (previous == null ? 0L : previous.trueResults) + (result ? 1L : 0L);
            falseResults = (previous == null ? 0L : previous.falseResults) + (result ? 0L : 1L);
            lastResult = result;
            calledMs = now;
        }
    }

    static final class OutputMode {
        final boolean street;
        final boolean turnTo;
        final boolean conflict;

        OutputMode(boolean currentStreet, boolean nextStreet) {
            street = currentStreet;
            turnTo = nextStreet;
            conflict = street && turnTo;
        }

        String name() {
            if (conflict) return "conflict";
            if (street) return "street";
            if (turnTo) return "turnto";
            return "off";
        }
    }

    private static final class ConnectionDiagnostics {
        final int type;
        final long readMs;
        final String error;

        ConnectionDiagnostics(int value, long now, String failure) {
            type = value;
            readMs = now;
            error = failure;
        }
    }

    private static final class FilterDiagnostics {
        final long calls;
        final long decorated;
        final long failures;
        final long calledMs;
        final String reason;
        final String outputPrefix;
        final int inputLength;
        final int outputLength;
        final String error;

        FilterDiagnostics(FilterDiagnostics previous, long now, String why, String prefix,
                int inputSize, int outputSize, String failure) {
            calls = (previous == null ? 0L : previous.calls) + 1L;
            decorated = (previous == null ? 0L : previous.decorated) + ("decorated".equals(why) ? 1L : 0L);
            failures = (previous == null ? 0L : previous.failures) + ("exception".equals(why) ? 1L : 0L);
            calledMs = now;
            reason = why;
            outputPrefix = prefix;
            inputLength = inputSize;
            outputLength = outputSize;
            error = failure;
        }
    }

    static final class Snapshot {
        final long sampleMs;
        final int validity;
        final int rawValidity;
        final boolean signPresent;
        final boolean limitPresent;
        final int speedLimit;
        final int speedLimitType;
        final int speedUnit;
        final int highestPrioritySign;
        final int secondPrioritySign;
        final int signOne;
        final int signTwo;
        final int signThree;
        final int sourceOne;
        final int sourceTwo;
        final int sourceThree;
        final int variant;

        Snapshot(TrafficSignInformation info, int valid, long now) {
            sampleMs = now;
            rawValidity = valid;
            // The MU1161 dispatcher removes the 0x80 initial-notification flag.
            // Retain every other bit so unknown validity values fail closed.
            validity = valid & ~0x80;
            signPresent = info != null;
            SpeedLimitInfo limit = info == null ? null : info.highestPrioritySpeedLimit;
            limitPresent = limit != null;
            speedLimit = limit == null ? 0 : limit.speedLimit;
            speedLimitType = limit == null ? 0 : limit.speedLimitType;
            speedUnit = limit == null ? -1 : limit.speedUnit;
            highestPrioritySign = info == null ? 0 : info.highestPrioritySign;
            secondPrioritySign = info == null ? 0 : info.secondHighestPrioritySign;
            signOne = info == null ? 0 : info.trafficSignOne;
            signTwo = info == null ? 0 : info.trafficSignTwo;
            signThree = info == null ? 0 : info.trafficSignThree;
            sourceOne = info == null ? 0 : info.trafficSignOneSource;
            sourceTwo = info == null ? 0 : info.trafficSignTwoSource;
            sourceThree = info == null ? 0 : info.trafficSignThreeSource;
            variant = info == null ? 0 : info.variant;
        }
    }

    private static final class Services {
        final SmartphoneIntegrationService smartphone;
        final ThreadSwitchingTarget threading;

        Services(SmartphoneIntegrationService integration, ThreadSwitchingTarget queue) {
            smartphone = integration;
            threading = queue;
        }
    }

    static final class RefreshTicket {
        final Object target;
        final long generation;
        boolean started;

        RefreshTicket(Object value, long id) {
            target = value;
            generation = id;
        }
    }

    private static final class RefreshTask implements Runnable {
        private final RefreshGate gate;
        private final RefreshTicket ticket;
        private final boolean turnTo;

        RefreshTask(RefreshGate owner, RefreshTicket value, boolean nextStreet) {
            gate = owner;
            ticket = value;
            turnTo = nextStreet;
        }

        public void run() {
            boolean success = true;
            try {
                Object target = gate.beginRun(ticket);
                if (target != null) {
                    ((BAPStage) target).process(-1);
                }
            } catch (Throwable failure) {
                success = false;
                recordRefreshError(turnTo, errorClass(failure));
            } finally {
                gate.finish(ticket, success);
            }
        }
    }

    /** Coalesces refreshes through completion and rejects obsolete queued tasks. */
    static final class RefreshGate {
        private Object target;
        private String lastKey;
        private RefreshTicket pending;
        private long generation;
        private long failures;
        private long requested;
        private long started;
        private long completed;
        private long discarded;

        synchronized void register(Object value) {
            target = value;
            generation++;
            lastKey = null;
        }

        synchronized boolean unregister(Object value) {
            if (target == value) {
                target = null;
                generation++;
                lastKey = null;
                return true;
            }
            return false;
        }

        synchronized boolean registered() {
            return target != null;
        }

        synchronized RefreshTicket request(String key) {
            if (target == null || pending != null || key.equals(lastKey)) {
                return null;
            }
            lastKey = key;
            pending = new RefreshTicket(target, generation);
            requested++;
            return pending;
        }

        synchronized Object beginRun(RefreshTicket ticket) {
            if (ticket != pending || ticket.generation != generation || ticket.target != target) {
                return null;
            }
            ticket.started = true;
            started++;
            return target;
        }

        synchronized void finish(RefreshTicket ticket, boolean success) {
            if (ticket != pending) {
                return;
            }
            pending = null;
            if (!success) {
                failures++;
                lastKey = null;
            } else if (ticket.started) {
                completed++;
            } else {
                discarded++;
            }
        }

        synchronized long[] diagnostics() {
            return new long[] {target == null ? 0L : 1L, pending == null ? 0L : 1L,
                    failures, requested, started, completed, discarded};
        }
    }
}
