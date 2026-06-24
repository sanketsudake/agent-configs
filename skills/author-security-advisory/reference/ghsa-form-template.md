# Paste-Ready GHSA Form Content

**File format (`.security-fixes/GHSA-xxxx-xxxx-xxxx.update.md`):**

```markdown
# GHSA-xxxx-xxxx-xxxx — paste-ready update

URL: https://github.com/{owner}/{repo}/security/advisories/GHSA-xxxx-xxxx-xxxx → Edit

## Form fields

| Field | Value |
| --- | --- |
| **Title** | Full advisory title |
| **Ecosystem** | Go (`github.com/owner/repo`) |
| **Affected versions** | `<= 1.24.0` |
| **Patched versions** | `1.25.0` |
| **Severity** | High |
| **CVSS v3.1** | `CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:C/C:H/I:H/A:N` (7.7 High) |
| **CWE** | CWE-22 Improper Limitation of a Pathname to a Restricted Directory |
| **Credits** | *FILL IN from GHSA UI* |

## Description (paste into the form's Description field)

### Summary

One-paragraph overview of what is vulnerable and what an attacker can do.

### Details

**Root cause.** Explain the exact code path. Reference specific files + line numbers.

**Attack path.** Concrete steps: RBAC needed, API call made, result.

#### Proof of Concept

    [Minimal reproducer]

### Impact

Who is affected, what is the blast radius, what security boundary is broken.

## Fix (paste into the Fix field)

Fixed in [vX.Y.Z](release-link) by:

- [PR #NNN](pr-link) (commit [`sha`](sha-link)) — what was done

## Reviewer / publish checklist

- [ ] Confirm `Affected versions` is `<= X.Y.Z`
- [ ] Set `Patched versions` to `A.B.C`
- [ ] Paste Description
- [ ] Paste Fix section
- [ ] Fill in Credits in the UI
- [ ] Request CVE  (GitHub UI — right-hand sidebar)
- [ ] Publish once release is tagged  (GitHub UI — separate button)
```
