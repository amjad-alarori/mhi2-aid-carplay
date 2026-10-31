/* SPDX-License-Identifier: GPL-3.0-or-later. Host build tool, never installed on the unit. */
import org.objectweb.asm.*;
import org.objectweb.asm.tree.*;
import java.nio.file.*;
import java.util.*;

/**
 * Package E: runs after tomasz-twardzicki's PatchLive (hash-pinned, unchanged) on its six patched NavSD classes and
 * wraps every call into com/cpmap/rgi/LiveBridge with Guard.wrapCall (buildtools/Guard.java), so that a helper J9
 * cannot load or run never reaches the stock BAP code (review 2, finding 1). Fallbacks keep the stock behaviour:
 *   fill hooks (descriptor, distance, route, lanes, destinationDistance, destinationTime, destinationValidity) -> false
 *   attach, detach                                                                                       -> nothing
 *   accepted(boolean stockResult, Function)                                                              -> stockResult
 *   descriptorRouteState(NavigationService)  -> the stock navigationService.getRouteGuidanceState() it replaced
 *   laneIterator(NavigationService)          -> the stock navigationService.getLaneGuidance() it replaced (lanes)
 *   lanesVisible(NavigationService)          -> the stock navigationService.isSetupLaneGuidanceActive() (lanes)
 * With Tomasz's lanes (v1.4.0) LaneGuidance gets no "lanes" fill hook; its factory builder calls laneIterator twice,
 * descriptorRouteState and lanesVisible once instead (6 calls with attach/detach).
 * Expected call counts per class are asserted; anything unknown aborts the build.
 *
 * usage: java GuardLive <stockClassesDir> <patchedClassesDir> [base|lanes]
 */
public final class GuardLive {
    static final String BASE = "de/vw/mib/bap/mqbab2/navsd/functions/";
    static final String HELPER = "com/cpmap/rgi/LiveBridge";
    static final String NAVSVC = "de/vw/mib/bap/mqbab2/common/api/navigation/NavigationService";
    static final Set<String> FILL = new HashSet<String>(Arrays.asList(
            "descriptor", "distance", "route", "lanes", "destinationDistance", "destinationTime", "destinationValidity"));

    static void expect(boolean ok, String what) {
        if (!ok) throw new IllegalStateException("GuardLive: " + what);
    }

    public static void main(String[] a) throws Exception {
        Path stock = Paths.get(a[0]), patched = Paths.get(a[1]);
        // calls per class: fill hook + attach + detach (+ accepted, + destinationValidity, + descriptorRouteState)
        String[] classes = {"ManeuverDescriptor", "DistanceToNextManeuver", "RGStatus", "LaneGuidance", "DistanceToDestination", "TimeToDestination"};
        int[] want = {5, 4, 4, a.length > 2 && a[2].equals("lanes") ? 6 : 3, 5, 4};
        expect(stockRouteStateCalls(stock.resolve(BASE + "ManeuverDescriptor.class")) == 1, "stock getRouteGuidanceState call");
        for (int i = 0; i < classes.length; i++) {
            Path p = patched.resolve(BASE + classes[i] + ".class");
            ClassNode cn = new ClassNode();
            new ClassReader(Files.readAllBytes(p)).accept(cn, ClassReader.SKIP_FRAMES);
            expect(cn.version == 46, cn.name + " version " + cn.version);
            int n = 0;
            for (MethodNode m : cn.methods) {
                List<MethodInsnNode> calls = new ArrayList<MethodInsnNode>();
                for (AbstractInsnNode x : m.instructions)
                    if (x instanceof MethodInsnNode && ((MethodInsnNode) x).owner.equals(HELPER)) calls.add((MethodInsnNode) x);
                for (MethodInsnNode c : calls) {
                    Guard.wrapCall(cn.name, m, c, fallback(c));
                    n++;
                }
            }
            expect(n == want[i], cn.name + " LiveBridge calls " + n + " != " + want[i]);
            Guard.checkAllGuarded(cn, "com/cpmap/");
            ClassWriter cw = new ClassWriter(ClassWriter.COMPUTE_MAXS);
            cn.accept(cw);
            Files.write(p, cw.toByteArray());
            System.out.println("guarded " + cn.name + " (" + n + " calls)");
        }
    }

    static InsnList fallback(MethodInsnNode c) {
        Type[] args = Type.getArgumentTypes(c.desc);
        Type r = Type.getReturnType(c.desc);
        InsnList l = new InsnList();
        if (FILL.contains(c.name)) {
            expect(args.length == 1 && r == Type.BOOLEAN_TYPE, "fill hook " + c.name + c.desc);
            return Guard.popArgsReturnZero(c.desc);
        }
        if (c.name.equals("attach") || c.name.equals("detach")) {
            expect(args.length == 1 && r == Type.VOID_TYPE, c.name + c.desc);
            return Guard.popArgsReturnZero(c.desc);
        }
        if (c.name.equals("accepted")) {
            expect(c.desc.equals("(ZLde/vw/mib/bap/mqbab2/common/api/stages/Function;)Z"), "accepted" + c.desc);
            l.add(new InsnNode(Opcodes.POP));   // drop Function, keep the stock statusProperty result
            return l;
        }
        if (c.name.equals("descriptorRouteState")) {
            expect(c.desc.equals("(L" + NAVSVC + ";)I"), "descriptorRouteState" + c.desc);
            l.add(new MethodInsnNode(Opcodes.INVOKEINTERFACE, NAVSVC, "getRouteGuidanceState", "()I", true));
            return l;
        }
        if (c.name.equals("laneIterator")) {
            expect(c.desc.equals("(L" + NAVSVC + ";)Ljava/util/Iterator;"), "laneIterator" + c.desc);
            l.add(new MethodInsnNode(Opcodes.INVOKEINTERFACE, NAVSVC, "getLaneGuidance", "()Ljava/util/Iterator;", true));
            return l;
        }
        if (c.name.equals("lanesVisible")) {
            expect(c.desc.equals("(L" + NAVSVC + ";)Z"), "lanesVisible" + c.desc);
            l.add(new MethodInsnNode(Opcodes.INVOKEINTERFACE, NAVSVC, "isSetupLaneGuidanceActive", "()Z", true));
            return l;
        }
        throw new IllegalStateException("GuardLive: unknown LiveBridge call " + c.name + c.desc);
    }

    static int stockRouteStateCalls(Path p) throws Exception {
        ClassNode cn = new ClassNode();
        new ClassReader(Files.readAllBytes(p)).accept(cn, ClassReader.SKIP_FRAMES);
        int n = 0;
        for (MethodNode m : cn.methods)
            for (AbstractInsnNode x : m.instructions)
                if (x instanceof MethodInsnNode) {
                    MethodInsnNode c = (MethodInsnNode) x;
                    if (c.name.equals("getRouteGuidanceState")) {
                        expect(c.getOpcode() == Opcodes.INVOKEINTERFACE && c.owner.equals(NAVSVC) && c.desc.equals("()I") && c.itf,
                                "stock getRouteGuidanceState shape");
                        n++;
                    }
                }
        return n;
    }
}
