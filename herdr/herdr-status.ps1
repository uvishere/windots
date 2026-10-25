<#
.SYNOPSIS
    Prints one line for herdr's tab bar: agents waiting for you, then the focused branch's PR,
    its review decision and CI rollup, e.g. "2 blocked · #123 · changes · CI" with Octicons.
.DESCRIPTION
    herdr runs this on its server with the active pane's context, keeps only the last line and
    strips escape sequences, so nothing here is coloured or clickable (prefix+o opens the PR).
    Every lookup degrades to printing less, never an error.
#>
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$ErrorActionPreference = 'SilentlyContinue'

# Nerd Font Octicons.
$alertIcon = [char]0xF421
$pullRequestIcon = [char]0xF407
$draftIcon = [char]0xF4DD
$mergedIcon = [char]0xF419
$closedIcon = [char]0xF4DC
$approvedIcon = [char]0xF49E
$changesIcon = [char]0xF4D2
$reviewIcon = [char]0xF441
$passedIcon = [char]0xF42E
$failedIcon = [char]0xF467
$pendingIcon = [char]0xF444

$herdr = $env:HERDR_BIN_PATH ?? 'herdr'
$statusParts = @()

$blockedCount = @((& $herdr pane list | ConvertFrom-Json).result.panes | Where-Object agent_status -EQ 'blocked').Count
if ($blockedCount) { $statusParts += "$alertIcon $blockedCount blocked" }

$focusedPane = $env:HERDR_ACTIVE_PANE_ID ? (& $herdr pane get $env:HERDR_ACTIVE_PANE_ID | ConvertFrom-Json).result.pane : $null
$paneCwd = $focusedPane.foreground_cwd ?? $focusedPane.cwd ?? $env:HERDR_ACTIVE_PANE_CWD
$repoRoot = $paneCwd ? (git -C $paneCwd rev-parse --show-toplevel 2>$null) : $null
$branch = $repoRoot ? (git -C $repoRoot symbolic-ref --short -q HEAD 2>$null) : $null
$defaultBranch = $repoRoot ? ((git -C $repoRoot symbolic-ref --short refs/remotes/origin/HEAD 2>$null) -replace '^origin/') : $null
if (-not $defaultBranch) { $defaultBranch = 'main' }

if ($branch -and $branch -ne $defaultBranch) {
    Push-Location $repoRoot
    $pullRequest = gh pr view $branch --json number,state,isDraft,reviewDecision,statusCheckRollup 2>$null | ConvertFrom-Json
    Pop-Location
    if (-not $pullRequest) {
        $statusParts += "$pullRequestIcon no PR"
    }
    else {
        $stateIcon = switch ($pullRequest.state) {
            'MERGED' { $mergedIcon }
            'CLOSED' { $closedIcon }
            default { $pullRequest.isDraft ? $draftIcon : $pullRequestIcon }
        }
        $statusParts += "$stateIcon #$($pullRequest.number)"
        if ($pullRequest.state -eq 'OPEN') {
            $reviewText = @{
                APPROVED          = "$approvedIcon approved"
                CHANGES_REQUESTED = "$changesIcon changes"
                REVIEW_REQUIRED   = "$reviewIcon review"
            }[[string]$pullRequest.reviewDecision]
            if ($reviewText) { $statusParts += $reviewText }

            # Check runs report a conclusion once finished; commit statuses only ever report a state.
            $checkStates = @($pullRequest.statusCheckRollup | ForEach-Object { ([string]($_.conclusion ? $_.conclusion : $_.state ? $_.state : $_.status)).ToUpper() })
            if ($checkStates.Count) {
                if ($checkStates | Where-Object { $_ -in 'FAILURE', 'ERROR', 'CANCELLED', 'TIMED_OUT', 'ACTION_REQUIRED', 'STARTUP_FAILURE' }) { $statusParts += "$failedIcon CI" }
                elseif ($checkStates | Where-Object { $_ -notin 'SUCCESS', 'NEUTRAL', 'SKIPPED' }) { $statusParts += "$pendingIcon CI" }
                else { $statusParts += "$passedIcon CI" }
            }
        }
    }
}

if ($statusParts) { $statusParts -join ' · ' }
