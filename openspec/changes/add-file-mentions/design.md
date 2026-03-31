## Context

The current request flow captures a visual selection and user instruction in Lua, sends them to the TypeScript service over JSON-RPC, and builds a provider-specific prompt from those two values. The LLM output is applied directly back onto the original selection, so any added context must remain reference-only.

## Goals / Non-Goals

- Goals:
  - Let users mention workspace files from the instruction with `@path`
  - Let users mention the current buffer with `@buffer`
  - Support quoted paths and duplicate elimination
  - Offer file autocomplete when `Snacks.nvim` is available
  - Keep fallback `vim.ui.input()` support for manual mentions
- Non-Goals:
  - Editing multiple files in one request
  - Adding a full project-indexing layer
  - Failing edits because one mention is invalid

## Decisions

- Decision: Parse and resolve mention tokens in Lua before the IPC request.
  - Alternatives considered: parsing in TypeScript only. Lua-side parsing keeps UI behavior, buffer-relative resolution, and autocomplete concerns together.
- Decision: Send structured file metadata to TypeScript and load file contents there.
  - Alternatives considered: reading file contents in Lua. TypeScript prompt assembly already centralizes provider formatting, token-boundary handling, and file-content labeling.
- Decision: Skip invalid or unreadable mentions instead of aborting the edit.
  - Alternatives considered: hard failures or interactive correction prompts. Skipping keeps the edit flow fast and matches the requested UX.
- Decision: Restrict live autocomplete to the Snacks path.
  - Alternatives considered: building a custom completion UI for `vim.ui.input()`. That would add more UI complexity than needed for the MVP.

## Risks / Trade-offs

- Large or binary files could bloat prompts -> skip unreadable files and cap included bytes per file
- Mention parsing can misread literal `@` -> support escaping with `\@`
- Prompt drift could make the model return more than the selected edit -> keep explicit labeled prompt sections and reinforce output constraints in the system prompt

## Migration Plan

1. Add spec deltas and tests for mention parsing
2. Add Lua mention parsing and IPC plumbing
3. Add TypeScript context loading and prompt assembly
4. Add Snacks autocomplete and update docs

## Open Questions

- None for MVP
