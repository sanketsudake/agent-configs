## NEVER EVER DO

These rules are ABSOLUTE:

### NEVER Publish Sensitive Data
- NEVER publish passwords, API keys, tokens to git/npm/docker
- Before ANY commit: verify no secrets included

### NEVER Commit .env Files
- NEVER commit `.env` to git
- ALWAYS verify `.env` is in `.gitignore`

## Markdown Style

### One sentence per line
- Within paragraphs, put each sentence on its own line.
- Why: CommonMark renders single newlines as spaces, so the rendered HTML is unchanged — but `git diff` becomes per-sentence and review is surgical.
- Applies to all markdown: blog posts, docs, READMEs, PR descriptions.
- Don't rewrap an entire paragraph just to add or reword one sentence.
- A reusable formatter lives at `$CLAUDE_CONFIG_DIR/scripts/md-one-sentence-per-line.py` (symlinked from this repo's `claude/scripts/`).
Run it on any markdown file (or batch) to enforce this.
It preserves frontmatter, fenced code, Hugo shortcodes, tables, headings, blockquote prefixes, list markers, and HTML comments.
