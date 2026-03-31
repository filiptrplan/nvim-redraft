## Why

Inline edits currently send only the visual selection and freeform instruction to the LLM. Users need a lightweight way to reference additional files without manually pasting their contents into the prompt.

## What Changes

- Add `@path/to/file` mentions in the instruction so extra files can be included as LLM context
- Add quoted-path support for files with spaces and skip invalid mentions instead of failing the edit
- Add Snacks-powered file autocomplete when typing `@`, while keeping manual mentions working with `vim.ui.input()` fallback

## Impact

- Affected specs: `visual-selection-editing`, `ai-llm-integration`
- Affected code: `lua/nvim-redraft.lua`, `lua/nvim-redraft/input.lua`, `lua/nvim-redraft/ipc.lua`, `ts/src/index.ts`, `ts/src/llm.ts`
