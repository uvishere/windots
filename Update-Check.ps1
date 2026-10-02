# Update-Check.ps1 — refreshes the update-status cache used by the prompt.
# Invoked detached from Profile.ps1 when the cache is older than 60 minutes.

$ErrorActionPreference = 'SilentlyContinue'

$statusDir = Join-Path $env:LOCALAPPDATA 'windots-status'
New-Item -Path $statusDir -ItemType Directory -Force | Out-Null

$repo = $env:WindotsLocalRepo
if (-not $repo) { $repo = Split-Path $PSCommandPath -Parent }

# Dotfiles update check
Push-Location $repo
git fetch *>$null
$behind = (git status) -match 'behind'
Pop-Location
$dotfilesIcon = if ($behind) { "󱤛 " } else { '' }
Set-Content -Path (Join-Path $statusDir 'dotfiles') -Value $dotfilesIcon -NoNewline -Encoding utf8

# Software update check (winget + choco)
$wingetOut = winget list --upgrade-available 2>&1 | Out-String
$chocoOut = choco upgrade all --noop -y 2>&1 | Out-String
$hasUpdates = ($wingetOut -match 'upgrades available') -or ($chocoOut -notmatch 'can upgrade 0/')
$softwareIcon = if ($hasUpdates) { " " } else { '' }
Set-Content -Path (Join-Path $statusDir 'software') -Value $softwareIcon -NoNewline -Encoding utf8
