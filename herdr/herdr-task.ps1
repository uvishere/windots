<#
.SYNOPSIS
    Starts a JIRA ticket in its own herdr worktree workspace, or opens the focused task's links.
.DESCRIPTION
    herdr-task.ps1          (prefix+t) Asks for a JIRA link, key or branch name (suggested from
                            the clipboard), a short description and a repository, then starts
                            Claude on the ticket in a worktree workspace branched from origin's
                            default branch. A ticket that already has a worktree reopens it.
    herdr-task.ps1 open     (prefix+o) Picks one of the focused task's links (ticket, PR,
                            changed files, checks, each failing check, the branch) and opens it
                            in the browser; ctrl-y copies it instead.

    HERDR_TASK_PROJECT_ROOTS (semicolon separated, default ~\pageup) lists the directories
    whose child repositories the project picker offers. HERDR_TASK_JIRA_SITE overrides the
    JIRA site used to build ticket links from a bare key.
.PARAMETER Command
    Empty for the interactive start, or "open".
#>
param([string]$Command)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
[Console]::InputEncoding = [Text.Encoding]::UTF8

$herdr = $env:HERDR_BIN_PATH ?? 'herdr'
$jiraSite = $env:HERDR_TASK_JIRA_SITE ?? 'https://pageuppeople.atlassian.net'
$projectRoots = ($env:HERDR_TASK_PROJECT_ROOTS ?? "$HOME\pageup") -split ';'
$metadataSource = 'herdr-task'
$ticketKeyPattern = '[A-Za-z][A-Za-z0-9]*-\d+'

# Nerd Font Octicons.
$ticketIcon = [char]0xF41B
$pullRequestIcon = [char]0xF407
$changedFilesIcon = [char]0xF4D2
$checksIcon = [char]0xF45E
$failedCheckIcon = [char]0xF52F
$compareIcon = [char]0xF47F
$branchIcon = [char]0xF418

<#
.SYNOPSIS
    Runs a herdr CLI command and returns the "result" of its JSON reply.
.EXCEPTION
    Throws when herdr exits non-zero.
#>
function Invoke-Herdr {
    $reply = & $herdr @args
    if ($LASTEXITCODE) { throw "herdr $($args -join ' ') failed: $reply" }
    ($reply | ConvertFrom-Json).result
}

<#
.SYNOPSIS
    Turns a JIRA link, a JIRA key or a branch carrying a key into the task's key, link and branch.
.PARAMETER Reference
    A JIRA link (/browse/PE-123 or ?selectedIssue=PE-123), a key such as PE-123, or a branch name
    containing a key, which is used as is.
.PARAMETER Description
    Short description appended to the branch name built from a link or key.
.OUTPUTS
    [pscustomobject] with Key, Url and Branch.
.EXCEPTION
    Throws when the reference carries no JIRA key: every task traces to a ticket.
#>
function Resolve-Ticket([string]$Reference, [string]$Description) {
    $branch = $null
    if ($Reference -match "^https?://\S+?(?:/browse/|[?&]selectedIssue=)($ticketKeyPattern)") {
        $key = $Matches[1]
    }
    elseif ($Reference -match "^$ticketKeyPattern$") {
        $key = $Reference
    }
    elseif ($Reference -match "\b($ticketKeyPattern)\b") {
        $key = $Matches[1]
        git check-ref-format --branch $Reference *> $null
        if ($LASTEXITCODE) { throw "'$Reference' is not a valid branch name" }
        $branch = $Reference
    }
    else {
        throw "'$Reference' has no JIRA key; give a ticket link, a key such as PE-123, or a branch containing one"
    }
    $key = $key.ToUpper()
    if (-not $branch) {
        $slug = ($Description.ToLower() -replace '[^a-z0-9]+', '-').Trim('-')
        $branch = $slug ? "feat/$key-$slug" : "feat/$key"
        if ($branch.Length -gt 60) { $branch = $branch.Substring(0, 60).TrimEnd('-') }
    }
    [pscustomobject]@{ Key = $key; Url = "$jiraSite/browse/$key"; Branch = $branch }
}

<#
.SYNOPSIS
    Lets the user pick a repository under the project roots, the focused pane's repository first.
.OUTPUTS
    [string] the repository path, or nothing when the picker is cancelled.
#>
function Select-Project {
    $focusedRepo = $null
    if ($env:HERDR_ACTIVE_PANE_CWD) {
        # The common git dir points at the main checkout even from inside a task worktree.
        $commonGitDir = git -C $env:HERDR_ACTIVE_PANE_CWD rev-parse --path-format=absolute --git-common-dir 2>$null
        if ($commonGitDir) { $focusedRepo = (Split-Path ($commonGitDir -replace '/', '\')) }
    }
    $repos = $projectRoots | Get-ChildItem -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName '.git') -PathType Container } |
        ForEach-Object FullName
    @($focusedRepo) + $repos | Where-Object { $_ } | Select-Object -Unique | fzf --prompt 'Project > '
}

<#
.SYNOPSIS
    Opens (or reopens) the ticket's worktree workspace, tags it for the sidebar and starts Claude.
.PARAMETER Ticket
    Output of Resolve-Ticket.
.PARAMETER Project
    Repository the worktree branches from.
.PARAMETER Label
    Workspace label until Claude renames it after the ticket title.
#>
function Start-Ticket($Ticket, [string]$Project, [string]$Label) {
    $existingWorktree = (Invoke-Herdr worktree list --cwd $Project).worktrees |
        Where-Object { $_.is_linked_worktree -and ($_.branch -eq $Ticket.Branch -or $_.branch -match "\b$($Ticket.Key)\b") } |
        Select-Object -First 1
    if ($existingWorktree) {
        Write-Host "$($Ticket.Key) already has a worktree at $($existingWorktree.path), opening it"
        $workspace = Invoke-Herdr worktree open --cwd $Project --path $existingWorktree.path --label $Label --focus
        $prompt = "Continue $($Ticket.Key) ($($Ticket.Url)) in this worktree on branch $($existingWorktree.branch)."
    }
    else {
        # New work branches from the latest default branch, never from whatever the main checkout has out.
        git -C $Project fetch --quiet origin
        $base = git -C $Project symbolic-ref --short refs/remotes/origin/HEAD
        Write-Host "creating $($Ticket.Branch) from $base"
        $workspace = Invoke-Herdr worktree create --cwd $Project --branch $Ticket.Branch --base $base --label $Label --focus
        $prompt = "/ticket $($Ticket.Key) - this herdr workspace is already a dedicated worktree on branch $($Ticket.Branch), branched from $base. Work there and do not create another branch. Once you have read the ticket, rename the workspace to its title without the key: herdr workspace rename `"`$env:HERDR_WORKSPACE_ID`" `"<title>`""
    }
    $workspaceId = $workspace.workspace.workspace_id
    $rootPane = $workspace.root_pane.pane_id

    Invoke-Herdr workspace report-metadata $workspaceId --source $metadataSource `
        --token "repo=$(Split-Path $Project -Leaf)" --token "jira=$ticketIcon $($Ticket.Key)" `
        --token "jira_id=$($Ticket.Key)" --token "jira_url=$($Ticket.Url)" | Out-Null

    # Agent names must be lowercase and unique per workspace, so a retried ticket never collides
    # with a name herdr still holds.
    $agentName = "$($Ticket.Key)-$($workspaceId.TrimStart('w'))".ToLower()
    # The new pane's shell takes a moment to become an agent target. An attempt can fail after
    # it has already launched Claude, so a later "name taken" means an earlier attempt worked.
    foreach ($attempt in 1..20) {
        $startReply = & $herdr agent start $agentName --kind claude --pane $rootPane 2>&1
        if (-not $LASTEXITCODE -or "$startReply" -match 'agent_name_taken') { break }
        Start-Sleep -Milliseconds 500
    }
    if ($LASTEXITCODE -and "$startReply" -notmatch 'agent_name_taken') {
        throw "the workspace is ready but Claude did not start in pane ${rootPane}: $startReply"
    }
    Invoke-Herdr agent prompt $agentName $prompt | Out-Null
}

function Start-TicketInteractively {
    $clipboard = (Get-Clipboard -Raw)?.Trim()
    $suggestion = $clipboard -match "^(https?://\S+?(/browse/|[?&]selectedIssue=)$ticketKeyPattern|$ticketKeyPattern)" ? $clipboard : $null
    $reference = Read-Host ($suggestion ? "JIRA link, key or branch [$suggestion]" : 'JIRA link, key or branch')
    $reference = $reference ? $reference.Trim() : $suggestion
    if (-not $reference) { return }

    $ticket = Resolve-Ticket $reference
    $description = $null
    if ($ticket.Branch -eq "feat/$($ticket.Key)") {
        $description = Read-Host "Short description for the branch (feat/$($ticket.Key)-...)"
        $ticket = Resolve-Ticket $reference $description
    }
    $project = Select-Project
    if (-not $project) { return }
    Start-Ticket $ticket $project ($description ? $description : $ticket.Key)
}

function Show-TaskLinks {
    $pane = (Invoke-Herdr pane get $env:HERDR_ACTIVE_PANE_ID).pane
    $tokens = (Invoke-Herdr workspace get $pane.workspace_id).workspace.tokens
    $paneCwd = $pane.foreground_cwd ?? $pane.cwd
    $branch = git -C $paneCwd symbolic-ref --short -q HEAD 2>$null
    $defaultBranch = (git -C $paneCwd symbolic-ref --short refs/remotes/origin/HEAD 2>$null) -replace '^origin/'
    if (-not $defaultBranch) { $defaultBranch = 'main' }
    if ($branch -eq $defaultBranch) { $branch = $null }
    $repoSlug = (git -C $paneCwd remote get-url origin 2>$null) -match 'github\.com[:/]([^/]+/[^/]+?)(\.git)?$' ? $Matches[1] : $null

    $links = [ordered]@{}
    if ($tokens.jira_url) { $links["$ticketIcon  $($tokens.jira_id)"] = $tokens.jira_url }
    $pullRequest = $null
    if ($branch) {
        Push-Location $paneCwd
        $pullRequest = gh pr view --json number,url,title,statusCheckRollup 2>$null | ConvertFrom-Json
        Pop-Location
    }
    if ($pullRequest) {
        $links["$pullRequestIcon  #$($pullRequest.number)  $($pullRequest.title)"] = $pullRequest.url
        $links["$changedFilesIcon  changed files"] = "$($pullRequest.url)/files"
        $links["$checksIcon  checks"] = "$($pullRequest.url)/checks"
        foreach ($check in $pullRequest.statusCheckRollup) {
            $checkState = ([string]($check.conclusion ? $check.conclusion : $check.state)).ToUpper()
            if ($checkState -in 'FAILURE', 'ERROR', 'CANCELLED', 'TIMED_OUT', 'ACTION_REQUIRED', 'STARTUP_FAILURE') {
                $links["$failedCheckIcon  failing: $($check.name ?? $check.context)"] = $check.detailsUrl ?? $check.targetUrl
            }
        }
    }
    elseif ($branch -and $repoSlug) {
        $links["$compareIcon  compare $branch"] = "https://github.com/$repoSlug/compare/$defaultBranch...$branch"
    }
    if ($branch -and $repoSlug) { $links["$branchIcon  branch $branch"] = "https://github.com/$repoSlug/tree/$branch" }

    if (-not $links.Count) { throw "no ticket, PR or GitHub branch for this pane (start the task with prefix+t)" }
    $copy = $false
    if ($links.Count -eq 1) {
        $url = @($links.Values)[0]
    }
    else {
        $picked = $links.GetEnumerator() | ForEach-Object { "$($_.Key)`t$($_.Value)" } |
            fzf --delimiter "`t" --with-nth 1 --prompt 'Open > ' --expect ctrl-y --header 'enter: open   ctrl-y: copy link'
        if (-not $picked -or $picked.Count -lt 2) { return }
        $copy = $picked[0] -eq 'ctrl-y'
        $url = ($picked[1] -split "`t")[1]
    }
    if ($copy) {
        Set-Clipboard $url
        & $herdr notification show 'Link copied' --body $url *> $null
    }
    else {
        Start-Process $url
    }
}

try {
    switch ($Command) {
        '' { Start-TicketInteractively }
        'open' { Show-TaskLinks }
        default { throw "unknown command '$Command' (use no command, or open)" }
    }
}
catch {
    # Popups close as soon as the script exits, so hold the error on screen.
    Write-Host "herdr-task: $_" -ForegroundColor Red
    Read-Host 'press Enter to close' | Out-Null
    exit 1
}
