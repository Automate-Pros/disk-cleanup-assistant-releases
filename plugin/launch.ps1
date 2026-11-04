# Runs the plugin's dca.exe, the build whose SHA-256 release.json pins.
# When bin\dca.exe is missing or is not that build, it is fetched from the
# GitHub release first; a download that does not match the pin is deleted
# and never run. `just plugin-dev` puts a local build in bin\ with a .dev
# marker, which is used as it is.
#
# Several Claude sessions may start the plugin at once, so each launch
# downloads to a file of its own and only a verified copy is moved into
# place; a launch that finds the pinned exe already there (or in use by
# another session) runs that one.
#
# Starting the pinned exe uses .NET only, no cmdlets: in the environment
# Claude Code starts plugins in, loading the modules of Join-Path,
# Get-Content and ConvertFrom-Json took seconds, and Claude Code takes a
# server that answers late for one that speaks an older protocol.
param([Parameter(ValueFromRemainingArguments = $true)] [string[]] $Rest)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$bin = [IO.Path]::Combine($root, 'bin')
$exe = [IO.Path]::Combine($bin, 'dca.exe')

# release.json is the plugin's own flat file of three strings.
$pinText = [IO.File]::ReadAllText([IO.Path]::Combine($root, 'release.json'))
function Get-PinField([string] $name) {
    $m = [regex]::Match($pinText, '"' + $name + '"\s*:\s*"([^"]*)"')
    if (-not $m.Success) { Fail "release.json has no $name" }
    $m.Groups[1].Value
}

# .NET directly rather than Get-FileHash, which lives in a script module
# that Windows PowerShell cannot load when started from PowerShell 7.
function Get-Sha256([string] $path) {
    # Shares Delete because a rename holds its file with delete access, and
    # another launch may be moving the exe into place while this one reads.
    $stream = [IO.File]::Open($path, 'Open', 'Read', 'Read, Delete')
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '').ToLowerInvariant()
    } finally { $stream.Dispose() }
}

function Test-Running([int] $id) {
    try { $null = [Diagnostics.Process]::GetProcessById($id); $true } catch { $false }
}

function Fail([string] $message) {
    [Console]::Error.WriteLine("Disk Cleanup Assistant: $message")
    exit 1
}

function Get-Release([string] $to) {
    $tag = "v$($pin.version)"
    if ($env:DCA_RELEASE_DIR) {
        # Tests fetch from a folder instead of GitHub.
        Copy-Item -LiteralPath (Join-Path $env:DCA_RELEASE_DIR 'dca.exe') -Destination $to
        return
    }
    $url = "https://github.com/$($pin.repo)/releases/download/$tag/dca.exe"
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $to
        return
    } catch {
        # A private repository needs the signed-in GitHub CLI.
    }
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        # gh names the file dca.exe, so it gets a folder of its own rather
        # than bin\, where another session may be running dca.exe.
        $dir = "$to.gh"
        & gh release download $tag --repo $pin.repo --pattern dca.exe --dir $dir --clobber 2>$null
        if ($LASTEXITCODE -eq 0) {
            Move-Item -Force -LiteralPath (Join-Path $dir 'dca.exe') -Destination $to
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -LiteralPath $dir
            return
        }
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -LiteralPath $dir
    }
    Fail "could not download dca.exe $tag from github.com/$($pin.repo). Check the internet connection; for a private repository, sign in with ``gh auth login``."
}

$pin = @{ version = (Get-PinField 'version'); repo = (Get-PinField 'repo'); sha256 = (Get-PinField 'sha256') }

# File.Replace holds the exe to itself for a moment, so a read that fails is
# tried again before the exe counts as not the pinned one.
function Test-Pinned {
    for ($try = 0; $try -lt 20; $try++) {
        if (-not [IO.File]::Exists($exe)) { return $false }
        try { return (Get-Sha256 $exe) -eq $pin.sha256 } catch { [Threading.Thread]::Sleep(50) }
    }
    $false
}

# Not Move-Item -Force: it deletes the destination before it renames, so a
# launch that lost the race took away the exe the winner was about to start.
# File.Move refuses when the exe is there, in one step; a launch that finds
# the pinned exe leaves it, and only an exe that is not the pinned one is
# replaced, also in one step.
function Set-PinnedExe([string] $from) {
    try {
        [IO.File]::Move($from, $exe)
        return
    } catch { }
    if (-not (Test-Pinned)) { [IO.File]::Replace($from, $exe, [NullString]::Value) }
}

$dev = [IO.File]::Exists([IO.Path]::Combine($bin, '.dev'))
if (-not ($dev -or (Test-Pinned))) {
    New-Item -ItemType Directory -Force $bin | Out-Null
    # Downloads left by launches that were stopped part way: each is named
    # for its launch's process, and one whose process still runs is in use.
    Get-ChildItem -LiteralPath $bin -Filter 'dca.exe.*.download*' |
        Where-Object { $_.Name -match '^dca\.exe\.(\d+)\.download' -and -not (Test-Running $Matches[1]) } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    $download = Join-Path $bin "dca.exe.$PID.download"
    Get-Release $download
    $got = Get-Sha256 $download
    if ($got -ne $pin.sha256) {
        Remove-Item -Force -LiteralPath $download
        Fail "the downloaded dca.exe does not match the plugin's pin (got $got, expected $($pin.sha256)); it was deleted, not run."
    }
    $why = ''
    try { Set-PinnedExe $download } catch { $why = ": $_" }
    Remove-Item -Force -ErrorAction SilentlyContinue -LiteralPath $download
    if (-not (Test-Pinned)) { Fail "could not put the downloaded dca.exe in $bin$why" }
}

# When a start fails, Windows PowerShell may retry it through ShellExecute.
# That runs dca.exe detached, with no pipes and no exit code, and `exit` with
# nothing to pass on would report success.
$global:LASTEXITCODE = $null
& $exe @Rest
if ($null -eq $LASTEXITCODE) { Fail "dca.exe started detached from this launcher, so it cannot be used." }
exit $LASTEXITCODE
