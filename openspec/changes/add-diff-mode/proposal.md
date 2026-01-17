## Why
Users need to review AI-generated code changes before applying them. Current behavior auto-applies changes immediately, which is risky for production code. A diff preview mode lets users accept or reject changes using familiar git conflict resolution UX.

## What Changes
- Add `diff_mode` config option (default: `false` to preserve current behavior)
- When `diff_mode = true`, inject git-style conflict markers instead of auto-replacing
- Highlight original (current) and AI-generated (incoming) code regions
- Add keybindings for conflict resolution: `co` (ours), `ct` (theirs), `cb` (both), `]x`/`[x` (navigation)
- Track conflict state and clean up markers on resolution

## Impact
- Affected specs: `visual-selection-editing`
- Affected code: `lua/nvim-redraft.lua`, new `lua/nvim-redraft/diff.lua` module
- New highlight groups: `NvimRedraftCurrent`, `NvimRedraftIncoming`
