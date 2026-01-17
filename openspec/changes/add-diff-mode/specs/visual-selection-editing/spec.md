## ADDED Requirements

### Requirement: Diff Mode Configuration
The system SHALL support a `diff_mode` configuration option that controls whether AI edits are auto-applied or shown as reviewable diffs.

#### Scenario: Diff mode disabled (default)
- **WHEN** `diff_mode` is `false` or not set
- **THEN** AI edits are applied immediately to the buffer (current behavior)

#### Scenario: Diff mode enabled
- **WHEN** `diff_mode` is `true`
- **THEN** AI edits are shown as conflict markers requiring user resolution

### Requirement: Conflict Marker Injection
The system SHALL inject git-style conflict markers when diff mode is enabled, showing original and AI-generated code side by side.

#### Scenario: Markers injected after AI response
- **WHEN** diff mode is enabled and AI returns edited code
- **THEN** buffer content at selection is replaced with conflict markers:
  ```
  <<<<<<< Current
  [original selected code]
  =======
  [AI generated code]
  >>>>>>> Incoming
  ```

#### Scenario: Markers preserve surrounding content
- **WHEN** conflict markers are injected
- **THEN** code before and after the original selection remains unchanged

### Requirement: Conflict Highlighting
The system SHALL highlight conflict regions using extmarks to visually distinguish current vs incoming changes.

#### Scenario: Current changes highlighted
- **WHEN** conflict markers are present
- **THEN** the "current" region (original code) is highlighted with `NvimRedraftCurrent` highlight group

#### Scenario: Incoming changes highlighted
- **WHEN** conflict markers are present
- **THEN** the "incoming" region (AI code) is highlighted with `NvimRedraftIncoming` highlight group

### Requirement: Conflict Resolution Actions
The system SHALL provide keybindings to resolve conflicts by choosing which version to keep.

#### Scenario: Choose ours (reject AI)
- **WHEN** cursor is within a conflict and user presses `co`
- **THEN** the original code is kept, AI code and markers are removed

#### Scenario: Choose theirs (accept AI)
- **WHEN** cursor is within a conflict and user presses `ct`
- **THEN** the AI code is kept, original code and markers are removed

#### Scenario: Choose both
- **WHEN** cursor is within a conflict and user presses `cb`
- **THEN** both versions are kept (original above AI), markers are removed

#### Scenario: Resolution preserves undo
- **WHEN** user resolves a conflict
- **THEN** the resolution can be undone with a single `u` command

### Requirement: Conflict Navigation
The system SHALL provide keybindings to navigate between multiple conflicts in a buffer.

#### Scenario: Jump to next conflict
- **WHEN** user presses `]x` and conflicts exist after cursor
- **THEN** cursor moves to the start of the next conflict

#### Scenario: Jump to previous conflict
- **WHEN** user presses `[x` and conflicts exist before cursor
- **THEN** cursor moves to the start of the previous conflict

#### Scenario: No more conflicts
- **WHEN** user navigates and no conflicts exist in that direction
- **THEN** cursor position is unchanged

### Requirement: Conflict Keybinding Lifecycle
The system SHALL register conflict keybindings only when conflicts are active and clean up when resolved.

#### Scenario: Keybindings registered on conflict
- **WHEN** conflict markers are injected into buffer
- **THEN** resolution keybindings (`co`, `ct`, `cb`, `]x`, `[x`) are registered for that buffer

#### Scenario: Keybindings cleared on resolution
- **WHEN** all conflicts in a buffer are resolved
- **THEN** conflict keybindings are removed from that buffer

#### Scenario: Multiple conflicts supported
- **WHEN** multiple AI edits create multiple conflicts
- **THEN** user can navigate between and resolve each independently
