# Using Multiple Claude Accounts with Claude Code
#
# Reference: https://github.com/anthropics/claude-code/issues/261#issuecomment-3071151276
#
# Claude Code uses CLAUDE_CONFIG_DIR to determine which config/profile to use.
# By setting different config directories, you can maintain separate accounts
# (e.g., personal and work) without conflicts.
#
# Add the following to your shell profile (~/.zprofile, ~/.bashrc, etc.):

_claude_with_profile() {
  export CLAUDE_CONFIG_DIR="$1"
  command claude "${@:2}"
}

# Personal profile
pclaude() {
  _claude_with_profile "$HOME/.claude-personal" "$@"
}

# Work profile
wclaude() {
  _claude_with_profile "$HOME/.claude-work" "$@"
}

# Prompt to choose profile when invoking plain `claude`
claude() {
  echo "Which Claude account do you want to use?"
  echo "  1) pclaude (Personal)"
  echo "  2) wclaude (Work)"
  read -r "choice?Select [1/2]: "
  case "$choice" in
    1|p) pclaude "$@" ;;
    2|w) wclaude "$@" ;;
    *) echo "Invalid choice. Aborting." ; return 1 ;;
  esac
}

# Usage:
#   pclaude              # Launch with personal account
#   wclaude              # Launch with work account
#   claude               # Prompts you to pick an account
#   pclaude --resume     # Resume last session with personal account
