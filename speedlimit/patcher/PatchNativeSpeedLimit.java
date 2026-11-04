/* SPDX-License-Identifier: GPL-3.0-or-later. Host build tool, never installed on the unit. */
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.stream.Stream;
import org.objectweb.asm.ClassReader;
import org.objectweb.asm.ClassWriter;
import org.objectweb.asm.Opcodes;
import org.objectweb.asm.Type;
import org.objectweb.asm.tree.AbstractInsnNode;
import org.objectweb.asm.tree.ClassNode;
import org.objectweb.asm.tree.InsnList;
import org.objectweb.asm.tree.InvokeDynamicInsnNode;
import org.objectweb.asm.tree.LdcInsnNode;
import org.objectweb.asm.tree.MethodInsnNode;
import org.objectweb.asm.tree.MethodNode;
import org.objectweb.asm.tree.VarInsnNode;
import org.objectweb.asm.tree.analysis.AnalyzerException;

/**
 * MU1161 optional native-map speed-limit text. The dispatcher hook only copies a
 * sample. The NavSD hook filters the existing street string and registers its
 * factory BAP function for refresh on the factory thread-switching service.
 * Every firmware-to-helper call has a Throwable guard with a stock fallback.
 *
 * Usage: PatchNativeSpeedLimit <stockClassesDir> <helperClassesDir> <outDir>
 */
public final class PatchNativeSpeedLimit {
    static final String HELPER = "com/pmcp/sl/NativeSpeedLimit";
    static final String DISPATCHER =
            "de/esolutions/fw/dsi/trafficregulation/DSITrafficRegulationDispatcher";
    static final String POSITION =
            "de/vw/mib/bap/mqbab2/navsd/functions/CurrentPositionInfo";
    static final String STATUS =
            "de/vw/mib/bap/mqbab2/generated/navsd/serializer/CurrentPositionInfo_Status";
    static final String TURN_TO =
            "de/vw/mib/bap/mqbab2/navsd/functions/TurnToInfo";
    static final String TURN_TO_STATUS =
            "de/vw/mib/bap/mqbab2/generated/navsd/serializer/TurnToInfo_Status";
    static final String SIGN = "org/dsi/ifc/trafficregulation/TrafficSignInformation";
    static final int FACTORY_VERSION = 46;

    // Exact classes in deterministic converted MU1161 lsd.jar 573b603a0b79b6c1.
    static final String DISPATCHER_SHA256 =
            "dff382ac9400272e5e97f57d6be7ea145069f6a01a8547cf47d2b2daab2c660a";
    static final String POSITION_SHA256 =
            "670abf196f45437c072536173ed8f9c445dae9f2ae89f04a10ed89cec268240a";
    static final String TURN_TO_SHA256 =
            "af643e32ede0adaeab7972a2ac33ec7cc3d085d0af422bba3182cc94a9d43878";

    private final Path stock;
    private final Path helpers;
    private final Path output;

    private PatchNativeSpeedLimit(Path stock, Path helpers, Path output) {
        this.stock = stock;
        this.helpers = helpers;
        this.output = output;
    }

    public static void main(String[] args) throws Exception {
        expect(args.length == 3,
                "usage: PatchNativeSpeedLimit <stock> <helpers> <output>");
        PatchNativeSpeedLimit patcher = new PatchNativeSpeedLimit(
                Paths.get(args[0]), Paths.get(args[1]), Paths.get(args[2]));
        expect(!patcher.stock.toAbsolutePath().normalize().equals(
                patcher.output.toAbsolutePath().normalize()), "output equals stock");
        patcher.patchDispatcher();
        patcher.patchCurrentPosition();
        patcher.patchTurnTo();
        patcher.copyHelpers();
        System.out.println("Native speed-limit text hooks built");
    }

    static void expect(boolean condition, String message) {
        if (!condition) {
            throw new IllegalStateException("speed-limit patch mismatch: " + message);
        }
    }

    private ClassNode readStock(String name, String expectedHash) throws Exception {
        expect(expectedHash.length() == 64, "stock class hash has not been pinned");
        byte[] bytes = Files.readAllBytes(stock.resolve(name + ".class"));
        expect(sha256(bytes).equals(expectedHash), "stock hash " + name);
        ClassNode node = read(bytes);
        expect(node.name.equals(name), "class name " + node.name);
        expect(node.version == 46 || node.version == 49,
                name + " class version " + node.version);
        rejectModernInstructions(node);
        node.version = FACTORY_VERSION;
        return node;
    }

    static ClassNode read(byte[] bytes) {
        ClassNode node = new ClassNode();
        new ClassReader(bytes).accept(node, ClassReader.SKIP_FRAMES);
        return node;
    }

    static String sha256(byte[] bytes) throws Exception {
        byte[] digest = MessageDigest.getInstance("SHA-256").digest(bytes);
        StringBuilder text = new StringBuilder();
        for (byte value : digest) {
            text.append(String.format("%02x", value & 255));
        }
        return text.toString();
    }

    static MethodNode method(ClassNode node, String name, String descriptor) {
        MethodNode found = null;
        for (MethodNode candidate : node.methods) {
            if (candidate.name.equals(name) && candidate.desc.equals(descriptor)) {
                expect(found == null, "duplicate " + node.name + "." + name);
                found = candidate;
            }
        }
        expect(found != null, "missing " + node.name + "." + name + descriptor);
        return found;
    }

    private void patchDispatcher() throws Exception {
        ClassNode node = readStock(DISPATCHER, DISPATCHER_SHA256);
        MethodNode update = method(node, "updateCurrentTrafficSign", "(L" + SIGN + ";I)V");
        expect((update.access & Opcodes.ACC_STATIC) == 0, "dispatcher instance method");
        InsnList hook = new InsnList();
        hook.add(new VarInsnNode(Opcodes.ALOAD, 1));
        hook.add(new VarInsnNode(Opcodes.ILOAD, 2));
        MethodInsnNode observe = call("observe", "(L" + SIGN + ";I)V");
        hook.add(observe);
        update.instructions.insert(hook);
        Guard.wrapCall(node.name, update, observe, Guard.popArgsReturnZero(observe.desc));
        writeFirmware(node, 1);
    }

    private void patchCurrentPosition() throws Exception {
        ClassNode node = readStock(POSITION, POSITION_SHA256);
        MethodNode init = method(node, "init",
                "(Lde/vw/mib/bap/mqbab2/common/api/stages/BAPStageInitializer;)"
                        + "Lde/vw/mib/bap/datatypes/BAPEntity;");
        int returns = 0;
        for (AbstractInsnNode instruction : init.instructions.toArray()) {
            if (instruction.getOpcode() == Opcodes.ARETURN) {
                insertStageHook(node.name, init, instruction, "register");
                returns++;
            }
        }
        expect(returns == 1, "CurrentPositionInfo.init return count " + returns);

        MethodNode uninitialize = method(node, "uninitialize", "()V");
        insertStageHook(node.name, uninitialize,
                uninitialize.instructions.getFirst(), "unregister");

        // Filter the final strings, including the stock empty-string branch.
        // When the trial is disabled or unavailable, identity fallback retains
        // that exact string and all native navigation-state decisions.
        MethodNode fill = method(node, "setCurrentPositionInfoStatusData", "(L" + STATUS + ";)V");
        int setters = 0;
        for (AbstractInsnNode instruction : fill.instructions.toArray()) {
            if (!(instruction instanceof MethodInsnNode)) {
                continue;
            }
            MethodInsnNode setter = (MethodInsnNode) instruction;
            if (!setter.owner.equals("de/vw/mib/bap/datatypes/BAPString")
                    || !setter.name.equals("setContent")
                    || !setter.desc.equals("(Ljava/lang/String;)V")) {
                continue;
            }
            expect(setter.getOpcode() == Opcodes.INVOKEVIRTUAL && !setter.itf,
                    "BAPString.setContent instruction");
            MethodInsnNode filter = call("streetText",
                    "(Ljava/lang/String;)Ljava/lang/String;");
            fill.instructions.insertBefore(setter, filter);
            // Guard restores the original stack. Leaving its String argument
            // untouched is the identity fallback, with BAPString below it.
            Guard.wrapCall(node.name, fill, filter, new InsnList());
            setters++;
        }
        expect(setters == 2, "CurrentPositionInfo street setter count " + setters);
        patchStatusResult(node, "sendCurrentPositionInfoStatus", STATUS, "currentStatusResult");
        writeFirmware(node, 5);
    }

    private static void insertStageHook(String owner, MethodNode method,
            AbstractInsnNode before, String name) throws AnalyzerException {
        InsnList hook = new InsnList();
        hook.add(new VarInsnNode(Opcodes.ALOAD, 0));
        MethodInsnNode invoke = call(name, "(L" + owner + ";)V");
        hook.add(invoke);
        method.instructions.insertBefore(before, hook);
        Guard.wrapCall(owner, method, invoke, Guard.popArgsReturnZero(invoke.desc));
    }

    private void patchTurnTo() throws Exception {
        ClassNode node = readStock(TURN_TO, TURN_TO_SHA256);
        MethodNode init = method(node, "init",
                "(Lde/vw/mib/bap/mqbab2/common/api/stages/BAPStageInitializer;)"
                        + "Lde/vw/mib/bap/datatypes/BAPEntity;");
        int returns = 0;
        for (AbstractInsnNode instruction : init.instructions.toArray()) {
            if (instruction.getOpcode() == Opcodes.ARETURN) {
                insertStageHook(node.name, init, instruction, "registerTurnTo");
                returns++;
            }
        }
        expect(returns == 1, "TurnToInfo.init return count " + returns);

        MethodNode uninitialize = method(node, "uninitialize", "()V");
        insertStageHook(node.name, uninitialize,
                uninitialize.instructions.getFirst(), "unregisterTurnTo");

        MethodNode fill = method(node, "setTurnToInfoStatusData", "(L" + TURN_TO_STATUS + ";)V");
        int streetGetters = 0;
        int signpostGetters = 0;
        int setters = 0;
        for (AbstractInsnNode instruction : fill.instructions.toArray()) {
            if (!(instruction instanceof MethodInsnNode)) {
                continue;
            }
            MethodInsnNode getter = (MethodInsnNode) instruction;
            if (isStringSetter(getter)) {
                setters++;
            }
            if (!getter.owner.equals(
                    "de/vw/mib/bap/mqbab2/common/api/navigation/datatypes/NavigationTurnToInfo")
                    || !getter.desc.equals("()Ljava/lang/String;")) {
                continue;
            }
            expect(getter.getOpcode() == Opcodes.INVOKEINTERFACE && getter.itf,
                    "NavigationTurnToInfo getter instruction");
            AbstractInsnNode next = nextReal(getter.getNext());
            expect(next instanceof MethodInsnNode && isStringSetter((MethodInsnNode) next),
                    "TurnToInfo getter followed by BAPString setter");
            if (getter.name.equals("getTurnToInfoStreet")) {
                MethodInsnNode filter = call("turnToText",
                        "(Ljava/lang/String;)Ljava/lang/String;");
                fill.instructions.insert(getter, filter);
                Guard.wrapCall(node.name, fill, filter, new InsnList());
                streetGetters++;
            } else {
                expect(getter.name.equals("getTurnToInfoSignPost"),
                        "unexpected NavigationTurnToInfo getter " + getter.name);
                signpostGetters++;
            }
        }
        expect(streetGetters == 1 && signpostGetters == 1 && setters == 2,
                "TurnToInfo exact street/signpost getter and setter counts");
        patchStatusResult(node, "sendTurnToInfoStatus", TURN_TO_STATUS, "turnToStatusResult");
        writeFirmware(node, 4);
    }

    private static void patchStatusResult(ClassNode node, String sendName,
            String status, String hookName) throws AnalyzerException {
        MethodNode send = method(node, sendName, "(L" + status + ";)V");
        int calls = 0;
        for (AbstractInsnNode instruction : send.instructions.toArray()) {
            if (!(instruction instanceof MethodInsnNode)) {
                continue;
            }
            MethodInsnNode stockCall = (MethodInsnNode) instruction;
            if (!stockCall.owner.equals("de/vw/mib/bap/functions/PropertyListener")
                    || !stockCall.name.equals("statusProperty")
                    || !stockCall.desc.equals("(Lde/vw/mib/bap/datatypes/BAPEntity;"
                            + "Lde/vw/mib/bap/functions/Property;)Z")) {
                continue;
            }
            expect(stockCall.getOpcode() == Opcodes.INVOKEINTERFACE && stockCall.itf,
                    "PropertyListener.statusProperty instruction");
            expect(nextReal(stockCall.getNext()).getOpcode() == Opcodes.POP,
                    sendName + " original result discarded");
            MethodInsnNode record = call(hookName, "(Z)Z");
            send.instructions.insert(stockCall, record);
            // The returned boolean and the original POP are preserved. Failed
            // diagnostic loading keeps the boolean already on the stack.
            Guard.wrapCall(node.name, send, record, new InsnList());
            calls++;
        }
        expect(calls == 1, sendName + " statusProperty call count " + calls);
    }

    private static boolean isStringSetter(MethodInsnNode instruction) {
        return instruction.getOpcode() == Opcodes.INVOKEVIRTUAL && !instruction.itf
                && instruction.owner.equals("de/vw/mib/bap/datatypes/BAPString")
                && instruction.name.equals("setContent")
                && instruction.desc.equals("(Ljava/lang/String;)V");
    }

    private static AbstractInsnNode nextReal(AbstractInsnNode instruction) {
        while (instruction != null && instruction.getOpcode() < 0) {
            instruction = instruction.getNext();
        }
        return instruction;
    }

    private static MethodInsnNode call(String name, String descriptor) {
        return new MethodInsnNode(Opcodes.INVOKESTATIC, HELPER, name, descriptor, false);
    }

    private void writeFirmware(ClassNode node, int expectedCalls) throws IOException {
        int calls = 0;
        for (MethodNode method : node.methods) {
            for (AbstractInsnNode instruction : method.instructions) {
                if (instruction instanceof MethodInsnNode
                        && ((MethodInsnNode) instruction).owner.equals(HELPER)) {
                    calls++;
                }
            }
        }
        expect(calls == expectedCalls, node.name + " helper call count " + calls);
        Guard.checkAllGuarded(node, HELPER);
        write(node);
    }

    private void copyHelpers() throws IOException {
        Path root = helpers.resolve("com/pmcp/sl");
        List<Path> files = new ArrayList<Path>();
        try (Stream<Path> paths = Files.walk(root)) {
            paths.filter(path -> path.toString().endsWith(".class"))
                    .sorted(Comparator.comparing(Path::toString)).forEach(files::add);
        }
        expect(!files.isEmpty(), "no helper classes");
        boolean mainFound = false;
        for (Path path : files) {
            ClassNode node = read(Files.readAllBytes(path));
            expect(node.name.equals(HELPER) || node.name.startsWith(HELPER + "$"),
                    "unexpected helper " + node.name);
            mainFound |= node.name.equals(HELPER);
            expect(node.version == 52, "helper must be compiled with --release 8");
            rejectModernInstructions(node);
            for (MethodNode method : node.methods) {
                method.localVariables = null;
            }
            node.version = FACTORY_VERSION;
            write(node);
        }
        expect(mainFound, "main helper missing");
    }

    static void rejectModernInstructions(ClassNode node) {
        for (MethodNode method : node.methods) {
            for (AbstractInsnNode instruction : method.instructions) {
                expect(!(instruction instanceof InvokeDynamicInsnNode),
                        node.name + "." + method.name + " invokedynamic");
                if (instruction instanceof LdcInsnNode) {
                    Object constant = ((LdcInsnNode) instruction).cst;
                    expect(!(constant instanceof Type),
                            node.name + "." + method.name + " class literal");
                }
                if (instruction instanceof MethodInsnNode) {
                    expect(!((MethodInsnNode) instruction).owner.equals("java/lang/StringBuilder"),
                            node.name + "." + method.name + " StringBuilder");
                }
            }
        }
    }

    private void write(ClassNode node) throws IOException {
        expect(node.version == FACTORY_VERSION, "output class version");
        ClassWriter writer = new ClassWriter(ClassWriter.COMPUTE_MAXS);
        node.accept(writer);
        Path path = output.resolve(node.name + ".class");
        Files.createDirectories(path.getParent());
        Files.write(path, writer.toByteArray());
        System.out.println("wrote " + node.name);
    }
}
