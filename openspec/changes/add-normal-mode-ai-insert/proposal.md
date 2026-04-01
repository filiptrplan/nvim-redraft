## Why

Visual-mode editing works well for replacing selected code, but there is no way to ask the model to generate code directly at the current cursor location. Adding a normal-mode insert flow makes the plugin useful for code generation and inline expansion without forcing users to preselect text.

## What Changes

- Add a normal-mode AI insert entrypoint with a default `<leader>ai` mapping
- Capture a default cursor-centered context window and send it to the LLM with an explicit cursor marker
- Insert the returned code at the saved cursor position instead of replacing a visual selection
- Keep visual-mode edit behavior unchanged, including diff-mode handling for selection edits

## Impact

- Affected specs: `cursor-context-insertion`
- Affected code: `lua/nvim-redraft.lua`, `lua/nvim-redraft/selection.lua`, `lua/nvim-redraft/replace.lua`, tests, and docs
