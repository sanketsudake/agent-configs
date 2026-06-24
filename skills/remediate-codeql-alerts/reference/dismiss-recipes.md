# Dismiss Recipes

## Long-comment workaround

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
