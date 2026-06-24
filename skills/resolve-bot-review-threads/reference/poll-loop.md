# Combined CI + New-Thread Monitor Loop

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
