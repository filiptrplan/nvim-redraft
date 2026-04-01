## ADDED Requirements

### Requirement: Cursor Context Capture
The system SHALL capture local code context around the cursor when the user triggers AI insert from normal mode.

#### Scenario: Default context window
- **WHEN** user triggers AI insert in normal mode
- **THEN** the request includes the current line plus up to 30 lines above and 30 lines below the cursor, clipped by file boundaries

#### Scenario: Cursor marker placement
- **WHEN** the system serializes the cursor context for the AI request
- **THEN** it inserts an explicit cursor marker at the exact cursor column within the captured text

### Requirement: Normal Mode AI Insert
The system SHALL provide a normal-mode AI insertion flow that inserts generated code at the saved cursor position.

#### Scenario: Successful insertion
- **WHEN** AI service returns generated code for a normal-mode insert request
- **THEN** the returned text is inserted at the original cursor position without replacing surrounding code

#### Scenario: Empty response
- **WHEN** AI service returns an empty string for a normal-mode insert request
- **THEN** no surrounding code is removed and the operation completes without replacing existing text

### Requirement: Normal Mode Keybinding
The system SHALL register a configurable normal-mode keybinding for AI insertion.

#### Scenario: Default keybinding
- **WHEN** plugin is loaded with default configuration
- **THEN** `<leader>ai` in normal mode triggers the AI insert flow

#### Scenario: Custom keybinding
- **WHEN** user configures a custom keybinding entry in `setup({ keys = ... })`
- **THEN** the custom normal-mode insert keybinding triggers the AI insert flow instead of the default one

### Requirement: Diff Mode Bypass For Insert
The system SHALL apply normal-mode insert results directly even when diff mode is enabled.

#### Scenario: Diff mode enabled during insert
- **WHEN** `diff_mode` is enabled and user triggers AI insert in normal mode
- **THEN** the generated code is inserted directly at the saved cursor position and no conflict markers are created

### Requirement: Insert Failure Handling
The system SHALL preserve the original buffer content and notify users when normal-mode insert requests fail.

#### Scenario: API failure during insert
- **WHEN** AI service returns an error for a normal-mode insert request
- **THEN** the original buffer content remains unchanged and an error is displayed via `vim.notify`
