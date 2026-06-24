---
name: resolve-bot-review-threads
description: Use when a PR has bot/Copilot review comments to clear — fix them, mark the threads resolved, and re-request the bot until the PR is at a good base (triggers "resolve copilot comments", "mark review threads resolved", "re-request copilot review"). Generic to any GitHub repo with bot reviewers.
---

# Resolve Bot Review Threads

## Overview

Bot reviewers (e.g. Copilot) post review threads on PRs as GraphQL `reviewThread` nodes.
Resolving them requires the GraphQL API — REST has no resolve endpoint, and REST's `requested_reviewers` rejects bot accounts.
This skill covers the full loop: list → fix → resolve → re-request → poll.

## Ordering Rule

Fix first, then resolve. Never resolve a thread before the code change has landed on the branch.

```
git push origin BRANCH
  → resolve threads whose fix just landed (GraphQL mutation)
  → optionally reply to explain the fix
  → re-request the bot (GraphQL mutation, botIds)
  → poll CI + watch for new bot review (pairs with watch-ci)
  → repeat until CI green + no unresolved bot threads
```

After ~3 passes where each new review surfaces only re-flags of intentional design decisions (not new actionable changes), stop iterating and confirm with the user before continuing.

---

## 1. List Unresolved Threads

### Basic listing (thread ID, author, file path)

```bash
gh api graphql -f query='
query($owner:String!,$repo:String!,$pr:Int!){
  repository(owner:$owner,name:$repo){
    pullRequest(number:$pr){
      reviewThreads(first:100){
        nodes{ id isResolved comments(first:1){ nodes{ author{login} path body } } }
      }
    }
  }
}' -f owner=OWNER -f repo=REPO -F pr=PR_NUMBER \
  | jq -r '.data.repository.pullRequest.reviewThreads.nodes[]
    | select(.isResolved==false)
    | "\(.id)\t\(.comments.nodes[0].author.login)\t\(.comments.nodes[0].path)"'
```

### Full detail listing (id, path, line, body snippet)

```bash
gh api graphql -f query='
query($owner:String!,$repo:String!,$pr:Int!){
  repository(owner:$owner,name:$repo){
    pullRequest(number:$pr){
      reviewThreads(first:100){
        nodes{
          id isResolved isOutdated path line
          comments(first:5){ nodes{ author{login} body createdAt } }
        }
      }
    }
  }
}' -f owner=OWNER -f repo=REPO -F pr=PR_NUMBER \
  | jq -r '.data.repository.pullRequest.reviewThreads.nodes[]
    | select(.isResolved==false)
    | "===\nthread=\(.id)\noutdated=\(.isOutdated)\n\(.comments.nodes[] | "[\(.author.login) @ \(.createdAt)] \(.path)\n\(.body)\n")"'
```

### Filter to bot-only threads (e.g. login contains "copilot")

```bash
gh api graphql -f query='
query($o:String!,$r:String!,$pr:Int!){
  repository(owner:$o,name:$r){
    pullRequest(number:$pr){
      reviewThreads(first:80){
        nodes{ id isResolved path line
          comments(first:1){ nodes{ author{login} body } }
        }
      }
    }
  }
}' -f o=OWNER -f r=REPO -F pr=PR_NUMBER \
  | jq -r '.data.repository.pullRequest.reviewThreads.nodes[]
    | select(.isResolved==false)
    | select(.comments.nodes[0].author.login | test("[Cc]opilot"))
    | "\(.id)\t\(.path):\(.line)\t\(.comments.nodes[0].body[0:60])"'
```

### Pagination

The queries above use `first:100`. For very large PRs add cursor pagination:

```graphql
reviewThreads(first:100, after: $cursor){
  pageInfo{ hasNextPage endCursor }
  nodes{ ... }
}
```

Loop until `pageInfo.hasNextPage == false`.

### Key thread node fields

| Field | Meaning |
|---|---|
| `id` | `PRRT_kwDO…` — the node ID required by the resolve mutation |
| `isResolved` | boolean |
| `isOutdated` | true when the diff line no longer exists in the current head |
| `path` | file path |
| `line` | line number |
| `comments(first:N)` | nested comment nodes: `author.login`, `body`, `createdAt` |

---

## 2. Resolve Threads

### Resolve a single thread

```bash
gh api graphql \
  -f query='mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{id isResolved}}}' \
  -f id=PRRT_kwDO... \
  | jq -c '.data.resolveReviewThread.thread'
```

### Resolve multiple threads in a loop

```bash
for tid in PRRT_kwDO...A PRRT_kwDO...B PRRT_kwDO...C; do
  gh api graphql \
    -f query='mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{id isResolved}}}' \
    -f id="$tid" \
    | jq -c '.data.resolveReviewThread.thread // .errors'
done
```

### Inline helper pattern

```bash
resolve () {
  gh api graphql \
    -f query='mutation($t:ID!){resolveReviewThread(input:{threadId:$t}){thread{isResolved}}}' \
    -f t="$1" \
    --jq '"resolved="+(.data.resolveReviewThread.thread.isResolved|tostring)' 2>&1
}
resolve PRRT_kwDO...A
resolve PRRT_kwDO...B
```

---

## 3. Optional Reply Before Resolving

Not required — "just resolve" is the default. Reply only when the fix needs explanation:

```bash
reply_resolve () {
  local tid="$1" body="$2"
  gh api graphql \
    -f query='mutation($t:ID!,$b:String!){addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$t,body:$b}){comment{id}}}' \
    -f t="$tid" -f b="$body" >/dev/null 2>&1 && echo "  replied $tid"
  gh api graphql \
    -f query='mutation($t:ID!){resolveReviewThread(input:{threadId:$t}){thread{isResolved}}}' \
    -f t="$tid" \
    --jq '.data.resolveReviewThread.thread.isResolved' 2>&1 | sed 's/^/  resolved=/'
}

# Usage:
reply_resolve 'PRRT_kwDO...' 'Fixed in <SHA> — explanation of what changed.'
```

**Field name difference:** `addPullRequestReviewThreadReply` takes `pullRequestReviewThreadId` (the full name), while `resolveReviewThread` takes `threadId` (short form). They are different input objects — do not swap them.

---

## 4. Re-request Bot Review

### Get the PR node ID

REST uses integer PR numbers; the `requestReviews` mutation needs the GraphQL `PR_kwDO…` node ID.

```bash
# Method A: REST (simplest)
gh api repos/OWNER/REPO/pulls/PR_NUMBER -q .node_id

# Method B: GraphQL
gh api graphql \
  -f query='{ repository(owner:"OWNER",name:"REPO"){ pullRequest(number:PR_NUMBER){ id } } }' \
  --jq '.data.repository.pullRequest.id'

# Method C: gh CLI (newer versions)
gh pr view PR_NUMBER --json id -q .id
```

### Discover the bot node ID

Bot node IDs rotate when GitHub updates the integration. Rediscover at the start of each session.

**Approach 1 — from an existing review on a recent PR (fastest):**

```bash
gh api graphql \
  -f query='{
    repository(owner:"OWNER",name:"REPO"){
      pullRequest(number:PR_NUMBER_THAT_WAS_REVIEWED){
        reviews(first:20){
          nodes{ author{ login ... on Bot { id } ... on User { id } } }
        }
      }
    }
  }' \
  --jq '.data.repository.pullRequest.reviews.nodes[]
    | select(.author.login=="copilot-pull-request-reviewer")
    | .author.id' | head -1
```

**Approach 2 — suggestedActors on the repo:**

```bash
gh api graphql \
  -f query='{
    repository(owner:"OWNER",name:"REPO"){
      suggestedActors(capabilities:[CAN_BE_ASSIGNED], first:30){
        nodes{ __typename ... on Bot { id login } }
      }
    }
  }' \
  | jq '.data.repository.suggestedActors.nodes[]
    | select(.login | test("[Cc]opilot"; "i"))'
```

### Request review mutation

**Use `botIds`, not `userIds`.** Passing a bot's node ID under `userIds` returns `NOT_FOUND`.

```bash
nid=$(gh pr view PR_NUMBER -R OWNER/REPO --json id -q .id)
gh api graphql \
  -f query='mutation($pid:ID!,$bot:ID!){
    requestReviews(input:{pullRequestId:$pid, botIds:[$bot], union:true}){
      pullRequest{ number }
    }
  }' \
  -f pid="$nid" \
  -f bot="BOT_kgDO..." \
  --jq '.data.requestReviews.pullRequest.number' \
  | sed 's/^/Bot review requested on #/'
```

`union:true` adds to the existing reviewer set rather than replacing it.
The mutation is idempotent — running it multiple times on the same PR+bot is safe.

---

## 5. Poll CI and Monitor New Threads

Use the `watch-ci` skill for CI polling.

Combined CI + new thread monitoring loop (stops when all CI checks settle):

```bash
prev_ci=""
prev_threads=""
for i in $(seq 1 80); do
  s=$(gh pr checks PR_NUMBER --repo OWNER/REPO --json name,bucket,state 2>/dev/null || echo "[]")
  if [ "$s" != "[]" ]; then
    cur=$(echo "$s" | jq -r '.[] | select(.bucket!="pending") | "[CI] \(.name): \(.bucket) (\(.state))"' | sort -u)
    comm -13 <(echo "$prev_ci") <(echo "$cur")
    prev_ci="$cur"
  fi
  t=$(gh api graphql \
    -f query='query($owner:String!,$repo:String!,$pr:Int!){
      repository(owner:$owner,name:$repo){
        pullRequest(number:$pr){
          reviewThreads(first:50){
            nodes{id isResolved comments(first:1){nodes{author{login} path body}}}
          }
        }
      }
    }' -f owner=OWNER -f repo=REPO -F pr=PR_NUMBER 2>/dev/null || echo "{}")
  curt=$(echo "$t" | jq -r '
    .data.repository.pullRequest.reviewThreads.nodes[]?
    | select(.isResolved==false)
    | select(.comments.nodes[0].author.login | test("[Cc]opilot"))
    | "[COPILOT] \(.id) @ \(.comments.nodes[0].path)"
  ' 2>/dev/null | sort -u)
  comm -13 <(echo "$prev_threads") <(echo "$curt")
  prev_threads="$curt"
  if echo "$s" | jq -e 'length>0 and all(.[]; .bucket!="pending")' >/dev/null 2>&1; then
    echo "ALL_CI_SETTLED"
    break
  fi
  sleep 30
done
```

### Final status check

```bash
echo "=== unresolved thread count ==="
gh api graphql \
  -f query='query($o:String!,$r:String!,$pr:Int!){
    repository(owner:$o,name:$r){
      pullRequest(number:$pr){ reviewThreads(first:80){ nodes{ isResolved } } }
    }
  }' -f o=OWNER -f r=REPO -F pr=PR_NUMBER \
  | jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved==false)] | length'

echo "=== latest bot review state ==="
gh api repos/OWNER/REPO/pulls/PR_NUMBER/reviews \
  | jq '[.[] | select(.user.login | test("[Cc]opilot"))] | last | {state, submitted_at, body_preview: .body[0:200]}'

echo "=== mergeable ==="
gh pr view PR_NUMBER --json mergeable,mergeStateStatus \
  | jq '"mergeable=\(.mergeable) state=\(.mergeStateStatus)"'
```

## Common Mistakes

| Mistake | Fix |
|---|---|
| Passing bot node ID under `userIds` | Use `botIds`. Bot IDs under `userIds` return `NOT_FOUND`. |
| Using `gh pr edit --add-reviewer <bot-login>` | This silently drops the assignment. Use the `requestReviews` mutation. |
| `POST .../pulls/PR/requested_reviewers` with a bot login | Returns 422 "not a collaborator". REST rejects bot accounts here. |
| Hardcoding the bot node ID across sessions | Bot IDs rotate on GitHub integration updates. Rediscover each session via approach 1 or 2. |
| Using `threadId` in the reply mutation | The reply mutation uses `pullRequestReviewThreadId`. Only the resolve mutation uses `threadId`. |
| Bulk-resolving all unresolved threads | Only resolve threads where the fix actually landed or the suggestion is intentionally rejected (with a reply documenting why). |
| Resolving before pushing the fix | Push first, then resolve. |
| Treating `isOutdated: true` threads as blocking | Outdated threads can be resolved without a code fix — the line no longer exists. |

## Auth

`gh auth` must have `repo` scope (the default for `gh auth login`).
The `resolveReviewThread` and `requestReviews` mutations require write access to the PR repository.
The node IDs involved (`PRRT_kwDO…`, `PR_kwDO…`, `BOT_kgDO…`) are GraphQL-only — they are not available or accepted by the REST API.
