[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$StockJar,
    [Parameter(Mandatory = $true)][string]$Jdk,
    [Parameter(Mandatory = $true)][string]$AsmDirectory,
    [Parameter(Mandatory = $true)][string]$BuildRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$module = $PSScriptRoot
$repo = Split-Path -Parent $module
$StockJar = [IO.Path]::GetFullPath($StockJar)
$BuildRoot = [IO.Path]::GetFullPath($BuildRoot)
$Jdk = [IO.Path]::GetFullPath($Jdk)
$AsmDirectory = [IO.Path]::GetFullPath($AsmDirectory)

if ((Get-FileHash -LiteralPath $StockJar -Algorithm SHA256).Hash.ToLowerInvariant() -ne
    '573b603a0b79b6c150d6c4363d5db2f9a1b644b21f81ab4a2329d5cdda0f1576') {
    throw 'The converted firmware is not the pinned MU1161 image'
}
if (Test-Path -LiteralPath $BuildRoot) {
    throw 'Use a fresh output directory'
}
$java = Join-Path $Jdk 'bin/java.exe'
$javac = Join-Path $Jdk 'bin/javac.exe'
foreach ($tool in @($java, $javac)) {
    if (!(Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Missing tool $tool" }
}
$asmPins = [ordered]@{
    'asm-9.7.jar' = 'adf46d5e34940bdf148ecdd26a9ee8eea94496a72034ff7141066b3eea5c4e9d'
    'asm-tree-9.7.jar' = '62f4b3bc436045c1acb5c3ba2d8ec556ec3369093d7f5d06c747eb04b56d52b1'
    'asm-analysis-9.7.jar' = '7bc6bcbc21379948a0c8c467fb0f864206e5b818f6bc0b546872f5c9f941556f'
}
$asmPaths = @()
foreach ($name in $asmPins.Keys) {
    $path = Join-Path $AsmDirectory $name
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $asmPins[$name]) {
        throw "ASM dependency differs from its pinned version $name"
    }
    $asmPaths += $path
}
$asmClasspath = $asmPaths -join [IO.Path]::PathSeparator
$stockClasses = Join-Path $BuildRoot 'stock'
$helpers = Join-Path $BuildRoot 'helpers'
$tools = Join-Path $BuildRoot 'tools'
$patched = Join-Path $BuildRoot 'patched'
$tests = Join-Path $BuildRoot 'tests'
New-Item -ItemType Directory -Path $stockClasses, $helpers, $tools, $patched, $tests | Out-Null

$extract = @'
from pathlib import Path
import sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    for name in (
        'de/esolutions/fw/dsi/trafficregulation/DSITrafficRegulationDispatcher.class',
        'de/vw/mib/bap/mqbab2/navsd/functions/CurrentPositionInfo.class',
    ):
        target = Path(sys.argv[2]) / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(z.read(name))
'@
& python -I -c $extract $StockJar $stockClasses
if ($LASTEXITCODE) { throw 'Original class extraction failed' }

$helperSources = @(Get-ChildItem -LiteralPath (Join-Path $module 'src') -Filter '*.java' -Recurse |
    Sort-Object FullName | Select-Object -ExpandProperty FullName)
& $javac --release 8 -g:none -Xlint:-options -cp $StockJar -d $helpers @helperSources
if ($LASTEXITCODE) { throw 'Exact firmware API compilation failed' }
$toolSources = @(
    (Join-Path $repo 'buildtools/Guard.java'),
    (Join-Path $repo 'buildtools/RefCheck.java'),
    (Join-Path $repo 'navactiveignore/patcher/Verify.java')
)
$toolSources += @(Get-ChildItem -LiteralPath (Join-Path $module 'patcher') -Filter '*.java' |
    Select-Object -ExpandProperty FullName)
& $javac -g:none -cp $asmClasspath -d $tools @toolSources
if ($LASTEXITCODE) { throw 'Build tool compilation failed' }
$toolClasspath = $tools + [IO.Path]::PathSeparator + $asmClasspath
& $java -cp $toolClasspath PatchNativeSpeedLimit $stockClasses $helpers $patched
if ($LASTEXITCODE) { throw 'Exact firmware patch assertions failed' }
& $java -Xverify:all -cp $toolClasspath TestNativeSpeedLimitPatch $stockClasses $patched
if ($LASTEXITCODE) { throw 'Hook scope or failure-containment tests failed' }

$jar = Join-Path $BuildRoot 'pmcp-sl.jar'
$pack = @'
from pathlib import Path
import hashlib, json, struct, sys, zipfile
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
'@
& python -I -c $pack $patched $jar
if ($LASTEXITCODE) { throw 'Deterministic JAR packaging failed' }
& $java -cp $toolClasspath RefCheck $StockJar $jar
if ($LASTEXITCODE) { throw 'J9 API compatibility check failed' }
$generatedClasses = @(Get-ChildItem -LiteralPath $patched -Recurse -Filter '*.class' |
    Select-Object -ExpandProperty FullName)
& $java -cp $toolClasspath Verify $patched $StockJar @generatedClasses
if ($LASTEXITCODE) { throw 'Generated bytecode verification failed' }

$testSources = @(Get-ChildItem -LiteralPath (Join-Path $module 'test') -Filter '*.java' -Recurse |
    Select-Object -ExpandProperty FullName)
$testClasspath = $jar + [IO.Path]::PathSeparator + $StockJar
& $javac --release 8 -g:none -Xlint:-options -cp $testClasspath -d $tests @testSources
if ($LASTEXITCODE) { throw 'Host test compilation failed' }
& $java -Xverify:all -cp ($tests + [IO.Path]::PathSeparator + $testClasspath) com.pmcp.sl.TestNativeSpeedLimit
if ($LASTEXITCODE) { throw 'Native speed-limit host tests failed' }

$report = [ordered]@{
    firmware = 'MHI2_ER_VWG13_P4512_1 MU1161'
    source_stock_jar_sha256 = (Get-FileHash -LiteralPath $StockJar -Algorithm SHA256).Hash.ToLowerInvariant()
    helper_jar_sha256 = (Get-FileHash -LiteralPath $jar -Algorithm SHA256).Hash.ToLowerInvariant()
    helper_jar_size = (Get-Item -LiteralPath $jar).Length
    generated_classes = $generatedClasses.Count
    j9_api_check = 'pass'
    bytecode_verification = 'pass'
    hook_scope_and_fallback_tests = 'pass'
    host_tests = 'pass'
    qnx_execution_tested = $false
    aid_text_rendering_tested = $false
}
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $BuildRoot 'BUILD-VALIDATION.json') -Encoding UTF8
Write-Output ('NATIVE_SPEED_LIMIT_BUILD_OK ' + $jar)
