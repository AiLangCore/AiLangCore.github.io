param(
  [string]$Version = $env:AILANG_VERSION,
  [ValidateSet('stable', 'alpha', 'beta', 'rc')]
  [string]$Channel = $(if ($env:AILANG_CHANNEL) { $env:AILANG_CHANNEL } else { 'stable' }),
  [string]$InstallRoot = $(if ($env:AILANG_INSTALL_ROOT) { $env:AILANG_INSTALL_ROOT } else { Join-Path $HOME '.ailang' }),
  [string]$Repo = $(if ($env:AILANG_REPO) { $env:AILANG_REPO } else { 'AiLangCore/AiLang' })
)

$ErrorActionPreference = 'Stop'

function Get-Rid {
  $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
  switch ($arch) {
    'X64' { $cpu = 'x64' }
    'Arm64' { $cpu = 'arm64' }
    default { throw "unsupported architecture: $arch" }
  }
  if ($IsWindows -or $env:OS -eq 'Windows_NT') {
    return "windows-$cpu"
  }
  if ($IsMacOS) {
    return "osx-$cpu"
  }
  if ($IsLinux) {
    return "linux-$cpu"
  }
  throw 'unsupported operating system'
}

function Resolve-Tag {
  if ($Version) {
    if ($Version.StartsWith('v')) { return $Version }
    return "v$Version"
  }
  if ($Channel -eq 'stable') {
    $latest = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases/latest"
    return $latest.tag_name
  }
  $releases = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases?per_page=100"
  $match = $releases | Where-Object { $_.tag_name -match "-$Channel\." } | Select-Object -First 1
  if (-not $match) {
    throw "could not resolve AiLang release for channel: $Channel"
  }
  return $match.tag_name
}

function New-Shim {
  param([string]$Name, [string]$Target)
  $path = Join-Path $InstallRoot "bin\$Name.cmd"
  $content = @"
@echo off
set ROOT=%~dp0..
set CURRENT=%ROOT%\current
if exist "%CURRENT%\bin\$Target.exe" "%CURRENT%\bin\$Target.exe" %*
if exist "%CURRENT%\$Target.exe" "%CURRENT%\$Target.exe" %*
if "$Target"=="ailang" if exist "%CURRENT%\airun.exe" "%CURRENT%\airun.exe" %*
echo missing installed executable: $Target 1>&2
exit /b 127
"@
  Set-Content -Path $path -Value $content -Encoding ASCII
}

$rid = Get-Rid
$tag = Resolve-Tag
$versionNoV = $tag.TrimStart('v')
$tmp = New-Item -ItemType Directory -Force (Join-Path ([System.IO.Path]::GetTempPath()) "ailang-install-$([guid]::NewGuid())")

try {
  $artifact = "ailang-$versionNoV-$rid.zip"
  $url = "https://github.com/$Repo/releases/download/$tag/$artifact"
  $archive = Join-Path $tmp $artifact
  try {
    Invoke-WebRequest -Uri $url -OutFile $archive
  } catch {
    $artifact = "airun-$versionNoV-$rid.zip"
    $url = "https://github.com/$Repo/releases/download/$tag/$artifact"
    $archive = Join-Path $tmp $artifact
    Invoke-WebRequest -Uri $url -OutFile $archive
  }

  $dest = Join-Path $InstallRoot "toolchains\$versionNoV"
  Remove-Item -Recurse -Force $dest -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force $dest | Out-Null
  Expand-Archive -Path $archive -DestinationPath $tmp -Force
  $expanded = Get-ChildItem $tmp -Directory | Where-Object { $_.Name -like "*$versionNoV*" } | Select-Object -First 1
  if ($expanded) {
    Copy-Item -Path (Join-Path $expanded.FullName '*') -Destination $dest -Recurse -Force
  } else {
    Copy-Item -Path (Join-Path $tmp '*') -Destination $dest -Recurse -Force
  }

  New-Item -ItemType Directory -Force (Join-Path $InstallRoot 'bin') | Out-Null
  $current = Join-Path $InstallRoot 'current'
  if (Test-Path $current) { Remove-Item -Recurse -Force $current }
  New-Item -ItemType Junction -Path $current -Target $dest | Out-Null
  New-Shim ailang ailang
  New-Shim airun airun
  New-Shim aivm aivm
  New-Shim aivectra aivectra

  Write-Host "Installed AiLangCore $versionNoV for $rid"
  Write-Host ""
  Write-Host "Add this to PATH:"
  Write-Host "  $InstallRoot\bin"
  Write-Host ""
  Write-Host "Then run:"
  Write-Host "  ailang --version"
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
