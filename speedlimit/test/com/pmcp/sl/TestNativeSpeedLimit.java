/* SPDX-License-Identifier: GPL-3.0-or-later */
package com.pmcp.sl;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import org.dsi.ifc.trafficregulation.SpeedLimitInfo;
import org.dsi.ifc.trafficregulation.TrafficSignInformation;

/** Host tests run against the converted MU1161 DTO classes. */
public final class TestNativeSpeedLimit {
    private static int checks;

    private static void check(boolean value, String message) {
        checks++;
        if (!value) {
            throw new AssertionError(message);
        }
    }

    private static TrafficSignInformation sign(int speed, int type, int unit) {
        TrafficSignInformation info = new TrafficSignInformation();
        info.highestPrioritySpeedLimit = new SpeedLimitInfo(speed, type, unit);
        info.highestPrioritySign = 1;
        info.secondHighestPrioritySign = 2;
        info.trafficSignOne = 7;
        info.trafficSignTwo = 11;
        info.trafficSignThree = 17;
        info.trafficSignOneSource = 3;
        info.trafficSignTwoSource = 4;
        info.trafficSignThreeSource = 5;
        info.variant = 6;
        return info;
    }

    private static NativeSpeedLimit.Snapshot sample(int speed, int type, int unit, int validity) {
        return new NativeSpeedLimit.Snapshot(sign(speed, type, unit), validity, 1000L);
    }

    private static void writeMode(File file, String value) throws Exception {
        FileOutputStream stream = new FileOutputStream(file);
        try {
            stream.write(value.getBytes("US-ASCII"));
        } finally {
            stream.close();
        }
    }

    private static NativeSpeedLimit.Snapshot observedSample() throws Exception {
        java.lang.reflect.Field field = NativeSpeedLimit.class.getDeclaredField("latest");
        field.setAccessible(true);
        return (NativeSpeedLimit.Snapshot) field.get(null);
    }

    public static void main(String[] args) throws Exception {
        NativeSpeedLimit.Snapshot metric = sample(50, 1, 0, 1);
        check("Limit 50 km/h | Road".equals(NativeSpeedLimit.renderStreet("Road", metric, true, 1001L)), "metric rendering");
        check("Limit 50 km/h".equals(NativeSpeedLimit.renderStreet("", metric, true, 1001L)), "empty street rendering");
        check("Limit 50 km/h".equals(NativeSpeedLimit.renderStreet(null, metric, true, 1001L)), "null street rendering");
        check("Road".equals(NativeSpeedLimit.renderStreet("Road", metric, false, 1001L)), "disabled passthrough");
        check(NativeSpeedLimit.renderStreet(null, metric, false, 1001L) == null, "disabled null passthrough");
        check("Limit 30 mph | Road".equals(NativeSpeedLimit.renderStreet("Road", sample(30, 1, 1, 1), true, 1001L)), "imperial rendering");
        StringBuffer longRoad = new StringBuffer();
        for (int i = 0; i < 300; i++) longRoad.append('R');
        String prefixed = NativeSpeedLimit.renderStreet(longRoad.toString(), metric, true, 1001L);
        check(prefixed.startsWith("Limit 50 km/h | "), "limit precedes a long road before BAP truncation");
        check("valid".equals(NativeSpeedLimit.status(metric, 121000L)), "unchanged limit remains current after two minutes");
        check("valid".equals(NativeSpeedLimit.status(metric, 86401000L)), "unchanged native property remains current on a long road");
        check("clock_reversed".equals(NativeSpeedLimit.status(metric, 999L)), "clock reversal");
        check("Limit 50 km/h | Road".equals(NativeSpeedLimit.renderStreet("Road", metric, true, 86401000L)),
              "long unchanged road retains current limit");
        check("invalid_event".equals(NativeSpeedLimit.status(sample(50, 1, 0, 0), 1001L)), "invalid event");
        check("invalid_event".equals(NativeSpeedLimit.status(sample(50, 1, 0, 2), 1001L)), "unknown validity");
        NativeSpeedLimit.Snapshot initial = sample(50, 1, 0, 0x81);
        check("valid".equals(NativeSpeedLimit.status(initial, 1001L)), "initial-notification validity flag normalized");
        check(initial.rawValidity == 0x81 && initial.validity == 1, "raw validity retained");
        check("invalid_event".equals(NativeSpeedLimit.status(sample(50, 1, 0, 0x82), 1001L)),
              "initial notification with invalid property remains invalid");
        check("invalid_event".equals(NativeSpeedLimit.status(sample(50, 1, 0, 0x8001), 1001L)),
              "unknown high validity bits preserved and rejected");
        check("invalid_event".equals(NativeSpeedLimit.status(sample(50, 1, 0, 0x800081), 1001L)),
              "normalizing the known flag preserves every unknown bit");
        check("limit_unknown".equals(NativeSpeedLimit.status(sample(0, 1, 0, 1), 1001L)), "zero sentinel");
        check("limit_unknown".equals(NativeSpeedLimit.status(sample(1000, 1, 0, 1), 1001L)), "1000 sentinel");
        check("limit_unknown".equals(NativeSpeedLimit.status(sample(-1, 1, 0, 1), 1001L)), "negative sentinel");
        check("unsupported_limit_type".equals(NativeSpeedLimit.status(sample(50, 0, 0, 1), 1001L)), "undefined type");
        check("unsupported_limit_type".equals(NativeSpeedLimit.status(sample(50, 2, 0, 1), 1001L)), "recommended speed excluded");
        check("unit_unknown".equals(NativeSpeedLimit.status(sample(50, 1, 2, 1), 1001L)), "unknown unit");
        check("no_sample".equals(NativeSpeedLimit.status(null, 1001L)), "no sample");
        check("no_sign_info".equals(NativeSpeedLimit.status(new NativeSpeedLimit.Snapshot(null, 1, 1000L), 1001L)), "null sign");
        check("no_limit_info".equals(NativeSpeedLimit.status(new NativeSpeedLimit.Snapshot(new TrafficSignInformation(), 1, 1000L), 1001L)), "null limit");

        NativeSpeedLimit.observe(sign(50, 1, 0), 1);
        check("Limit 50 km/h | Road".equals(NativeSpeedLimit.renderStreet("Road", observedSample(), true, System.currentTimeMillis())),
              "current native event reaches output");
        NativeSpeedLimit.observe(sign(70, 1, 0), 1);
        check("Limit 70 km/h | Road".equals(NativeSpeedLimit.renderStreet("Road", observedSample(), true, System.currentTimeMillis())),
              "later limit replaces earlier limit");
        NativeSpeedLimit.observe(sign(70, 1, 0), 0);
        check("Road".equals(NativeSpeedLimit.renderStreet("Road", observedSample(), true, System.currentTimeMillis())),
              "invalid event replaces valid limit");
        NativeSpeedLimit.observe(null, 1);
        check("Road".equals(NativeSpeedLimit.renderStreet("Road", observedSample(), true, System.currentTimeMillis())),
              "null event clears visible limit");
        NativeSpeedLimit.observe(sign(1000, 1, 0), 1);
        check("Road".equals(NativeSpeedLimit.renderStreet("Road", observedSample(), true, System.currentTimeMillis())),
              "unknown-limit event clears visible limit");

        TrafficSignInformation mutable = sign(70, 1, 0);
        NativeSpeedLimit.Snapshot copied = new NativeSpeedLimit.Snapshot(mutable, 1, 1000L);
        mutable.highestPrioritySpeedLimit.speedLimit = 90;
        mutable.trafficSignOneSource = 99;
        check(copied.speedLimit == 70 && copied.sourceOne == 3, "DTO copied, not retained");
        String state = NativeSpeedLimit.stateText(copied, true, 2000L);
        check(state.indexOf("speed_limit_raw=70\n") >= 0, "raw numeric speed captured");
        check(state.indexOf("sign_one_source_raw=3\n") >= 0, "raw source captured");
        check(state.indexOf("traffic_sign_three_raw=17\n") >= 0, "raw sign captured");
        check(state.indexOf("sample_age_ms=1000\n") >= 0, "age captured");
        check(state.indexOf("stage_registered=") >= 0 && state.indexOf("refresh_errors=") >= 0, "lifecycle diagnostics captured");
        check(state.indexOf("bap_services_ready=0\n") >= 0, "no factory services initialized before BAP registration");
        check(state.indexOf("street_filter_calls=0\n") >= 0 && state.indexOf("turnto_filter_calls=0\n") >= 0,
              "unused routes distinguishable from completed refreshes");
        check("Limit 50 km/h | Private Test Road".equals(NativeSpeedLimit.filterStreet("Private Test Road", metric, true, true, 1001L)),
              "instrumented current-street route decorates");
        String filtered = NativeSpeedLimit.stateText(metric, true, 1002L);
        check(filtered.indexOf("street_filter_calls=1\n") >= 0 && filtered.indexOf("street_filter_decorated=1\n") >= 0,
              "current-street filter counters");
        check(filtered.indexOf("last_filter_reason=decorated\n") >= 0
                && filtered.indexOf("last_filter_output_prefix=Limit 50 km/h\n") >= 0,
              "last returned limit prefix recorded");
        check(filtered.indexOf("Private Test Road") < 0, "street contents excluded from diagnostic file");
        check("Road".equals(NativeSpeedLimit.filterStreet("Road", metric, true, false, 1003L)), "inactive CarPlay passes street through");
        filtered = NativeSpeedLimit.stateText(metric, true, 1004L);
        check(filtered.indexOf("last_filter_reason=carplay_inactive\n") >= 0, "filter gating reason recorded");
        check("Limit 50 km/h | Next Road".equals(NativeSpeedLimit.filterText("Next Road", metric, true, true, false, 1005L, true)),
              "isolated TurnTo route decorates");
        check("Next Road".equals(NativeSpeedLimit.filterText("Next Road", metric, true, true, true, 1006L, true)),
              "conflicting output markers suppress TurnTo output");
        check("Road".equals(NativeSpeedLimit.filterText("Road", metric, true, true, true, 1006L, false)),
              "conflicting output markers suppress current-street output");
        filtered = NativeSpeedLimit.stateText(metric, true, 1007L);
        check(filtered.indexOf("turnto_filter_calls=2\n") >= 0 && filtered.indexOf("turnto_filter_decorated=1\n") >= 0,
              "separate TurnTo filter counters");
        check(filtered.indexOf("turnto_last_filter_reason=output_mode_conflict\n") >= 0,
              "mode-conflict reason recorded");
        check("off".equals(new NativeSpeedLimit.OutputMode(false, false).name()), "off mode");
        check("street".equals(new NativeSpeedLimit.OutputMode(true, false).name()), "current-street mode");
        check("turnto".equals(new NativeSpeedLimit.OutputMode(false, true).name()), "TurnTo mode");
        check("conflict".equals(new NativeSpeedLimit.OutputMode(true, true).name()), "conflicting mode");
        check(NativeSpeedLimit.currentStatusResult(true), "true current-street status result returned unchanged");
        check(!NativeSpeedLimit.currentStatusResult(false), "false current-street status result returned unchanged");
        check(!NativeSpeedLimit.turnToStatusResult(false), "false TurnTo status result returned unchanged");
        check(NativeSpeedLimit.turnToStatusResult(true), "true TurnTo status result returned unchanged");
        filtered = NativeSpeedLimit.stateText(metric, true, 1008L);
        check(filtered.indexOf("current_status_calls=2\n") >= 0 && filtered.indexOf("current_status_true_results=1\n") >= 0
                && filtered.indexOf("current_status_false_results=1\n") >= 0, "current-street BAP result counters");
        check(filtered.indexOf("turnto_status_calls=2\n") >= 0 && filtered.indexOf("turnto_status_last_result=1\n") >= 0,
              "TurnTo BAP result counters");
        check("java.lang.IllegalStateException".equals(NativeSpeedLimit.errorClass(new IllegalStateException("private path"))),
              "only exception class recorded");
        String unchanged = NativeSpeedLimit.stateText(copied, true, 86401000L);
        check(unchanged.indexOf("status=valid\n") >= 0 && unchanged.indexOf("speed_limit_raw=70\n") >= 0
                && unchanged.indexOf("sample_age_ms=86400000\n") >= 0,
              "unchanged native property retains its real event age");
        check(unchanged.indexOf("freshness_policy=native_event\n") >= 0
                && unchanged.indexOf("display_max_sample_age_ms=") < 0, "native-event policy reported");
        check(filtered.length() < 4096, "bounded diagnostic state file");

        NativeSpeedLimit.RefreshGate gate = new NativeSpeedLimit.RefreshGate();
        Object firstStage = new Object();
        Object secondStage = new Object();
        check(gate.request("Limit 50") == null, "no stage, no queued refresh");
        gate.register(firstStage);
        NativeSpeedLimit.RefreshTicket first = gate.request("Limit 50");
        check(first != null, "registration allows initial refresh");
        check(gate.request("Limit 70") == null, "one refresh pending at a time");
        check(gate.beginRun(first) == firstStage, "queued refresh resolves registered stage");
        check(gate.request("Limit 70") == null, "running task remains pending until completion");
        gate.finish(first, true);
        NativeSpeedLimit.RefreshTicket second = gate.request("Limit 70");
        check(second != null, "new value during pending task is not lost");
        check(gate.beginRun(second) == firstStage, "second value reaches same stage");
        gate.finish(second, true);
        check(gate.request("Limit 70") == null, "unchanged value does not requeue");
        NativeSpeedLimit.RefreshTicket clearing = gate.request("");
        check(clearing != null, "invalid source or disable queues clearing output");
        check(gate.unregister(firstStage), "current stage unregister reported");
        gate.register(secondStage);
        check(gate.beginRun(clearing) == null, "queued task for old registration discarded");
        gate.finish(clearing, true);
        NativeSpeedLimit.RefreshTicket failed = gate.request("Limit 70");
        check(failed != null, "new stage gets current value");
        gate.finish(failed, false);
        NativeSpeedLimit.RefreshTicket retry = gate.request("Limit 70");
        check(retry != null, "failed enqueue or process retries same value");
        check(gate.beginRun(failed) == null, "late old task cannot consume new queued refresh");
        gate.finish(failed, false);
        check(gate.diagnostics()[1] == 1 && gate.diagnostics()[2] == 1, "late completion preserves new task and error count");
        check(!gate.unregister(firstStage), "old stage cannot clear a newer service registration");
        check(gate.beginRun(retry) == secondStage, "old-stage unregister preserves new registration");
        gate.finish(retry, false);
        check(gate.diagnostics()[0] == 1 && gate.diagnostics()[1] == 0 && gate.diagnostics()[2] == 2, "refresh failure diagnostics");
        NativeSpeedLimit.RefreshTicket processRetry = gate.request("Limit 70");
        check(processRetry != null, "process failure allows same-key retry");
        check(gate.beginRun(processRetry) == secondStage, "retried process starts");
        gate.finish(processRetry, true);
        long[] counts = gate.diagnostics();
        check(counts[3] == 6 && counts[4] == 4 && counts[5] == 3 && counts[6] == 1,
              "requested, started, completed and discarded tasks distinguishable");

        File output = File.createTempFile("pmcp-native-speedlimit-", ".state");
        try {
            NativeSpeedLimit.writeState(output, state);
            NativeSpeedLimit.writeState(output, unchanged);
            byte[] bytes = new byte[(int) output.length()];
            FileInputStream input = new FileInputStream(output);
            int count = 0;
            try {
                for (;;) {
                    int read = input.read(bytes, count, bytes.length - count);
                    if (read <= 0) break;
                    count += read;
                }
            } finally {
                input.close();
            }
            check(count == bytes.length && unchanged.equals(new String(bytes, "US-ASCII")), "complete replacement writes");
            check(!new File(output.getPath() + ".new").exists(), "temporary file consumed");

            File temporary = new File(output.getPath() + ".new");
            check(temporary.mkdir(), "make failing temporary-file path");
            boolean refused = false;
            try {
                NativeSpeedLimit.writeState(output, state);
            } catch (java.io.IOException expected) {
                refused = true;
            }
            check(refused && output.length() == bytes.length, "failed staging preserves previous diagnostic file");
            FileInputStream previous = new FileInputStream(output);
            byte[] afterFailure = new byte[bytes.length];
            try {
                check(previous.read(afterFailure) == afterFailure.length, "previous diagnostic file remains readable");
            } finally {
                previous.close();
            }
            check(unchanged.equals(new String(afterFailure, "US-ASCII")), "failed staging leaves old content intact");
            check(temporary.delete(), "remove test-only temporary directory");
        } finally {
            output.delete();
            new File(output.getPath() + ".new").delete();
        }

        File modeFile = File.createTempFile("pmcp-native-speedlimit-mode-", ".txt");
        try {
            writeMode(modeFile, "off\n");
            check("off".equals(NativeSpeedLimit.readMode(modeFile).name()), "explicit persisted off mode");
            writeMode(modeFile, "street\n");
            check("street".equals(NativeSpeedLimit.readMode(modeFile).name()), "persisted current-street mode");
            check("street".equals(NativeSpeedLimit.readMode(new File(modeFile.getPath())).name()),
                  "mode survives independent file-reader initialization");
            writeMode(modeFile, "turnto\n");
            check("turnto".equals(NativeSpeedLimit.readMode(modeFile).name()), "persisted next-street mode");
            String[] invalidModes = {"", "street", "turnto\r\n", "STREET\n", "street\nturnto\n",
                    "street\n\u0000", " street\n", "street\n123456789", "street\n1234567890"};
            for (int i = 0; i < invalidModes.length; i++) {
                writeMode(modeFile, invalidModes[i]);
                check("off".equals(NativeSpeedLimit.readMode(modeFile).name()), "malformed persisted mode disabled " + i);
            }
            check(modeFile.delete(), "remove temporary mode file");
            check("off".equals(NativeSpeedLimit.readMode(modeFile).name()), "missing mode file disables output");
            File disappeared = new File(modeFile.getPath()) {
                public boolean isFile() {
                    return true;
                }
            };
            check("off".equals(NativeSpeedLimit.readMode(disappeared).name()),
                  "mode disappearing before open disables output");
            check(modeFile.mkdir(), "make non-file mode path");
            check("off".equals(NativeSpeedLimit.readMode(modeFile).name()), "non-file mode path disables output");
        } finally {
            modeFile.delete();
        }
        System.out.println("TestNativeSpeedLimit checks=" + checks);
    }
}
