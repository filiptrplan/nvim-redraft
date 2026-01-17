## 1. Configuration
- [x] 1.1 Add `diff_mode` option to config (default: `false`)
- [x] 1.2 Add `diff` keybinding config section with avante-style defaults

## 2. Diff Module
- [x] 2.1 Create `lua/nvim-redraft/diff.lua` module
- [x] 2.2 Implement conflict marker injection (<<<<<<, ======, >>>>>>)
- [x] 2.3 Implement conflict detection/parsing from buffer content
- [x] 2.4 Implement highlight extmarks for current/incoming regions
- [x] 2.5 Implement conflict resolution (choose ours/theirs/both/none)
- [x] 2.6 Implement conflict navigation (next/prev)
- [x] 2.7 Add state tracking for active conflicts per buffer

## 3. Integration
- [x] 3.1 Modify `edit()` to branch based on `diff_mode` config
- [x] 3.2 Register diff keybindings when conflicts are detected
- [x] 3.3 Clear keybindings when all conflicts resolved
- [x] 3.4 Define highlight groups in setup

## 4. Testing
- [x] 4.1 Add tests for conflict marker injection
- [x] 4.2 Add tests for conflict detection/parsing
- [x] 4.3 Add tests for resolution actions
- [x] 4.4 Add tests for config validation
