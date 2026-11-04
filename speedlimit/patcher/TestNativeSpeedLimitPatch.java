/* SPDX-License-Identifier: GPL-3.0-or-later. Host regression test, never installed. */
import java.lang.reflect.Method;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;
import org.objectweb.asm.ClassWriter;
import org.objectweb.asm.Opcodes;
import org.objectweb.asm.tree.AbstractInsnNode;
import org.objectweb.asm.tree.ClassNode;
import org.objectweb.asm.tree.InsnList;
import org.objectweb.asm.tree.InsnNode;
import org.objectweb.asm.tree.LdcInsnNode;
import org.objectweb.asm.tree.MethodInsnNode;
import org.objectweb.asm.tree.MethodNode;
import org.objectweb.asm.tree.VarInsnNode;

/** Checks the exact firmware scope and executes Guard's String identity fallback. */
public final class TestNativeSpeedLimitPatch {
    private static int checks;

    public static void main(String[] args) throws Exception {
        check(args.length == 2, "usage: TestNativeSpeedLimitPatch <stock> <patched>");
        Path stock = Paths.get(args[0]);
        Path patched = Paths.get(args[1]);
        checkScope(stock, patched, PatchNativeSpeedLimit.DISPATCHER,
                new String[] {"updateCurrentTrafficSign(Lorg/dsi/ifc/trafficregulation/TrafficSignInformation;I)V"}, 1);
        checkScope(stock, patched, PatchNativeSpeedLimit.POSITION, new String[] {
                "init(Lde/vw/mib/bap/mqbab2/common/api/stages/BAPStageInitializer;)Lde/vw/mib/bap/datatypes/BAPEntity;",
                "uninitialize()V",
                "setCurrentPositionInfoStatusData(Lde/vw/mib/bap/mqbab2/generated/navsd/serializer/CurrentPositionInfo_Status;)V",
                "sendCurrentPositionInfoStatus(Lde/vw/mib/bap/mqbab2/generated/navsd/serializer/CurrentPositionInfo_Status;)V"
        }, 5);
        checkStatusResult(patched, PatchNativeSpeedLimit.POSITION,
                "sendCurrentPositionInfoStatus", PatchNativeSpeedLimit.STATUS, "currentStatusResult");
        check(!Files.exists(patched.resolve("de/vw/mib/bap/mqbab2/navsd/functions/TurnToInfo.class")),
                "TurnToInfo is left to the rg package");
        checkWrongHash(stock);
        checkRuntimeFallbacks();
        System.out.println("NATIVE_SPEED_LIMIT_PATCH_TEST_OK checks=" + checks);
    }

    private static void check(boolean value, String message) {
        checks++;
        if (!value) {
            throw new AssertionError(message);
        }
    }

    private static ClassNode read(Path root, String name) throws Exception {
        return PatchNativeSpeedLimit.read(Files.readAllBytes(root.resolve(name + ".class")));
    }

    private static void checkScope(Path stock, Path patched, String owner,
            String[] changedMethods, int expectedCalls) throws Exception {
        ClassNode original = read(stock, owner);
        ClassNode result = read(patched, owner);
        check(result.version == 46, owner + " factory class version");
        check(original.methods.size() == result.methods.size(), owner + " method count");
        check(original.fields.size() == result.fields.size(), owner + " field count");
        Set<String> expected = new HashSet<String>(Arrays.asList(changedMethods));
        int calls = 0;
        for (MethodNode method : original.methods) {
            String key = method.name + method.desc;
            MethodNode modified = PatchNativeSpeedLimit.method(result, method.name, method.desc);
            boolean same = Arrays.equals(methodBytes(owner, method), methodBytes(owner, modified));
            check(same != expected.contains(key), owner + "." + key + " change scope");
            for (AbstractInsnNode instruction : modified.instructions) {
                if (instruction instanceof MethodInsnNode) {
                    MethodInsnNode call = (MethodInsnNode) instruction;
                    if (call.owner.equals(PatchNativeSpeedLimit.HELPER)) {
                        calls++;
                        check(Guard.guarded(modified, call), owner + "." + key + " call guarded");
                    }
                }
            }
        }
        check(calls == expectedCalls, owner + " exact helper call count");
        Guard.checkAllGuarded(result, PatchNativeSpeedLimit.HELPER);
    }

    private static void checkStatusResult(Path patched, String owner,
            String methodName, String status, String hook) throws Exception {
        MethodNode send = PatchNativeSpeedLimit.method(read(patched, owner),
                methodName, "(L" + status + ";)V");
        int stockCalls = 0;
        int resultHooks = 0;
        for (AbstractInsnNode instruction : send.instructions) {
            if (instruction instanceof MethodInsnNode) {
                MethodInsnNode call = (MethodInsnNode) instruction;
                if (call.owner.equals("de/vw/mib/bap/functions/PropertyListener")
                        && call.name.equals("statusProperty")) {
                    stockCalls++;
                }
                if (call.owner.equals(PatchNativeSpeedLimit.HELPER)) {
                    check(call.name.equals(hook) && call.desc.equals("(Z)Z"),
                            methodName + " only records the original boolean result");
                    resultHooks++;
                }
            }
        }
        check(stockCalls == 1 && resultHooks == 1, methodName + " one stock call and one result hook");
    }

    /** A fresh constant pool makes method serialization independent of the enclosing class pool. */
    private static byte[] methodBytes(String owner, MethodNode method) {
        ClassWriter writer = new ClassWriter(ClassWriter.COMPUTE_MAXS);
        writer.visit(46, Opcodes.ACC_PUBLIC, owner, null, "java/lang/Object", null);
        method.accept(writer);
        writer.visitEnd();
        return writer.toByteArray();
    }

    private static void checkWrongHash(Path stock) throws Exception {
        Path root = Files.createTempDirectory("pmcp-speedlimit-patch-test-");
        Path source = root.resolve("stock").resolve(PatchNativeSpeedLimit.DISPATCHER + ".class");
        Path output = root.resolve("output");
        try {
            byte[] bytes = Files.readAllBytes(stock.resolve(PatchNativeSpeedLimit.DISPATCHER + ".class"));
            bytes[bytes.length - 1] ^= 1;
            Files.createDirectories(source.getParent());
            Files.write(source, bytes);
            boolean rejected = false;
            try {
                PatchNativeSpeedLimit.main(new String[] {
                        root.resolve("stock").toString(), root.resolve("unused-helpers").toString(), output.toString()
                });
            } catch (IllegalStateException mismatch) {
                rejected = mismatch.getMessage().contains("stock hash");
            }
            check(rejected, "changed source hash rejected");
            check(!Files.exists(output), "wrong source creates no output");
        } finally {
            Files.deleteIfExists(source);
            Path directory = source.getParent();
            while (directory != null && directory.startsWith(root)) {
                Files.deleteIfExists(directory);
                directory = directory.getParent();
            }
        }
    }

    private static void checkRuntimeFallbacks() throws Exception {
        String owner = "SpeedLimitGuardFixture";
        ClassNode fixture = new ClassNode();
        fixture.version = 46;
        fixture.access = Opcodes.ACC_PUBLIC;
        fixture.name = owner;
        fixture.superName = "java/lang/Object";
        addStringMethod(fixture, "missing", "pmcp/test/MissingSpeedLimitFilter", true);
        addStringMethod(fixture, "throwing", "TestNativeSpeedLimitPatch$FailingFilter", true);
        addStringMethod(fixture, "identity", "pmcp/test/MissingSpeedLimitFilter", false);
        addBooleanMethod(fixture, "missingBoolean", "pmcp/test/MissingSpeedLimitFilter");
        addBooleanMethod(fixture, "throwingBoolean", "TestNativeSpeedLimitPatch$FailingFilter");
        addVoidMethod(fixture);
        ClassWriter writer = new ClassWriter(ClassWriter.COMPUTE_MAXS);
        fixture.accept(writer);
        Class<?> loaded = new FixtureLoader().define(writer.toByteArray());
        String stock = new String("Factory street \u00e9");
        for (String name : new String[] {"missing", "throwing"}) {
            Method method = loaded.getMethod(name, String.class);
            check(("prefix:" + stock).equals(method.invoke(null, stock)),
                    name + " retains value below String argument");
        }
        Method identity = loaded.getMethod("identity", String.class);
        check(identity.invoke(null, stock) == stock, "missing helper retains original String identity");
        check(identity.invoke(null, new Object[] {null}) == null, "missing helper retains null");
        check(Integer.valueOf(7).equals(loaded.getMethod("observe").invoke(null)),
                "missing void helper permits stock continuation");
        for (String name : new String[] {"missingBoolean", "throwingBoolean"}) {
            Method method = loaded.getMethod(name, Boolean.TYPE);
            check(Integer.valueOf(7).equals(method.invoke(null, Boolean.FALSE)),
                    name + " retains false and lower stack value");
            check(Integer.valueOf(8).equals(method.invoke(null, Boolean.TRUE)),
                    name + " retains true and lower stack value");
        }
    }

    private static void addStringMethod(ClassNode owner, String name,
            String helper, boolean belowStack) throws Exception {
        MethodNode method = new MethodNode(Opcodes.ACC_PUBLIC | Opcodes.ACC_STATIC,
                name, "(Ljava/lang/String;)Ljava/lang/String;", null, null);
        method.maxLocals = 1;
        method.maxStack = 2;
        if (belowStack) {
            method.instructions.add(new LdcInsnNode("prefix:"));
        }
        method.instructions.add(new VarInsnNode(Opcodes.ALOAD, 0));
        MethodInsnNode filter = new MethodInsnNode(Opcodes.INVOKESTATIC,
                helper, "streetText", "(Ljava/lang/String;)Ljava/lang/String;", false);
        method.instructions.add(filter);
        if (belowStack) {
            method.instructions.add(new MethodInsnNode(Opcodes.INVOKEVIRTUAL,
                    "java/lang/String", "concat", "(Ljava/lang/String;)Ljava/lang/String;", false));
        }
        method.instructions.add(new InsnNode(Opcodes.ARETURN));
        Guard.wrapCall(owner.name, method, filter, new InsnList());
        owner.methods.add(method);
    }

    private static void addVoidMethod(ClassNode owner) throws Exception {
        MethodNode method = new MethodNode(Opcodes.ACC_PUBLIC | Opcodes.ACC_STATIC,
                "observe", "()I", null, null);
        method.maxStack = 1;
        MethodInsnNode observe = new MethodInsnNode(Opcodes.INVOKESTATIC,
                "pmcp/test/MissingSpeedLimitFilter", "observe", "()V", false);
        method.instructions.add(observe);
        method.instructions.add(new LdcInsnNode(7));
        method.instructions.add(new InsnNode(Opcodes.IRETURN));
        Guard.wrapCall(owner.name, method, observe, Guard.popArgsReturnZero(observe.desc));
        owner.methods.add(method);
    }

    private static void addBooleanMethod(ClassNode owner, String name, String helper) throws Exception {
        MethodNode method = new MethodNode(Opcodes.ACC_PUBLIC | Opcodes.ACC_STATIC,
                name, "(Z)I", null, null);
        method.maxLocals = 1;
        method.maxStack = 2;
        method.instructions.add(new LdcInsnNode(7));
        method.instructions.add(new VarInsnNode(Opcodes.ILOAD, 0));
        MethodInsnNode result = new MethodInsnNode(Opcodes.INVOKESTATIC,
                helper, "statusResult", "(Z)Z", false);
        method.instructions.add(result);
        method.instructions.add(new InsnNode(Opcodes.IADD));
        method.instructions.add(new InsnNode(Opcodes.IRETURN));
        Guard.wrapCall(owner.name, method, result, new InsnList());
        owner.methods.add(method);
    }

    public static final class FailingFilter {
        public static String streetText(String stock) {
            throw new AssertionError("deliberate helper failure");
        }

        public static boolean statusResult(boolean stock) {
            throw new AssertionError("deliberate result diagnostic failure");
        }
    }

    private static final class FixtureLoader extends ClassLoader {
        Class<?> define(byte[] bytes) {
            return defineClass(null, bytes, 0, bytes.length);
        }
    }
}
