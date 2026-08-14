# kmos Codex Session Preferences

- At the start of a kmos Codex session, summarize the previous session in one short paragraph, then ask whether to resume that work or start fresh.
- Every 5 user prompts in a session, run `/status` if available. If slash commands are not available, report the same practical status information manually: current session id when known, cwd, git branch, git status summary, and current task focus.
