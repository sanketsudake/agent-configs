---
name: remediate-codeql-alerts
description: Use when fixing or triaging GitHub code-scanning / CodeQL alerts (triggers "fix codeql issues", "check code-scanning alerts", "dismiss false-positive alert"). Lists alerts, finds the taint source, fixes real ones, dismisses won't-fix, and verifies on the PR merge ref. Generic to any repo with CodeQL enabled.
---

# Remediate GitHub Code-Scanning / CodeQL Alerts

## Overview

CodeQL produces data-flow taint alerts in GitHub's code-scanning feed.
The fix loop is: list → identify source (not just sink) → triage → fix real findings in an isolated worktree → dismiss false positives via API → verify per-alert on the PR merge ref before merge.

This skill is distinct from `source-code-for-gh-advisory` (which covers reproducing the vulnerable code from a published GHSA on the consumer side).
Work in an isolated git worktree — use the `using-git-worktrees` skill.

---

## 0. Auth Prerequisite

```bash
gh auth status
gh auth refresh -s security_events   # add scope if missing
```

Without `security_events` scope, the code-scanning API returns HTTP 403.
For public repos, `public_repo` is sufficient for reads.

Quick probe to confirm access:

```bash
gh api repos/{owner}/{repo}/code-scanning/alerts --paginate 2>&1 | head -c 200
```

---

## 1. List Open Alerts

### Count open alerts

```bash
gh api repos/{owner}/{repo}/code-scanning/alerts \
  --paginate \
  -q '[.[] | select(.state=="open")] | length'
```

### Full triage table (tool, rule, severity, file)

```bash
gh api repos/{owner}/{repo}/code-scanning/alerts \
  --paginate \
  -q '.[] | select(.state=="open") | [.number, .tool.name, .rule.id, (.rule.security_severity_level // "n/a"), .most_recent_instance.location.path] | @tsv' \
  | sort -t$'\t' -k2,2 -k3,3
```

### Compact JSON per alert

```bash
gh api repos/{owner}/{repo}/code-scanning/alerts \
  --paginate \
  -q '.[] | select(.state=="open") | {
        num:      .number,
        tool:     .tool.name,
        rule:     .rule.id,
        sev:      .rule.security_severity_level,
        file:     .most_recent_instance.location.path,
        line:     .most_recent_instance.location.start_line,
        msg:      .most_recent_instance.message.text
      }'
```

`--paginate` is mandatory for repos with >30 alerts — the default page size is 30.

### Key alert fields

| Field | Meaning |
|---|---|
| `.number` | Stable alert number — used in PATCH dismiss calls |
| `.rule.id` | Rule identifier (e.g. `go/path-injection`, `TokenPermissions`) |
| `.rule.security_severity_level` | `critical` / `high` / `medium` / `low` / null |
| `.most_recent_instance.location.{path,start_line}` | File + line of the **sink** |
| `.most_recent_instance.message.text` | Human-readable description |
| `.most_recent_instance.message.markdown` | Often contains a link to the taint **source** |
| `.tool.name` | `CodeQL`, `OSSF Scorecard`, etc. — always filter by this |

---

## 2. Inspect a Single Alert

```bash
gh api repos/{owner}/{repo}/code-scanning/alerts/{number} \
  -q '{
        rule:   .rule.id,
        msg:    .most_recent_instance.message.text,
        path:   .most_recent_instance.location.path,
        line:   .most_recent_instance.location.start_line,
        ref:    .most_recent_instance.ref,
        commit: .most_recent_instance.commit_sha,
        analysis: .most_recent_instance.analysis_key
      }'
```

To get the full `most_recent_instance` including `.message.markdown` (which names the taint source):

```bash
gh api repos/{owner}/{repo}/code-scanning/alerts/{number} \
  --jq '.most_recent_instance' | python3 -m json.tool | head -80
```

The `.message.markdown` field often contains the source location as a link:
`"This path depends on a [user-provided value](path/to/file.go#L221C26-L221C32)."`
That link is the **source**. The `.location` in the alert is the **sink**.
Fix the code where the source is controlled or add a CodeQL-recognized barrier at the sink.

### Batch-inspect multiple alerts

```bash
for n in 17 310 312 315 334 335; do
  echo "=== Alert #$n ==="
  gh api repos/{owner}/{repo}/code-scanning/alerts/$n \
    -q '{rule: .rule.id, msg: .most_recent_instance.message.text,
         path: .most_recent_instance.location.path,
         line: .most_recent_instance.location.start_line}'
done
```

---

## 3. Triage Loop

### Step 1 — group by tool first

CodeQL (data-flow taint analysis) and OSSF Scorecard (policy/configuration checks) appear in the same feed but require completely different fix strategies. Always separate them before working.

### Step 2 — identify source, not just sink

The sink is where CodeQL flags the code. The source determines whether the risk is real.
Read `.message.markdown` to find the source file:line before deciding how to fix.

### Step 3 — decide real vs false positive

**Fix in code (real finding):**
- Sink is reachable from an untrusted HTTP/network/user-supplied source.
- A custom sanitizer exists but CodeQL does not model it as a barrier.
- Fix: replace the bare OS call at the sink with a CodeQL-recognized confinement primitive (e.g. `os.Root` for path-injection in Go, `filepath.Clean` + prefix check for simpler cases), or add a CodeQL custom query model.

**Dismiss (false positive / won't-fix):**
- Sink is intentionally user-supplied (e.g. an operator-configured command in a trusted channel).
- Existing mitigations are in place (no shell invocation, metacharacter rejection).
- Endpoint is an internal, trusted channel — not Internet-facing.
- No code change could clear the alert without removing the feature.

### Step 4 — fix in a git worktree

Use the `using-git-worktrees` skill to create an isolated worktree:

```bash
git worktree add .claude/worktrees/fix-codeql-issues -b fix/codeql-{rule-slug}
```

Build, vet, lint, and test after each change:

```bash
go build ./...
go vet ./pkg/affected/...
golangci-lint run ./pkg/affected/...
go test ./pkg/affected/...
```

---

## 4. Dismiss False Positives via API

```bash
gh api -X PATCH repos/{owner}/{repo}/code-scanning/alerts/{number} \
  -f state=dismissed \
  -f dismissed_reason="won't fix" \
  -f dismissed_comment="<justification under ~280 chars>"
```

Valid `dismissed_reason` values: `"won't fix"`, `"false positive"`, `"used in tests"`.

Confirm dismissal:

```bash
gh api repos/{owner}/{repo}/code-scanning/alerts/{number} \
  -q '{state: .state, reason: .dismissed_reason, comment: .dismissed_comment}'
```

Expected: `{"state":"dismissed","reason":"won't fix","comment":"..."}`

### Long-comment workaround

Comments longer than ~400-500 chars fail silently (state stays `open`; exit code may not surface the error).
Keep dismiss comments under ~280 chars, or use `--input` with a temp JSON file:

```bash
python3 - <<'PY'
import json
body = {
  "state": "dismissed",
  "dismissed_reason": "won't fix",
  "dismissed_comment": "Justification under ~280 chars."
}
open("/tmp/dismiss.json","w").write(json.dumps(body))
PY
gh api -X PATCH repos/{owner}/{repo}/code-scanning/alerts/{number} \
  --input /tmp/dismiss.json \
  -q '{state:.state,reason:.dismissed_reason}'
rm /tmp/dismiss.json
```

---

## 5. Open a PR

```bash
git add <changed files explicitly>
git commit -m "fix(security): <description>

Resolves CodeQL alerts #N, #M (rule: go/path-injection)."

git push -u origin fix/codeql-{rule-slug}

gh pr create \
  --base main \
  --head fix/codeql-{rule-slug} \
  --title "fix(security): <description>" \
  --body "..."
```

PR body: include a table mapping each alert number → rule → severity → what the fix does.
For dismissed false positives, document the reasoning in the PR body as an audit trail.

---

## 6. Verify Fixes Before Merge

**Do not rely only on a green CodeQL CI check.** A green check means no *new* alerts were introduced; it does not confirm the specific alerts you targeted are gone.
The definitive proof is querying alert instances on the PR merge ref.

### Check per-alert state on the PR merge ref

```bash
PRREF="refs/pull/{PR_NUMBER}/merge"

for n in 17 310 312 315 335 336; do
  st=$(gh api "repos/{owner}/{repo}/code-scanning/alerts/$n/instances?ref=$PRREF" \
        --jq '.[0].state' 2>/dev/null)
  echo "alert #$n -> ${st:-<no instance on this ref>}"
done
```

Expected for each fixed alert: `alert #N -> <no instance on this ref>`
"no instance on this ref" means CodeQL analyzed the PR code and did not find the pattern.

### Confirm CodeQL actually ran on the PR ref

First check a control alert (code unchanged) still has an instance — proving analysis ran:

```bash
gh api "repos/{owner}/{repo}/code-scanning/alerts/{unchanged_alert_number}/instances?ref=$PRREF" \
  --jq '.[0] | "state=\(.state)  loc=\(.location.path):\(.location.start_line)"'
```

Count analyses for the PR ref:

```bash
gh api "repos/{owner}/{repo}/code-scanning/analyses?ref=$PRREF&tool_name=CodeQL" \
  --jq 'length'
```

Should be ≥ 1.

### Main vs PR merge ref comparison table

```bash
PRREF="refs/pull/{PR_NUMBER}/merge"
printf "%-7s %-40s %-10s %-10s\n" "alert" "location" "main" "PRmerge"
for n in 17 310 312 315 335 336; do
  loc=$(gh api repos/{owner}/{repo}/code-scanning/alerts/$n \
        --jq '"\(.most_recent_instance.location.path):\(.most_recent_instance.location.start_line)"' 2>/dev/null)
  m=$(gh api "repos/{owner}/{repo}/code-scanning/alerts/$n/instances?ref=refs/heads/main" \
       --jq '.[0].state // "absent"' 2>/dev/null)
  p=$(gh api "repos/{owner}/{repo}/code-scanning/alerts/$n/instances?ref=$PRREF" \
       --jq '.[0].state // "absent"' 2>/dev/null)
  printf "#%-6s %-40s %-10s %-10s\n" "$n" "$loc" "$m" "$p"
done
```

Expected: fixed alerts show `open` under `main` and `absent` under `PRmerge`.

---

## 7. Post-Merge State Transition

After merging, CodeQL re-runs on the default branch.
Once that analysis completes, alerts absent on the PR ref automatically transition `open` → `fixed` (with `fixed_at` timestamp) in the security tab.
This flip is automatic — no manual action needed.
The per-ref proof above is the definitive evidence before the post-merge run completes.

---

## Common Mistakes

| Mistake | Fix |
|---|---|
| Treating a green CodeQL CI check as proof the alert is fixed | Query `.../instances?ref=refs/pull/{n}/merge` for each alert to confirm it is absent. |
| Fixing the sink without reading `.message.markdown` | The source (not the sink) determines the correct fix. Always read the markdown field first. |
| Mixing CodeQL and OSSF Scorecard alerts in the same fix pass | They need completely different strategies. Group by `.tool.name` first. |
| Long `dismissed_comment` (>~400 chars) sent as `-f` flag | State stays `open` silently. Use `--input` with a JSON file and keep comment under ~280 chars. |
| Forgetting `--paginate` | The API returns at most 30 alerts per page; partial results look complete. Always use `--paginate`. |
| An alert stays `open` on the dashboard after merge | CodeQL has not yet re-analyzed the default branch. Wait for the post-merge CI run. |
| Using `git add -A` in the worktree | Stage specific files explicitly. |

## Workflow Checklist

```
[ ] 1. Verify gh auth has security_events scope
[ ] 2. List open alerts; group by tool.name
[ ] 3. For each CodeQL alert: read .most_recent_instance.markdown to find source + sink
[ ] 4. Create git worktree for the fix branch (using-git-worktrees)
[ ] 5. Real findings: fix in code using CodeQL-recognized primitives at the sink
[ ] 6. False positives: prepare <280-char justification for dismiss
[ ] 7. Build, vet, lint, test locally — all green
[ ] 8. Dismiss false positives via PATCH API; verify state=dismissed
[ ] 9. Commit, push, open PR with alert table in body
[ ] 10. Wait for CodeQL CI check to pass on PR
[ ] 11. Query /instances?ref=refs/pull/{n}/merge for each fixed alert → "absent"
[ ] 12. Confirm analysis count >= 1 for the PR ref
[ ] 13. Merge; state transitions to "fixed" when default-branch CI re-runs
```
