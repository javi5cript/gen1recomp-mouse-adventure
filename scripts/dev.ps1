#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Test', 'Build', 'Install', 'Run', 'Smoke')]
    [string]$Task = 'Test',
    [string]$GameDirectory,
    [ValidateSet('red', 'blue', 'yellow')]
    [string]$Game = 'yellow',
    [switch]$AllGames
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($AllGames -and $Task -ne 'Smoke') { throw '-AllGames is only supported with -Task Smoke.' }
$root = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $root '.dev.local.json'
if (!$GameDirectory) {
    if (Test-Path -LiteralPath $configPath) {
        $GameDirectory = (Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json).GameDirectory
    } else {
        $GameDirectory = $env:GEN1RECOMP_DIR
    }
}
if (!$GameDirectory) {
    throw 'Set -GameDirectory, GEN1RECOMP_DIR, or GameDirectory in .dev.local.json (see .dev.example.json).'
}
if (![IO.Path]::IsPathRooted($GameDirectory)) { $GameDirectory = Join-Path $root $GameDirectory }
$exe = Join-Path (Resolve-Path -LiteralPath $GameDirectory).Path 'gen1recomp.exe'
if (!(Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Game executable not found: $exe" }
$cache = Join-Path $root '.dev-cache'
$dist = Join-Path $root 'dist'
$files = @('manifest.json', 'main.lua', 'mouse_ui.lua', 'mouse_targets.lua',
    'README.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md')
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression

function Assert-GameClosed {
    if (Get-Process -Name gen1recomp -ErrorAction SilentlyContinue) {
        throw 'Close Gen1Recomp after saving before installing or running. No process was stopped.'
    }
}

function Get-EngineSource {
    $hash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
    $target = Join-Path $cache "engine\$hash"
    $ready = Join-Path $target '.ready'
    if (Test-Path -LiteralPath $ready) { return $target }

    # Windows releases prepend LOVE's executable to a ZIP. Its directory
    # offsets are relative to the ZIP, not the PE executable.
    $bytes = [IO.File]::ReadAllBytes($exe)
    $end = -1
    for ($i = $bytes.Length - 22; $i -ge [Math]::Max(0, $bytes.Length - 65557); $i--) {
        if ([BitConverter]::ToUInt32($bytes, $i) -eq 0x06054b50 -and
            $i + 22 + [BitConverter]::ToUInt16($bytes, $i + 20) -eq $bytes.Length) {
            $end = $i
            break
        }
    }
    if ($end -lt 0) { throw 'The executable does not contain a supported LOVE ZIP bundle.' }
    $count = [BitConverter]::ToUInt16($bytes, $end + 10)
    if ($count -eq 0 -or $count -eq 65535 -or
        [BitConverter]::ToUInt16($bytes, $end + 4) -ne 0 -or
        [BitConverter]::ToUInt16($bytes, $end + 6) -ne 0) {
        throw 'Empty, split, or ZIP64 engine bundles are not supported.'
    }
    $offset = $end - [long][BitConverter]::ToUInt32($bytes, $end + 12) -
        [long][BitConverter]::ToUInt32($bytes, $end + 16)
    if ($offset -lt 0 -or $offset -ge $end -or
        [BitConverter]::ToUInt32($bytes, [int]$offset) -ne 0x04034b50) {
        throw 'Cannot locate the embedded engine ZIP; the executable was not modified.'
    }
    $stream = [IO.MemoryStream]::new()
    try {
        $stream.Write($bytes, [int]$offset, $bytes.Length - [int]$offset)
        $stream.Position = 0
        $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read)
        try {
            foreach ($entry in $archive.Entries) {
                # Only engine Lua source, and no traversal or absolute paths.
                if ($entry.FullName -cmatch '^src/(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_-]+\.lua$') {
                    $path = Join-Path $target $entry.FullName.Replace('/', '\')
                    [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
                    [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $path, $true)
                }
            }
        } finally { $archive.Dispose() }
    } finally { $stream.Dispose() }
    if (!(Test-Path -LiteralPath (Join-Path $target 'src\core\Input.lua'))) {
        throw 'The embedded bundle did not contain the expected engine source.'
    }
    [IO.File]::WriteAllText($ready, $hash)
    return $target
}

function New-ModPackage {
    $manifest = Get-Content -LiteralPath (Join-Path $root 'manifest.json') -Raw | ConvertFrom-Json
    $path = Join-Path $dist "$($manifest.id)-$($manifest.version).zip"
    [IO.Directory]::CreateDirectory($dist) | Out-Null
    $temporary = Join-Path $dist ("package-" + [guid]::NewGuid().ToString('N') + '.zip')
    try {
        $archive = [IO.Compression.ZipFile]::Open($temporary, [IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($file in $files) {
                [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                    $archive, (Join-Path $root $file), $file) | Out-Null
            }
        } finally { $archive.Dispose() }
        $archive = [IO.Compression.ZipFile]::OpenRead($temporary)
        try {
            if (@(Compare-Object $files @($archive.Entries.FullName)).Count -ne 0) {
                throw 'Package contents did not match the runtime allowlist.'
            }
        } finally { $archive.Dispose() }
        Move-Item -LiteralPath $temporary -Destination $path -Force
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
    }
    Write-Host "Package: $path"
    return $path
}

function Install-Mod([string]$Package) {
    Assert-GameClosed
    if (!$env:APPDATA) { throw 'APPDATA is not set; cannot locate the Windows mod directory.' }
    $mods = Join-Path $env:APPDATA 'pokemon-love2d\mods'
    $destination = Join-Path $mods 'click_to_move'
    $stage = Join-Path $cache ("install-" + [guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($stage) | Out-Null
    try {
        [IO.Compression.ZipFile]::ExtractToDirectory($Package, $stage)
        $backup = Join-Path $cache ("backups\" + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
        if (Test-Path -LiteralPath $destination) {
            $installed = Join-Path $destination 'manifest.json'
            if (!(Test-Path -LiteralPath $installed) -or
                (Get-Content -LiteralPath $installed -Raw | ConvertFrom-Json).id -ne 'click_to_move') {
                throw "Refusing to overwrite an unidentified mod folder: $destination"
            }
            [IO.Directory]::CreateDirectory((Split-Path -Parent $backup)) | Out-Null
            Copy-Item -LiteralPath $destination -Destination $backup -Recurse
            Write-Host "Backup: $backup"
        }
        [IO.Directory]::CreateDirectory($destination) | Out-Null
        foreach ($file in $files) {
            $source = Join-Path $stage $file
            $installed = Join-Path $destination $file
            Copy-Item -LiteralPath $source -Destination $installed -Force
            if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $installed).Hash) {
                throw "Installation mismatch: $file. Restore the backup before launching."
            }
        }
        Write-Host "Installed: $destination"
    } finally {
        # The exact staging directory was generated by this invocation.
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse }
    }
}

if ($Task -in @('Install', 'Run')) { Assert-GameClosed }
if (!(Test-Path -LiteralPath (Join-Path $root 'node_modules\wasmoon')) -or
    !(Test-Path -LiteralPath (Join-Path $root 'node_modules\luaparse'))) {
    throw 'Development dependencies are missing. Run npm ci in the repository first.'
}
$previousSource = $env:GEN1RECOMP_SOURCE
try {
    $env:GEN1RECOMP_SOURCE = Get-EngineSource
    & node (Join-Path $root 'tests\run.js')
    if ($LASTEXITCODE -ne 0) { throw 'Regression tests failed; nothing was packaged or installed.' }
} finally { $env:GEN1RECOMP_SOURCE = $previousSource }
if ($Task -eq 'Test') { return }
$package = New-ModPackage
if ($Task -eq 'Build') { return }
if ($Task -eq 'Smoke') {
    $selection = if ($AllGames) { 'all' } else { $Game }
    & node (Join-Path $root 'tests\opening\run.js') $exe $selection
    if ($LASTEXITCODE -ne 0) { throw 'Opening smoke run failed; see its report under .dev-cache\smoke.' }
    return
}
Install-Mod $package
if ($Task -eq 'Run') {
    $process = Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe) `
        -ArgumentList "--game=$Game" -PassThru
    Start-Sleep -Seconds 3
    $process.Refresh()
    if ($process.HasExited) { throw "Gen1Recomp exited during startup (code $($process.ExitCode))." }
    Write-Host "Running $Game (PID $($process.Id)). Close normally after saving."
    Wait-Process -Id $process.Id
}
