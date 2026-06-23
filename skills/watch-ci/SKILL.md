---
name: watch-ci
description: After pushing to a PR, watch its CI checks to terminal state and surface each transition as a notification instead of busy-polling. Use when you've just pushed a fix and want to know the moment a check goes green or red, or whenever the user says "watch CI", "wait for the checks", "loop on CI". Pairs with debug-ci (hand back to it on a red check).
---

# Watch CI to terminal state

After a push you want each check's terminal state to arrive as a notification, not to sit in a foreground `gh pr checks` loop burning context and turns.
Arm a background monitor with the poll loop below.

This skill is project-agnostic; it only needs the PR number and an authenticated `gh`.

## The poll loop

```bash
prev=""
while true; do
  s=$(gh pr checks <PR> --json name,bucket,state 2>/dev/null) || { echo "gh-api-error"; sleep 30; continue; }
  cur=$(jq -r '.[] | select(.name != null) | select(.bucket != "pending") | "\(.name): \(.bucket)"' <<<"$s" | sort)
  comm -13 <(echo "$prev") <(echo "$cur")          # emit each newly-terminal check
  prev=$cur
  if jq -e 'map(select(.name != null)) | all(.bucket != "pending")' <<<"$s" >/dev/null 2>&1; then
    echo "DONE: all checks completed"
    break
  fi
  sleep 30
done
```

Run it under a background monitor (the harness's `Monitor` tool, or `run_in_background`) with a timeout that covers a full run (e.g. 40 min / `2400000` ms).
Each newly-non-pending check emits one stdout line → one notification; output is bounded to ~1 line per transition plus a final `DONE`.

## Why this shape

- **Not `gh pr checks --watch`** — that's a TTY screen-refresh; its output isn't structured per-event, so the harness can't split it into per-event notifications.
  The `comm -13` diff gives exactly one event per check transition.
- **30s polling** — check states update sub-second, but the API is rate-limited.
  30s means a 40-minute wait is ~80 calls (well under 5000/hour) while staying responsive.

## Discipline while a monitor is armed

- **Don't also poll `gh pr checks` in the foreground** to "check progress" — notifications arrive on their own; parallel polling wastes context and confuses you about stale state.
- **On a red check mid-loop**, you may start fetching that job's logs in the foreground, but **don't push another fix until the loop completes** — a different still-pending check often carries more diagnostic signal.
  Then hand the failure to the **debug-ci** skill.
- **If you must push mid-loop** (e.g. an obvious typo in the previous push), the old monitor keeps running against the superseded run; push, then re-arm a fresh monitor against the new run.
  The old one exits cleanly once its checks finish, or stop it via the harness's task-stop.

## Out of scope

- Diagnosing *why* a check failed → that's **debug-ci**.
- Cancelling runs (`gh run cancel <runId>`) — rarely needed; pushing a fix supersedes the old run.
