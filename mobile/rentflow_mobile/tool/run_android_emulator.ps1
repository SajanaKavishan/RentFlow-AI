param(
    [ValidateRange(1, 65535)]
    [int]$ApiPort = 5277,
    [string]$DeviceId
)

$ErrorActionPreference = 'Stop'

if (-not (Test-NetConnection -ComputerName '127.0.0.1' -Port $ApiPort -InformationLevel Quiet)) {
    throw "The RentFlow API is not listening on localhost:$ApiPort. Start the backend first."
}

if (-not $DeviceId) {
    $emulators = @(& adb devices | ForEach-Object {
        $match = [regex]::Match($_, '^(emulator-\d+)\s+device$')
        if ($match.Success) { $match.Groups[1].Value }
    })
    if ($emulators.Count -ne 1) {
        throw 'Connect one Android emulator or pass its ID with -DeviceId.'
    }
    $DeviceId = $emulators[0]
}

& adb -s $DeviceId reverse "tcp:$ApiPort" "tcp:$ApiPort"
if ($LASTEXITCODE -ne 0) { throw 'ADB port forwarding failed.' }

$projectDirectory = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Push-Location -LiteralPath $projectDirectory
try {
    $flutterArgs = @('run', '-d', $DeviceId,
        "--dart-define=API_BASE_URL=http://127.0.0.1:$ApiPort")
    & flutter @flutterArgs
    if ($LASTEXITCODE -ne 0) { throw "Flutter exited with code $LASTEXITCODE." }
} finally {
    Pop-Location
}
