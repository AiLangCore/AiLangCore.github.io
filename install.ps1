param(
  [string]$Version = $env:AILANG_VERSION,
  [ValidateSet('stable', 'alpha', 'beta', 'rc')]
  [string]$Channel = $(if ($env:AILANG_CHANNEL) { $env:AILANG_CHANNEL } else { 'beta' }),
  [string]$InstallRoot = $(if ($env:AILANG_INSTALL_ROOT) { $env:AILANG_INSTALL_ROOT } else { Join-Path $HOME '.ailang' }),
  [string]$Repo = $(if ($env:AILANG_REPO) { $env:AILANG_REPO } else { 'AiLangCore/AiLang' }),
  [string]$AivmVersion = $env:AIVM_VERSION,
  [string]$AiVectraVersion = $env:AIVECTRA_VERSION,
  [string]$AivmRepo = $(if ($env:AIVM_REPO) { $env:AIVM_REPO } else { 'AiLangCore/AiVM' }),
  [string]$AiVectraRepo = $(if ($env:AIVECTRA_REPO) { $env:AIVECTRA_REPO } else { 'AiLangCore/AiVectra' })
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

function Resolve-RepoTag {
  param([string]$RepoName, [string]$ExactVersion)
  if ($ExactVersion) {
    if ($ExactVersion.StartsWith('v')) { return $ExactVersion }
    return "v$ExactVersion"
  }
  if ($Channel -eq 'stable') {
    $latest = Invoke-RestMethod "https://api.github.com/repos/$RepoName/releases/latest"
    return $latest.tag_name
  }
  $releases = Invoke-RestMethod "https://api.github.com/repos/$RepoName/releases?per_page=100"
  $match = $releases | Where-Object { $_.tag_name -match "-$Channel\." } | Select-Object -First 1
  if (-not $match) {
    throw "could not resolve release for $RepoName channel: $Channel"
  }
  return $match.tag_name
}

function Resolve-Tag {
  return Resolve-RepoTag $Repo $Version
}

function Expand-Package {
  param([string]$Archive, [string]$Destination)
  New-Item -ItemType Directory -Force $Destination | Out-Null
  $extractDir = Join-Path $tmp "extract-$([guid]::NewGuid())"
  New-Item -ItemType Directory -Force $extractDir | Out-Null
  Expand-Archive -Path $Archive -DestinationPath $extractDir -Force
  $expanded = Get-ChildItem $extractDir -Directory | Select-Object -First 1
  if ($expanded) {
    Copy-Item -Path (Join-Path $expanded.FullName '*') -Destination $Destination -Recurse -Force
  } else {
    Copy-Item -Path (Join-Path $extractDir '*') -Destination $Destination -Recurse -Force
  }
}

function Download-Asset {
  param([string]$RepoName, [string]$TagName, [string]$ArtifactName, [string]$OutFile)
  Invoke-WebRequest -Uri "https://github.com/$RepoName/releases/download/$TagName/$ArtifactName" -OutFile $OutFile
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
  Invoke-WebRequest -Uri $url -OutFile $archive

  $dest = Join-Path $InstallRoot "toolchains\$versionNoV"
  Remove-Item -Recurse -Force $dest -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force $dest | Out-Null
  Expand-Package $archive $dest

  $aivmTag = Resolve-RepoTag $AivmRepo $AivmVersion
  if ($aivmTag) {
    $aivmVersionNoV = $aivmTag.TrimStart('v')
    $aivmArtifact = "aivm-$aivmVersionNoV-windows.zip"
    $aivmArchive = Join-Path $tmp $aivmArtifact
    $aivmStage = Join-Path $tmp 'aivm'
    $aivmDest = Join-Path $dest 'aivm'
    Download-Asset $AivmRepo $aivmTag $aivmArtifact $aivmArchive
    Expand-Package $aivmArchive $aivmStage
    New-Item -ItemType Directory -Force $aivmDest, (Join-Path $dest 'bin') | Out-Null
    Copy-Item -Path (Join-Path $aivmStage '*') -Destination $aivmDest -Recurse -Force
    $aivmExe = Join-Path $aivmStage 'bin\aivm.exe'
    if (Test-Path $aivmExe) {
      Copy-Item -Path $aivmExe -Destination (Join-Path $dest 'bin\aivm.exe') -Force
    }
  }

  $aivectraTag = Resolve-RepoTag $AiVectraRepo $AiVectraVersion
  if ($aivectraTag) {
    $aivectraVersionNoV = $aivectraTag.TrimStart('v')
    $aivectraArtifact = "aivectra-$aivectraVersionNoV.zip"
    $aivectraArchive = Join-Path $tmp $aivectraArtifact
    $aivectraStage = Join-Path $tmp 'aivectra'
    $aivectraDest = Join-Path $dest 'aivectra'
    Download-Asset $AiVectraRepo $aivectraTag $aivectraArtifact $aivectraArchive
    Expand-Package $aivectraArchive $aivectraStage
    New-Item -ItemType Directory -Force $aivectraDest, (Join-Path $dest 'bin') | Out-Null
    Copy-Item -Path (Join-Path $aivectraStage '*') -Destination $aivectraDest -Recurse -Force
    $aivectraCmd = Join-Path $aivectraStage 'bin\aivectra'
    if (Test-Path $aivectraCmd) {
      Copy-Item -Path $aivectraCmd -Destination (Join-Path $dest 'bin\aivectra') -Force
    }
  }

  New-Item -ItemType Directory -Force (Join-Path $InstallRoot 'bin') | Out-Null
  $current = Join-Path $InstallRoot 'current'
  if (Test-Path $current) { Remove-Item -Recurse -Force $current }
  New-Item -ItemType Junction -Path $current -Target $dest | Out-Null
  New-Shim ailang ailang
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
