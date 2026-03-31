# ai-llm-integration Delta Specification

## ADDED Requirements

### Requirement: Mentioned File Context
The system SHALL include resolved file mentions as labeled reference context in LLM edit requests without changing the replacement target.

#### Scenario: Request includes mentioned file context
- **WHEN** the Lua client sends resolved context file metadata with an edit request
- **THEN** the TypeScript service loads those files and appends their contents to the prompt as labeled reference context

#### Scenario: Edit target remains the visual selection
- **WHEN** the prompt includes additional mentioned file context
- **THEN** the model is still instructed to return only the edited replacement for the selected code

#### Scenario: Unreadable or oversized file is skipped
- **WHEN** a resolved context file cannot be read safely by the TypeScript service
- **THEN** that file is omitted from the prompt and the edit continues with remaining context

#### Scenario: Current buffer content is sent inline
- **WHEN** the Lua client resolves `@buffer`
- **THEN** the current buffer text is included directly in the edit request so unsaved changes are available as LLM context
