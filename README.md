# Claude Code Configuration
Custom configuration files for Claude Code harness, including statusline customization and settings overrides.

## Contents
- `statusline.sh` — Custom status line display script for Claude Code terminal output
- `settings.json` — Claude Code harness settings and hooks configuration
                                                                                                                                                                                                                                                                                                         
## Installation

1. **Copy files to your Claude Code config directory:**

   ```bash
     cp settings.json ~/.claude/settings.json
     cp statusline.sh ~/.claude/statusline.sh
     chmod +x ~/.claude/statusline.sh
   ```

2. Verify installation:
2. Restart Claude Code. Your custom statusline and settings should load automatically.

---
What These Do

`settings.json` - Configures Claude Code harness behavior: hooks, keybindings, model preferences, and tool settings.
`statusline.sh` - Renders a custom status line in your Claude Code terminal. Executed by the harness to display session info, task progress, and other context.

Customization

Edit settings.json to adjust:
- Model selection and defaults
- Hooks (pre/post-command automation)
- Keybindings
- Tool-specific options

Edit statusline.sh to customize what appears in your status display.
Both files are re-read on each Claude Code session start — no restart required.
