# ██╗    ██╗██╗███╗   ██╗██████╗  ██████╗ ████████╗███████╗
# ██║    ██║██║████╗  ██║██╔══██╗██╔═══██╗╚══██╔══╝██╔════╝
# ██║ █╗ ██║██║██╔██╗ ██║██║  ██║██║   ██║   ██║   ███████╗
# ██║███╗██║██║██║╚██╗██║██║  ██║██║   ██║   ██║   ╚════██║
# ╚███╔███╔╝██║██║ ╚████║██████╔╝╚██████╔╝   ██║   ███████║
#  ╚══╝╚══╝ ╚═╝╚═╝  ╚═══╝╚═════╝  ╚═════╝    ╚═╝   ╚══════╝
# Setup.ps1 - Scott McKendry
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#Requires -RunAsAdministrator
#Requires -Version 7

# Dot-source the Install.ps1 script to load the function into the current session
# . .\Install.ps1

# Linked Files (Destination => Source)
$symlinks = @{
    $PROFILE.CurrentUserAllHosts                                                                    = ".\Profile.ps1"
    "$HOME\AppData\Local\nvim"                                                                      = ".\nvim"
    "$HOME\AppData\Local\fastfetch"                                                                 = ".\fastfetch"
    "$HOME\AppData\Local\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" = ".\windowsterminal\settings.json"
    "$HOME\.gitconfig"                                                                              = ".\.gitconfig"
    "$HOME\AppData\Roaming\lazygit"                                                                 = ".\lazygit"
    "$HOME\.config\ccstatusline\settings.json"                                                      = ".\ccstatusline\settings.json"
    "$HOME\.claude\CLAUDE.md"                                                                       = ".\claude\CLAUDE.md"
    "$HOME\.claude\hooks\jira-branch-gate.sh"                                                       = ".\claude\hooks\jira-branch-gate.sh"
    "$HOME\.claude\skills\babysit-pr"                                                               = ".\claude\skills\babysit-pr"
}

# Winget & choco dependencies
$wingetDeps = @(
    "chocolatey.chocolatey"
    "eza-community.eza"
    "ezwinports.make"
    "fastfetch-cli.fastfetch"
    "gerardog.gsudo"
    "git.git"
    "github.cli"
    "kitware.cmake"
    "mbuilov.sed"
    "microsoft.powershell"
    "neovim.neovim"
    "openjs.nodejs"
    "starship.starship"

    # Dev tools & runtimes
    "7zip.7zip"
    "amazon.awscli"
    "astral-sh.uv"
    "caddyserver.caddy"
    "coder.coder"
    "coder.coderdesktop"
    "docker.dockerdesktop"
    "golang.go"
    "google.cloudsdk"
    "hashicorp.terraform"
    "insomnia.insomnia"
    "jqlang.jq"
    "microsoft.azurecli"
    "microsoft.dotnet.sdk.9"
    "microsoft.dotnet.sdk.10"
    "microsoft.visualstudiocode"
    "microsoft.windowsterminal"
    "microsoft.wsl"
    "notepad++.notepad++"
    "opentofu.tofu"
    "postgresql.postgresql.18"
    "python.python.3.14"

    # Apps
    "adobe.acrobat.reader.64-bit"
    "andrewng.openworker"
    "anthropic.claude"
    "devtoys-app.devtoys"
    "figma.figma"
    "google.chrome"
    "google.googledrive"
    "logitech.optionsplus"
    "marktext.marktext"
    "microsoft.powertoys"
    "9PFXXSHC64H3" # Raycast (Microsoft Store)
    "slacktechnologies.slack"
    "zoom.zoom.exe"
)
$chocoDeps = @(
    "bat"
    "fd"
    "fzf"
    "gawk"
    "k9s"
    "kubernetes-cli"
    "kubernetes-helm"
    "lazygit"
    "less"
    "mingw"
    "nerd-fonts-jetbrainsmono"
    "ripgrep"
    "sqlite"
    "zig"
    "zoxide"
)

# Global npm packages
$npmDeps = @(
    "@fission-ai/openspec"
    "@google/gemini-cli"
    "ccstatusline"
    "mcp-remote"
    "pnpm"
)

# PS Modules
$psModules = @(
    "Pester"
    "PSScriptAnalyzer"
    "poshy-coreutils-ish"
    "powershell-yaml"
    "ps-color-scripts"
)

# Set working directory
Set-Location $PSScriptRoot
[Environment]::CurrentDirectory = $PSScriptRoot

Write-Host "Installing missing dependencies..."
$installedWingetDeps = winget list | Out-String
foreach ($wingetDep in $wingetDeps) {
    if ($installedWingetDeps -notmatch $wingetDep) {
        winget install --id $wingetDep
    }
}

# Path Refresh
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

$installedChocoDeps = (choco list --limit-output --id-only).Split("`n")
foreach ($chocoDep in $chocoDeps) {
    if ($installedChocoDeps -notcontains $chocoDep) {
        choco install $chocoDep -y
    }
}

# Install PS Modules
foreach ($psModule in $psModules) {
    if (!(Get-Module -ListAvailable -Name $psModule)) {
        Install-Module -Name $psModule -Force -AcceptLicense -Scope CurrentUser
    }
}

$installedNpmDeps = npm ls -g --depth=0 2>$null | Out-String
foreach ($npmDep in $npmDeps) {
    if ($installedNpmDeps -notmatch [regex]::Escape("$npmDep@")) {
        npm install -g $npmDep
    }
}

if (!(Get-Command claude -ErrorAction SilentlyContinue)) {
    Invoke-RestMethod https://claude.ai/install.ps1 | Invoke-Expression
}

# Windows Terminal's default profile launches herdr from its installer's stable alias path
if (!(Test-Path "$env:LOCALAPPDATA\Programs\Herdr\bin\herdr.exe")) {
    Invoke-RestMethod https://herdr.dev/install.ps1 | Invoke-Expression
    & "$env:LOCALAPPDATA\Programs\Herdr\bin\herdr.exe" integration install claude
}

# Leapp isn't published to winget or choco, so point to the installer instead of guessing a URL
if (!(Test-Path "$env:LOCALAPPDATA\Programs\Leapp")) {
    Start-Process "https://www.leapp.cloud/releases"
}

# Delete OOTB Nvim Shortcuts (including QT)
if (Test-Path "$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Neovim\") {
    Remove-Item "$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Neovim\" -Recurse -Force
}

$currentGitEmail = (git config --global user.email)
$currentGitName = (git config --global user.name)

# Create Symbolic Links
Write-Host "Creating Symbolic Links..."
foreach ($symlink in $symlinks.GetEnumerator()) {
    Get-Item -Path $symlink.Key -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path (Split-Path $symlink.Key) -Force | Out-Null
    New-Item -ItemType SymbolicLink -Path $symlink.Key -Target (Resolve-Path $symlink.Value) -Force | Out-Null
}

# Copied rather than linked: Claude Code rewrites settings.json at runtime, and a link would
# leak work-only additions (org plugins, autoMode context) back into this public repo.
if (!(Test-Path "$HOME\.claude\settings.json")) {
    Copy-Item ".\claude\settings.json" "$HOME\.claude\settings.json"
}

git config --global --unset user.email | Out-Null
git config --global --unset user.name | Out-Null
git config --global user.email $currentGitEmail | Out-Null
git config --global user.name $currentGitName | Out-Null

# Install bat themes
bat cache --clear
bat cache --build