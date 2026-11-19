param(
  [string]$Configuration = "Release",
  [string]$OutDir = "Klaro-Portable"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$build = Join-Path $root "build\windows\x64\runner\$Configuration"
if (-not (Test-Path (Join-Path $build "klaro.exe"))) {
  throw "Build the app first: flutter build windows --$($Configuration.ToLower())"
}
$rustDll = Join-Path $root "native\klaro_engine\target\release\klaro_engine.dll"
if (-not (Test-Path $rustDll)) {
  throw "Build the Rust native engine first: cargo build --release in native\klaro_engine"
}
$out = Join-Path $root $OutDir

# A repackage never touches the user's data: userdata, backups, config and
# models are moved aside first and put back once the new files are in place.
$preserved = @{}
if (Test-Path $out) {
  foreach ($d in @("userdata", "backups", "config", "models")) {
    $existing = Join-Path $out $d
    if (Test-Path $existing) {
      $stash = Join-Path ([System.IO.Path]::GetTempPath()) ("klaro-" + $d + "-" + [guid]::NewGuid().ToString("N"))
      Move-Item $existing $stash
      $preserved[$d] = $stash
    }
  }
  Remove-Item $out -Recurse -Force
}
New-Item -ItemType Directory -Path $out | Out-Null
Copy-Item (Join-Path $build "*") $out -Recurse
Copy-Item $rustDll $out -Force
foreach ($d in @("userdata", "config", "models", "cache", "logs", "backups", "docs")) {
  New-Item -ItemType Directory -Force -Path (Join-Path $out $d) | Out-Null
}
foreach ($d in $preserved.Keys) {
  Remove-Item (Join-Path $out $d) -Recurse -Force
  Move-Item $preserved[$d] (Join-Path $out $d)
}
Copy-Item (Join-Path $root "README.md") $out
Copy-Item (Join-Path $root "LICENSE") $out
Copy-Item (Join-Path $root "NOTICE.md") $out
Copy-Item (Join-Path $root "docs\*") (Join-Path $out "docs") -Recurse
New-Item -ItemType Directory -Force -Path (Join-Path $out "assets\fonts") | Out-Null
Copy-Item (Join-Path $root "assets\fonts\OFL-*.txt") (Join-Path $out "assets\fonts")

$launcher = @"
@echo off
start "" "%~dp0Klaro-Portable\klaro.exe"
"@
Set-Content -Path (Join-Path $root "Start-Klaro.bat") -Value $launcher -Encoding ASCII

$zipPath = Join-Path $root "Klaro-Windows-Portable.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
$zipStash = @{}
foreach ($d in @("userdata", "backups", "config", "logs", "cache")) {
  $p = Join-Path $out $d
  $items = Get-ChildItem $p -Force -ErrorAction SilentlyContinue
  if ($items) {
    $s = Join-Path ([System.IO.Path]::GetTempPath()) ("klaro-zip-" + $d + "-" + [guid]::NewGuid().ToString("N"))
    Move-Item $p $s
    New-Item -ItemType Directory -Force -Path $p | Out-Null
    $zipStash[$d] = $s
  }
}
Compress-Archive -Path "$out\*" -DestinationPath $zipPath -Force
foreach ($d in $zipStash.Keys) {
  Remove-Item (Join-Path $out $d) -Recurse -Force
  Move-Item $zipStash[$d] (Join-Path $out $d)
}

Write-Output "Portable folder ready: $out"
Write-Output "Portable archive ready: $zipPath"

$iscc = "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $iscc)) {
  $iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
}
$issPath = Join-Path $PSScriptRoot "installer.iss"
if ((Test-Path $iscc) -and (Test-Path $issPath)) {
  & $iscc /Q $issPath
  Write-Output "Installer ready: $(Join-Path $root 'Klaro-Windows-Setup.exe')"
}