# kmos Session Preferences

- At the start of a kmos Codex session, summarize the previous session in one short paragraph, then ask whether to resume that work or start fresh.
- Every 5 user prompts in a session, run `/status` if available. If slash commands are not available, report the same practical status information manually: current session id when known, cwd, git branch, git status summary, and current task focus.
- All user-facing scripts must be runnable as `./script.sh`, without telling the user to prefix them with `sudo`. If root is needed, request it inside the script at runtime using the system `sudo` prompt, preserve the script's arguments, and skip escalation when already root. Never collect, pass through arguments, or store the user's sudo password yourself. Show help without escalating when the script supports `--help`. Tools that need root only for an operation may call `sudo` for that operation instead of restarting the whole script.
- Keep executable entry-point and test scripts executable in the filesystem and Git. Check file modes after moving or editing scripts.
- Prefer tools already installed on a kmos host. Do not add a new host package dependency without explaining why and asking the user first.
- Destructive media tools should detect eligible devices and ask the user to confirm the target interactively by default; a `--device` argument must not be required for normal use.
