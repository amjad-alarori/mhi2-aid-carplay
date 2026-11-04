#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Build the optional native-map speed-limit road text package from exact MU1161 classes.
#   ASM_DIR=/path/to/asm-9.7 build.sh <converted lsd.jar> <fresh work dir>
# Requires JDK 17+ and Python 3. JAVA_HOME may select the JDK.
set -euo pipefail

STOCK_JAR=${1:?converted lsd jar}; W=${2:?fresh work dir}
H=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$H/.." && pwd)
: "${ASM_DIR:?set ASM_DIR to a directory with ASM 9.7 jars}"
JAVA=java; JAVAC=javac
if [ -n "${JAVA_HOME:-}" ]; then
    JAVA="$JAVA_HOME/bin/java"; JAVAC="$JAVA_HOME/bin/javac"
fi

fail() { echo "FAIL: $*" >&2; exit 1; }
sha() { python3 -I -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"; }
[ "$(sha "$STOCK_JAR")" = 573b603a0b79b6c150d6c4363d5db2f9a1b644b21f81ab4a2329d5cdda0f1576 ] || fail "converted jar is not the pinned MU1161 image"
[ "$(sha "$ASM_DIR/asm-9.7.jar")" = adf46d5e34940bdf148ecdd26a9ee8eea94496a72034ff7141066b3eea5c4e9d ] || fail "asm-9.7.jar hash"
[ "$(sha "$ASM_DIR/asm-tree-9.7.jar")" = 62f4b3bc436045c1acb5c3ba2d8ec556ec3369093d7f5d06c747eb04b56d52b1 ] || fail "asm-tree-9.7.jar hash"
[ "$(sha "$ASM_DIR/asm-analysis-9.7.jar")" = 7bc6bcbc21379948a0c8c467fb0f864206e5b818f6bc0b546872f5c9f941556f ] || fail "asm-analysis-9.7.jar hash"
[ ! -e "$W" ] || fail "use a fresh output directory"
mkdir -p "$W"/{stock,helpers,tools,patched,tests}
W=$(cd "$W" && pwd)
STOCK_JAR=$(cd "$(dirname "$STOCK_JAR")" && pwd)/$(basename "$STOCK_JAR")
ASM_DIR=$(cd "$ASM_DIR" && pwd)

# Git Bash can also drive a Windows JDK. Its classpath separator and path syntax differ.
CP_SEP=:
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) CP_SEP=';' ;; esac
java_path() {
    if [ "$CP_SEP" = ';' ]; then cygpath -w "$1"; else printf '%s\n' "$1"; fi
}
CP="$(java_path "$ASM_DIR/asm-9.7.jar")$CP_SEP$(java_path "$ASM_DIR/asm-tree-9.7.jar")$CP_SEP$(java_path "$ASM_DIR/asm-analysis-9.7.jar")"
STOCK_CP=$(java_path "$STOCK_JAR")
TOOLS_CP="$(java_path "$W/tools")$CP_SEP$CP"

python3 -I - "$STOCK_JAR" "$W/stock" <<'PY'
from pathlib import Path
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    for name in (
        'de/esolutions/fw/dsi/trafficregulation/DSITrafficRegulationDispatcher.class',
        'de/vw/mib/bap/mqbab2/navsd/functions/CurrentPositionInfo.class',
        'de/vw/mib/bap/mqbab2/navsd/functions/TurnToInfo.class',
    ):
        target = Path(sys.argv[2]) / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(z.read(name))
PY

"$JAVAC" --release 8 -g:none -Xlint:-options -cp "$STOCK_CP" -d "$W/helpers" "$H"/src/com/pmcp/sl/*.java
"$JAVAC" -g:none -cp "$CP" -d "$W/tools" "$REPO/buildtools/Guard.java" "$REPO/buildtools/RefCheck.java" \
    "$REPO/navactiveignore/patcher/Verify.java" "$H"/patcher/*.java
"$JAVA" -cp "$TOOLS_CP" PatchNativeSpeedLimit "$W/stock" "$W/helpers" "$W/patched"
"$JAVA" -Xverify:all -cp "$TOOLS_CP" TestNativeSpeedLimitPatch "$W/stock" "$W/patched"

# Identical to build.ps1, including manifest, sorted entries, timestamp and class version checks.
python3 -I - "$W/patched" "$W/pmcp-sl.jar" <<'PY'
from pathlib import Path
import hashlib, struct, sys, zipfile
root, target = Path(sys.argv[1]), Path(sys.argv[2])
classes = sorted(root.rglob('*.class'))
if not classes:
    raise ValueError('No generated classes')
with zipfile.ZipFile(target, 'x') as z:
    entries = [('META-INF/MANIFEST.MF', b'Manifest-Version: 1.0\nCreated-By: MU1161 native speed-limit road text\n\n')]
    for path in classes:
        data = path.read_bytes()
        if data[:4] != b'\xca\xfe\xba\xbe' or struct.unpack('>H', data[6:8])[0] != 46:
            raise ValueError('Generated class is not J9 version 46 ' + str(path))
        entries.append((path.relative_to(root).as_posix(), data))
    for name, data in entries:
        item = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
        item.compress_type = zipfile.ZIP_DEFLATED
        item.create_system = 3
        item.external_attr = 0o100644 << 16
        z.writestr(item, data)
print('NATIVE_SPEED_LIMIT_JAR', target.stat().st_size, hashlib.sha256(target.read_bytes()).hexdigest())
PY

"$JAVA" -cp "$TOOLS_CP" RefCheck "$STOCK_JAR" "$W/pmcp-sl.jar"
classes=()
while IFS= read -r path; do classes+=("$path"); done < <(find "$W/patched" -name '*.class' | LC_ALL=C sort)
"$JAVA" -cp "$TOOLS_CP" Verify "$W/patched" "$STOCK_JAR" "${classes[@]}"
TEST_CP="$(java_path "$W/pmcp-sl.jar")$CP_SEP$STOCK_CP"
"$JAVAC" --release 8 -g:none -Xlint:-options -cp "$TEST_CP" -d "$W/tests" "$H"/test/com/pmcp/sl/*.java
"$JAVA" -Xverify:all -cp "$(java_path "$W/tests")$CP_SEP$TEST_CP" com.pmcp.sl.TestNativeSpeedLimit

python3 -I - "$STOCK_JAR" "$W/pmcp-sl.jar" "$W/patched" "$W/BUILD-VALIDATION.json" <<'PY'
from pathlib import Path
import hashlib, json, sys
stock, jar, classes, target = map(Path, sys.argv[1:])
report = {
    'firmware': 'MHI2_ER_VWG13_P4512_1 MU1161',
    'source_stock_jar_sha256': hashlib.sha256(stock.read_bytes()).hexdigest(),
    'helper_jar_sha256': hashlib.sha256(jar.read_bytes()).hexdigest(),
    'helper_jar_size': jar.stat().st_size,
    'generated_classes': len(list(classes.rglob('*.class'))),
    'j9_api_check': 'pass',
    'bytecode_verification': 'pass',
    'hook_scope_and_fallback_tests': 'pass',
    'host_tests': 'pass',
    'qnx_execution_tested': False,
    'aid_text_rendering_tested': False,
}
target.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
PY
echo "NATIVE_SPEED_LIMIT_BUILD_OK $W/pmcp-sl.jar"
