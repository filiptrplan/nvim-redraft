# visual-selection-editing Delta Specification

## MODIFIED Requirements

### Requirement: User Instruction Prompt
The system SHALL display an input prompt to collect editing instructions from the user, using Snacks.nvim when available or vim.ui.input as fallback.

#### Scenario: User provides instruction with Snacks
- **WHEN** selection is captured, Snacks.nvim is available, and Snacks.input prompt is shown
- **THEN** user can type natural language instructions with enhanced styling and submit with Enter

#### Scenario: User provides instruction without Snacks
- **WHEN** selection is captured, Snacks.nvim is not available, and vim.ui.input prompt is shown
- **THEN** user can type natural language instructions and submit with Enter

#### Scenario: User cancels prompt with Snacks
- **WHEN** user presses Escape or provides empty input in Snacks.input
- **THEN** the input closes and the operation is cancelled with no changes made

#### Scenario: User cancels prompt without Snacks
- **WHEN** user presses Escape or provides empty input in vim.ui.input
- **THEN** the input closes and the operation is cancelled with no changes made

#### Scenario: Input positioning with Snacks
- **WHEN** Snacks.nvim is available and input prompt is displayed
- **THEN** the input appears relative to cursor position with configured styling (icon, title, border)

#### Scenario: Input positioning without Snacks
- **WHEN** Snacks.nvim is not available and input prompt is displayed
- **THEN** vim.ui.input shows at the command line with prompt text only

#### Scenario: Mention autocomplete with Snacks
- **WHEN** user types `@` while entering an instruction in the Snacks.nvim prompt
- **THEN** a file picker can be used to insert a workspace-relative path mention into the prompt

## ADDED Requirements

### Requirement: Additional Context File Mentions
The system SHALL allow users to mention extra files in the edit instruction so their contents can be added as reference context for the LLM.

#### Scenario: Mention a workspace file
- **WHEN** the instruction contains a valid `@path/to/file` mention
- **THEN** the mention is resolved to a file reference and included in the AI request context

#### Scenario: Mention a file with spaces
- **WHEN** the instruction contains a quoted mention such as `@"docs/my file.md"`
- **THEN** the full quoted path is resolved as a single file reference

#### Scenario: Invalid mention is skipped
- **WHEN** the instruction contains a missing, unreadable, or disallowed file mention
- **THEN** that mention is ignored and the edit continues with any remaining valid context

#### Scenario: Duplicate mentions are deduplicated
- **WHEN** the instruction mentions the same file multiple times
- **THEN** the file is included at most once in the AI request context

#### Scenario: Mention the current buffer
- **WHEN** the instruction contains `@buffer`
- **THEN** the current buffer contents are included in the AI request context as an additional reference source
