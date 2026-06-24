---
name: author-security-advisory
description: Use when triaging or preparing a GitHub repository security advisory as a maintainer (triggers "draft the advisory", "prepare GHSA content", "request CVE", "publish advisory"). Lists/triages advisories via the API and produces paste-ready GHSA form content; CVE-request and Publish are UI actions. Generic to any maintainer-owned repo.
---

# Author a GitHub Security Advisory (Maintainer Side)

**Request CVE and Publish are GitHub UI-only actions** — there is no REST or GraphQL endpoint for either.
Listing, reading, creating drafts, and updating metadata are all API-accessible.

## Auth Prerequisites

```bash
gh auth status
# Look for "security_events" in the scopes line
gh auth refresh -s security_events   # add if missing
```

The user must be a repository admin or security manager to see draft advisories and the "Request CVE" / "Publish" buttons.

---

## 1. List and Triage Existing Advisories (API)

```bash
# List all advisories — pick key fields
gh api repos/{owner}/{repo}/security-advisories --paginate \
  -q '.[] | {ghsa_id, state, severity, summary, published_at, updated_at, cve_id}'

# Get a single advisory in full
gh api repos/{owner}/{repo}/security-advisories/{GHSA-xxxx-xxxx-xxxx}

# Handy per-advisory summary
gh api repos/{owner}/{repo}/security-advisories/{GHSA-ID} -q '{
  state, severity, summary, description,
  cwes: [.cwes[].cwe_id],
  credits: [.credits[].user.login],
  cvss_v3: .cvss_severities.cvss_v3.vector_string,
  cvss_score: .cvss_severities.cvss_v3.score,
  vulnerabilities: [.vulnerabilities[] | {
    package: .package.name,
    affected: .vulnerable_version_range,
    patched: .patched_versions
  }]
}'

# Batch-check CVE assignment status
for id in GHSA-xxxx-xxxx-xxxx GHSA-yyyy-yyyy-yyyy; do
  printf "%-26s " "$id"
  gh api "repos/{owner}/{repo}/security-advisories/$id" \
    -q '"state=\(.state) cve=\(.cve_id // "PENDING") patched=\((.vulnerabilities[0].patched_versions // "—"))"'
done

# Check whether package/version fields are filled in
gh api "repos/{owner}/{repo}/security-advisories/{GHSA-ID}" | jq -r '
  "ecosystem:  \([.vulnerabilities[]?.package.ecosystem] | join(", "))",
  "package:    \([.vulnerabilities[]?.package.name] | join(", "))",
  "affected:   \([.vulnerabilities[]?.vulnerable_version_range] | join(" | "))",
  "patched:    \([.vulnerabilities[]?.patched_versions] | join(" | "))"
'
```

---

## 2. Create a Draft Advisory (API)

Reporters typically file a triage advisory via GitHub's "Report a vulnerability" button; the maintainer then fills it in.
Creation via API is supported for cases where the maintainer is initiating:

```bash
gh api repos/{owner}/{repo}/security-advisories \
  --method POST \
  --input - << 'EOF'
{
  "summary": "One-sentence title shown in advisory list",
  "description": "Full markdown body — see section 5 for shape",
  "severity": "critical",
  "cve_id": null,
  "vulnerabilities": [
    {
      "package": {
        "ecosystem": "go",
        "name": "github.com/owner/repo"
      },
      "vulnerable_version_range": "<= 1.23.0",
      "patched_versions": "1.24.0"
    }
  ],
  "cwe_ids": ["CWE-269", "CWE-284"],
  "credits": [
    { "login": "github-username", "type": "reporter" }
  ],
  "cvss_vector_string": "CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:C/C:H/I:H/A:H"
}
EOF
```

Valid `severity` values: `"low"`, `"medium"`, `"high"`, `"critical"`.
Valid `ecosystem` values: `"go"`, `"npm"`, `"pip"`, `"maven"`, `"nuget"`, `"rubygems"`, `"cargo"`, `"composer"`, `"hex"`, `"pub"`, `"erlang"`, `"actions"`, `"swift"`, `"rust"`, `"other"`.
Valid `credits[].type` values: `"reporter"`, `"finder"`, `"analyst"`, `"coordinator"`, `"remediation_developer"`, `"remediation_reviewer"`, `"remediation_verifier"`, `"tool"`, `"sponsor"`, `"other"`.

Notes:
- `cve_id` is always `null` at creation — GitHub's CNA assigns it later.
- `patched_versions` can be omitted while the fix PR is still open.
- The `credits[]` field returned by the API may be `[null]`; always fill credits from the GHSA UI edit page — the API does not expose reporter handles externally.
- Multiple affected packages go into the `vulnerabilities` array as separate objects.

---

## 3. Update a Draft Advisory (API)

```bash
GHSA="GHSA-xxxx-xxxx-xxxx"

gh api "repos/{owner}/{repo}/security-advisories/$GHSA" \
  --method PATCH \
  --input - << 'EOF'
{
  "summary": "Updated title",
  "description": "Updated description markdown",
  "severity": "high",
  "vulnerabilities": [
    {
      "package": { "ecosystem": "go", "name": "github.com/owner/repo" },
      "vulnerable_version_range": "<= 1.24.0",
      "patched_versions": "1.25.0"
    }
  ],
  "cwe_ids": ["CWE-22"],
  "cvss_vector_string": "CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:C/C:N/I:H/A:N"
}
EOF
```

Only supply the fields you want to change; omitted fields are unchanged.
You cannot PATCH state to `published` via the API — that is a UI-only action.
`patched_versions` and `vulnerable_version_range` must be updated together when a fix ships.

---

## 4. `vulnerable_version_range` Syntax

| Example | Meaning |
|---|---|
| `<= 1.23.0` | All versions up to and including 1.23.0 |
| `>= 1.0.0, < 1.7.0` | Range (regression introduced in 1.0.0, fixed in 1.7.0) |
| `< 1.7.0` | All versions before 1.7.0 |

`patched_versions` is the **first** non-vulnerable version (e.g. `1.24.0`, not `>= 1.24.0`).

---

## 5. Paste-Ready GHSA Form Content (the Main Output)

This is the primary deliverable.
Produce one file per advisory with a form-fields table, Description markdown, and Fix section, ready to copy-paste into the GitHub GHSA UI edit form.

See `reference/ghsa-form-template.md` for the paste-ready form structure (form-fields table, Description markdown, Fix section).

CVSS scoring guidance:
- Node/cluster escape: `S:C/C:H/I:H/A:H` → Critical (9.9)
- Cross-tenant secret theft: `S:C/C:H/I:N/A:N` or `S:U/C:H/I:H/A:N` → High (7.7–8.2)
- Missing validation, no demonstrated escalation path: Medium (4.3–6.5)

---

## 6. Local `.security-fixes/` Working Catalog

Use a local-only, never-committed `.security-fixes/` directory to track advisories in flight (master index of GHSA/state/CVE, cached advisory snapshots, and the paste-ready `.update.md` files).

---

## 7. Publishing Flow (State Machine)

```
triage → draft → published
(or triage → closed for duplicates/invalid)
```

### Step 1: Triage

Reporter files via "Report a vulnerability" → advisory starts in `triage` state; confirm/reproduce, plan fix.

```bash
gh api repos/{owner}/{repo}/security-advisories/{GHSA-ID}
# Confirm/reproduce, plan fix, update description via PATCH if needed.
```

Close a duplicate:

```bash
gh api "repos/{owner}/{repo}/security-advisories/{GHSA-duplicate}" \
  --method PATCH --input - <<'EOF'
{"state": "closed"}
EOF
```

### Step 2: Fix the code

Work in a branch.
PR description and commit message should reference the GHSA URL.

### Step 3: Fill in advisory metadata

Via API PATCH (everything except Credits):

```bash
gh api "repos/{owner}/{repo}/security-advisories/{GHSA-ID}" \
  --method PATCH \
  --input - << 'EOF'
{
  "summary": "Advisory title",
  "description": "Full markdown body",
  "severity": "high",
  "cvss_vector_string": "CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:C/C:H/I:N/A:N",
  "cwe_ids": ["CWE-22"],
  "vulnerabilities": [{
    "package": { "ecosystem": "go", "name": "github.com/owner/repo" },
    "vulnerable_version_range": "<= 1.24.0",
    "patched_versions": "1.25.0"
  }]
}
EOF
```

Credits **must** be added from the right-hand Credits panel in the GitHub UI — the API does not expose reporter handles.

### Step 4: Request CVE — GitHub UI only

**There is no API endpoint for this.**

In the GHSA edit page: right-hand sidebar → "Request CVE" button.
The button only appears on draft or published advisories (not triage).
The advisory must have `severity`, `cvss_vector_string`, `vulnerabilities[].package`, `vulnerable_version_range`, and `patched_versions` all set before the button appears.

### Step 5: Publish — GitHub UI only

**There is no API endpoint to set state=published.**

In the GHSA edit page: "Publish advisory" button (separate from "Request CVE").
Can be done before or after CVE is assigned.
Common order: Request CVE first → then Publish (or simultaneous).

Verify after publishing:

```bash
gh api repos/{owner}/{repo}/security-advisories/{GHSA-ID} -q '.state'
# Should return "published"
```

### Step 6: Wait for CVE assignment

CVEs are assigned by GitHub's CNA asynchronously — hours to a few days after publishing.

```bash
for id in GHSA-xxxx GHSA-yyyy; do
  echo "$id: $(gh api repos/{owner}/{repo}/security-advisories/$id -q '.cve_id // "no-CVE-yet"')"
done
```

GitHub emails the security manager when a CVE is assigned.

---

## 8. Linking Fix and Advisory

**In the fix PR description:**

```markdown
## Related security advisory

[GHSA-xxxx-xxxx-xxxx](https://github.com/{owner}/{repo}/security/advisories/GHSA-xxxx-xxxx-xxxx) — Title (CVSS score Severity).
```

**In the advisory Fix section:**

```markdown
Fixed in [v1.X.Y](https://github.com/{owner}/{repo}/releases/tag/v1.X.Y) by:

- [PR #NNN](https://github.com/{owner}/{repo}/pull/NNN)
  (commit [`abc12345`](https://github.com/{owner}/{repo}/commit/abc12345)) — What was changed.
```

**In git commit messages:**

```
Short title (GHSA-xxxx-xxxx-xxxx)

Detailed explanation of the fix.
```

---

## 9. Batch Publish Order (Multiple Advisories)

When publishing a batch:

1. **Wave A** (oldest, fix already in a prior release): publish first, request CVEs — these resolve fastest.
2. **Wave B** (recent round): publish after confirming fix is merged and release is tagged.
3. Within a wave: any order.
   Do all "Request CVE" clicks in one sitting.

The efficient UI loop: produce one advisory's complete form-fill block, maintainer fills the form, says "next", repeat for the next advisory.

---

## Common Mistakes

| Mistake | Fix |
|---|---|
| Calling an API to "Request CVE" or publish | No such endpoint for either. Click the button in the GitHub GHSA UI. |
| Missing CVSS score when clicking "Request CVE" | The button does not appear until `cvss_vector_string`, `severity`, `vulnerabilities[].package`, `vulnerable_version_range`, and `patched_versions` are all set. |
| Setting Credits via PATCH API | The API may return `[null]`. Credits must be filled from the right-hand panel in the GHSA UI. |
| Committing `.security-fixes/` to the repo | Keep this directory local-only. It may contain pre-disclosure details. Add to `.gitignore`. |
| Using `patched_versions: ">= 1.24.0"` | Use the exact first-fixed version: `"1.24.0"` (no operator). |
