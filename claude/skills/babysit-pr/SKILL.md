---
name: babysit-pr
description: Use when you've opened/pushed a PR and want to shepherd it to merge-ready — watching CI, addressing reviewer comments (bot and human), and keeping the branch rebased on its base. Includes running continuously until CI is green and all threads are resolved.
---

# Babysit a PR to Merge-Ready

## Overview

Watch a PR across three workstreams until it is ready to merge: **CI health**, **review comments**, and **branch freshness**. Auto-fix what's obvious, escalate judgment calls, ride out each round of bot/human re-review and CI re-runs.

**Announce at start:** "Using the babysit-pr skill to shepherd this PR to merge-ready."

**Assumes the PR already exists.** If there's no PR for the current branch, abort and tell the user to create one (this skill babysits; it does not open PRs).

Self-contained: comment triage and rebase mechanics are inlined below — no other skills required. Apply a verify-before-you-agree mindset on review feedback: confirm a comment is correct before acting, push back when it's wrong, no performative agreement.

## When to Use

- You just pushed a PR and want it watched until green + approved.
- A PR is mid-flight: CI failing, bots/humans commenting, base branch moving.
- The user says "babysit this PR", "watch it until it's green", "ride it out".

**Don't use for:** opening the PR (do that first), or a pure one-off comment pass with no CI interest.

## The Three Workstreams

| Workstream | Source of truth | Auto-act | Escalate |
|------------|-----------------|----------|----------|
| **CI health** | `gh pr checks` (+ provider detail) | lint/format/type/obvious test fixes; retry flakes | logic test failures, ambiguous breakage |
| **Review comments** | GraphQL `reviewThreads` | `Act`/`Outdated` threads | `Human`/subjective threads |
| **Branch freshness** | base branch HEAD vs PR merge state | clean rebase + force-push | conflicts that are risky/ambiguous |

## Setup: Snapshot the PR

```bash
gh pr view --json number,url,title,state,baseRefName,mergeStateStatus \
  --jq '{number, url, title, state, base: .baseRefName, mergeState: .mergeStateStatus}'
```

If `state != OPEN`, stop — nothing to babysit. Keep a visible checklist of the three workstreams (a plan/todo list if your harness has one, otherwise a plain status list in your replies).

## Workstream A: CI Health

### 1. Read check status

```bash
gh pr checks <number> --json name,state,bucket,link,description
```

`bucket` ∈ `pass | fail | pending | skipping | cancel`. Act on `fail`; wait on `pending`; treat `cancel` as needs-attention (re-run or ask the user — never silently pass a canceled check).

### 2. Get failure detail (provider-aware)

The failed check's `link` points at the CI provider. Pull the failing log through whatever is available, in this order:

- **GitHub Actions:** `gh run view <run-id> --log-failed` (always available with `gh`).
- **Buildkite (if a Buildkite MCP is connected):** parse `org`/`pipeline`/`number` from the URL, then `get_build` → `list_jobs`/`get_job` → `read_logs`/`search_logs`.
- **No tooling for that provider:** open/return the `link` and ask the user for the failing output.

Don't assume every check is one provider — read the `link` host.

### 3. Triage each failing check

| Failure | Signal | Action |
|---------|--------|--------|
| **Lint / format** | lint step fails; diff is style only | auto-fix, re-push |
| **Type error** | compile fails with clear location | auto-fix if unambiguous |
| **Unit/integration test** | test step fails | read log → fix if cause is obvious; else escalate |
| **Flaky / infra** | timeout, network, OOM, passes on local re-run | **retry the build, don't change code** |
| **Build** | build/bundle step fails | fix if clear |
| **Logic / unknown** | ambiguous failure, behavior change expected | escalate with the log excerpt |

Before re-pushing a fix, run the repo's own test/lint commands locally if a project verify/test skill or an obvious `package.json`/`Makefile` target exists — don't hardcode a specific command.

**Retrying flakes:** confirm it's actually flaky (re-run the step locally / known-flaky test) before retrying. Never edit code to mask a flake. If the CI tooling is read-only, return the build link and ask the user to hit *Retry*.

## Workstream B: Review Comments (inlined)

Each round, one pass over unresolved threads:

### 1. Fetch threads (one GraphQL query)

```bash
gh api graphql -f query='
query($owner:String!,$repo:String!,$pr:Int!){
  repository(owner:$owner,name:$repo){
    pullRequest(number:$pr){
      reviewThreads(first:100){ nodes {
        id isResolved isOutdated
        comments(first:20){ nodes { author{login} body path line createdAt } }
      }}
    }
  }
}' -f owner=<owner> -f repo=<repo> -F pr=<number>
```

### 2. Triage each unresolved thread

- **Act** — concrete, correct, actionable → make the change.
- **Outdated** (`isOutdated`) — code already moved past it → resolve.
- **Human / subjective** — opinion, architecture call, unclear → queue for the user, don't auto-act.

Skip threads that are already `isResolved` or are only your own comments. Keep a small ledger of thread IDs you've addressed so you don't re-handle the same one (oscillation guard: if a thread reopens → fixed → reopens across 3 rounds, stop and escalate).

### 3. Reply + resolve

Reply in-thread on the comment, then resolve fixed threads:

```bash
# reply in-thread (REST):
gh api repos/<owner>/<repo>/pulls/<number>/comments/<comment_id>/replies -f body='...'
# resolve (GraphQL):
gh api graphql -f query='mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){ thread{ isResolved }}}' -f id=<threadId>
```

**Never dismiss a reviewer (human or AI) without user approval.** AI-reviewer replies can go out automatically; draft replies to **human** reviewers are a pause point.

### 4. Re-trigger AI reviewers

To re-request a bot review (e.g. `@codex review`, `@coderabbitai review`, `@cursor review`), post it **as an in-thread reply to one of that bot's existing review threads** — not a new top-level PR comment. If the bot has no thread yet (nothing to reply to), a fresh push is the trigger; only fall back to a top-level comment if that's the bot's documented trigger.

## Workstream C: Branch Freshness (rebase, inlined)

Whenever `mergeStateStatus` is `BEHIND` or `DIRTY`, bring the branch onto its base:

1. Detect the base: use the PR's `baseRefName` (from setup). Confirm you're not on it.
2. Check for uncommitted changes; stash or commit first.
3. Rebase:
   ```bash
   git fetch origin <base>
   git rebase origin/<base>
   ```
4. Conflicts: resolve clean ones (`git add` → `git rebase --continue`); **stop and ask** on anything risky/ambiguous. Abort with `git rebase --abort` if needed.
5. Re-verify (tests/lint) on the rebased tree, then `git push --force-with-lease` (never plain `--force`).

A rebase re-triggers CI and may re-trigger bot review — expect a fresh round.

## The Babysit Loop (heartbeat)

Loop-by-default. Each round:

1. **Snapshot** — `gh pr view` (state + mergeState) and `gh pr checks`.
2. **CI** — for each `fail`: pull detail, triage, auto-fix obvious / retry flakes / escalate logic failures.
3. **Comments** — run the Workstream B round.
4. **Apply + push** — commit fixes with a clear scoped message, push. If base moved → Workstream C. **Record the pushed HEAD SHA** (`git rev-parse HEAD`) — you'll use it, not a timestamp, to judge whether re-reviews are current.
5. **Re-trigger** AI reviewers (Workstream B step 4).
6. **Wait for the next round.**
   - **On Claude Code:** run a `persistent` **Monitor** that polls `gh pr checks` and `gh api .../comments?since=` and emits changes as events — react as they land, no busy-wait.
   - **On agents without Monitor/ScheduleWakeup (e.g. Codex CLI):** do NOT `sleep`-spin. Either use the harness's native persistent-work mechanism if it has one, or take one snapshot, report current state, and tell the user continuous watching needs external automation (a CI webhook, a cron, `gh pr checks --watch` in their terminal).

   A round is **NOT settled** until **both**: (a) no checks are `pending`, and (b) every reviewer you re-triggered has re-reviewed **the current HEAD SHA** — a bot review/comment tied to (or created after) the SHA you recorded in step 4. A "0 unresolved threads" snapshot taken before the bot answers is a **false settle**. Require the clean state to hold across **2 consecutive polls**.
7. Settled with work remaining → round N+1. Settled and clean → stop conditions.

## Stop Conditions

Stop when **all** hold:
- All checks `bucket == pass` (or `skipping`); no `cancel` left unhandled, **and**
- Every review thread resolved/addressed, nothing new outside the ledger, **and**
- Every bot you re-triggered has reviewed the current HEAD SHA (**never declare merge-ready in the window after a re-trigger and before the bot responds — the #1 false-victory trap**), **and**
- No `Human`/escalated-CI items pending a user decision, **and**
- `mergeStateStatus` is `CLEAN`. If it's `BLOCKED`, report why (missing approval, required check, branch protection) and hand to the user — don't loop on it.

Stop **immediately** if: the PR is merged/closed, the user says stop, or the same check oscillates fail→fixed→fail across 3 rounds (escalate as a judgment call instead of auto-fixing).

On stop, report final status: checks summary, threads resolved, rebase state, anything left for the user.

## Pause Points (always ask the user)

- Logic/ambiguous CI failures you can't confidently fix.
- Draft replies to **human** reviewers and `Human`-graded threads.
- Risky/ambiguous rebase conflicts.
- Force-push when the branch has commits you didn't make this session.
- Oscillating CI checks or review findings (the 3-round guards).

## Important Rules

- **Babysit only — never merge.** Leave the merge to the user unless explicitly told otherwise.
- **Never change code to mask a flake** — confirm, then retry.
- **Never dismiss a reviewer without user approval.**
- **Always re-verify after a rebase** before force-pushing.
- **One GraphQL query per comment round; one `gh pr checks` per CI round** — no redundant fan-out.
- **Never busy-wait / `sleep`-spin** — use Monitor (Claude) or hand off; honor the oscillation guards and stop conditions.
