# Quick reference — Codecov coverage cheat-sheet

```bash
# Fetch combined coverage for main
curl -s "https://api.codecov.io/api/v2/github/<owner>/repos/<repo>/totals/?branch=main" -o /tmp/cov.json

# Fetch for a PR branch
curl -s "https://api.codecov.io/api/v2/github/<owner>/repos/<repo>/totals/?branch=<branch>" -o /tmp/cov_pr.json

# Local unit test + profile
go test -race -coverprofile=/tmp/cov.out ./pkg/mypackage/...
go tool cover -func=/tmp/cov.out | tail -1
go tool cover -func=/tmp/cov.out | grep " 0.0%"
go tool cover -html=/tmp/cov.out -o /tmp/cov.html

# Full suite (matches CI unittests flag)
go test -race -coverprofile=coverage.txt -covermode=atomic --coverpkg=./... ./...
go tool cover -func=coverage.txt | tail -1

# Merge integration covdata and convert
go tool covdata textfmt -i="covdata-raw,covdata-cli" -o=integration-coverage.txt
go tool cover -func=integration-coverage.txt | tail -1

# Validate before commit
golangci-lint run ./pkg/mypackage/...
go vet ./pkg/mypackage/...
```
