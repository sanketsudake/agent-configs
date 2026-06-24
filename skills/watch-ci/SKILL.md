---
name: watch-ci
description: After pushing to a PR, watch its CI checks to terminal state and surface each transition as a notification instead of busy-polling. Use when you've just pushed a fix and want to know the moment a check goes green or red, or whenever the user says "watch CI", "wait for the checks", "is CI green yet", "loop on CI". Pairs with debug-ci (hand back to it on a red check) and resolve-bot-review-threads (the fix→push→resolve→re-request→watch loop).
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

## Discipline while a monitor is armed

Let the monitor run to completion before pushing new changes or re-querying CI state.
On a red check, hand the failure to the **debug-ci** skill.
