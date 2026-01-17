# nvim-redraft

A Neovim plugin for AI-powered inline code editing with support for multiple LLM providers (OpenAI, Anthropic, xAI, GitHub Copilot, OpenRouter, Cerebras).

https://github.com/user-attachments/assets/4124e8e5-27ce-4628-b005-e0d7b65a1392

## Features

- Select code in visual mode and apply AI edits inline
- No confirmation dialogs - seamless editing experience
- Switch between multiple LLM providers and models on the fly
- Customizable system prompts and keybindings
- Built with Lua and TypeScript for optimal performance
- **Diff mode**: Review AI changes as git-style conflict markers before applying

## Installation

### Prerequisites

- Neovim >= 0.8.0
- Node.js >= 18.0.0
- API key for at least one supported provider ([OpenAI](https://platform.openai.com/api-keys), [Anthropic](https://console.anthropic.com/), [xAI](https://console.x.ai/), [OpenRouter](https://openrouter.ai/), [Cerebras](https://cloud.cerebras.ai/))
- For GitHub Copilot: [copilot.lua](https://github.com/zbirenbaum/copilot.lua) installed and authenticated

**Optional but recommended:**
- [Snacks.nvim](https://github.com/folke/snacks.nvim) - Enhanced input UI with icons and custom styling. Without it, the plugin uses `vim.ui.input()` for prompts.

### lazy.nvim

**Basic installation (no dependencies):**

```lua
{
  "jim-at-jibba/nvim-redraft",
  event = "VeryLazy",
  build = "cd ts && npm install && npm run build",
  opts = {
    -- See Configuration section for options
  },
}
```

**With Snacks.nvim (recommended for enhanced UI):**

```lua
{
  "jim-at-jibba/nvim-redraft",
  dependencies = {
    { "folke/snacks.nvim", opts = { input = {} } },
  },
  event = "VeryLazy",
  build = "cd ts && npm install && npm run build",
  opts = {
    -- See Configuration section for options
  },
}
```

### packer.nvim

**Basic installation (no dependencies):**

```lua
use {
  "jim-at-jibba/nvim-redraft",
  config = function()
    require("nvim-redraft").setup()
  end,
  run = "cd ts && npm install && npm run build",
}
```

**With Snacks.nvim (recommended for enhanced UI):**

```lua
use {
  "folke/snacks.nvim",
  config = function()
    require("snacks").setup({ input = {} })
  end,
}

use {
  "jim-at-jibba/nvim-redraft",
  requires = { "folke/snacks.nvim" },
  config = function()
    require("nvim-redraft").setup()
  end,
  run = "cd ts && npm install && npm run build",
}
```

## Quick Start

1. Set your API key(s) in your shell profile:

```bash
export OPENAI_API_KEY="your-openai-api-key"
export ANTHROPIC_API_KEY="your-anthropic-api-key"
export XAI_API_KEY="your-xai-api-key"
export OPENROUTER_API_KEY="your-openrouter-api-key"
export CEREBRAS_API_KEY="your-cerebras-api-key"
```

**GitHub Copilot:** No API key needed! If you have [copilot.lua](https://github.com/zbirenbaum/copilot.lua) installed and authenticated, the plugin automatically extracts your token.

2. Select code in visual mode (`v`, `V`, or `Ctrl-v`)
3. Press `<leader>ae` and enter your instruction
4. The AI applies changes inline

### Example

Select this code:

```javascript
function add(a, b) {
  return a + b
}
```

Press `<leader>ae` and type: "add JSDoc comments"

Result:

```javascript
/**
 * Adds two numbers together
 * @param {number} a - First number
 * @param {number} b - Second number
 * @returns {number} Sum of a and b
 */
function add(a, b) {
  return a + b
}
```

## Configuration

### Multiple Models (Recommended)

Configure multiple provider/model combinations and switch between them with `<leader>am`:

```lua
require("nvim-redraft").setup({
  llm = {
    models = {
      { provider = "openai", model = "gpt-4o-mini", label = "GPT-4o Mini" },
      { provider = "openai", model = "gpt-4o", label = "GPT-4o" },
      { provider = "anthropic", model = "claude-3-5-sonnet-20241022", label = "Claude 3.5 Sonnet" },
      { provider = "xai", model = "grok-4-fast-non-reasoning", label = "Grok 4 Fast" },
      { provider = "copilot", model = "gpt-4o", label = "Copilot GPT-4o" },
      { provider = "openrouter", model = "anthropic/claude-3.5-sonnet", label = "OpenRouter Claude" },
      { provider = "cerebras", model = "qwen-3-235b-a22b-instruct-2507", label = "Cerebras Qwen" },
    },
    default_model_index = 1,
  },
})
```

The `label` field is optional - defaults to `"provider: model"`.

### Single Provider

```lua
require("nvim-redraft").setup({
  llm = {
    provider = "openai",  -- "openai", "anthropic", "xai", "copilot", "openrouter", or "cerebras"
    model = "gpt-4o-mini",
  },
})
```

Default models: `gpt-4o-mini` (OpenAI), `claude-3-5-sonnet-20241022` (Anthropic), `grok-4-fast-non-reasoning` (xAI), `gpt-4o` (Copilot), `anthropic/claude-3.5-sonnet` (OpenRouter), `qwen-3-235b-a22b-instruct-2507` (Cerebras).

### GitHub Copilot Setup

GitHub Copilot requires [copilot.lua](https://github.com/zbirenbaum/copilot.lua) to be installed and authenticated:

1. Install copilot.lua:

```lua
-- lazy.nvim
{
  "zbirenbaum/copilot.lua",
  cmd = "Copilot",
  event = "InsertEnter",
  config = function()
    require("copilot").setup({
      suggestion = { enabled = false },
      panel = { enabled = false },
    })
  end,
}
```

2. Authenticate with GitHub:
   - Run `:Copilot auth` in Neovim, or
   - Run `gh auth login` in your terminal

3. Use Copilot as a provider:

```lua
require("nvim-redraft").setup({
  llm = {
    provider = "copilot",
    model = "gpt-4o",  -- or "gpt-4-turbo"
  },
})
```

The plugin automatically extracts your Copilot OAuth token from `~/.config/github-copilot/apps.json` - no API key needed!

### Default Keybindings

```lua
require("nvim-redraft").setup({
  keys = {
    { "<leader>ae", function() require("nvim-redraft").edit() end, mode = "v", desc = "AI Edit Selection" },
    { "<leader>am", function() require("nvim-redraft").select_model() end, desc = "Select AI Model" },
  },
})
```

Or disable and define your own:

```lua
require("nvim-redraft").setup({
  keys = {},
})

vim.keymap.set("v", "<C-a>", function()
  require("nvim-redraft").edit()
end, { desc = "AI Edit Selection" })
```

### Diff Mode

By default, AI edits are applied directly to your code. Enable `diff_mode` to review changes as git-style conflict markers first:

```lua
require("nvim-redraft").setup({
  diff_mode = true,
})
```

When enabled, AI suggestions appear as familiar conflict markers:

```
<<<<<<< Current
function add(a, b) {
  return a + b
}
=======
/**
 * Adds two numbers
 */
function add(a, b) {
  return a + b
}
>>>>>>> Incoming
```

**Resolution keybindings** (buffer-local, active only when conflicts exist):

| Key | Action |
|-----|--------|
| `co` | Keep original code (ours) |
| `ct` | Accept AI suggestion (theirs) |
| `cb` | Keep both versions |
| `]x` | Jump to next conflict |
| `[x` | Jump to previous conflict |

**Diff configuration:**

```lua
require("nvim-redraft").setup({
  diff_mode = true,
  diff = {
    autojump = true,  -- Jump to next conflict after resolution
    mappings = {
      ours = "co",
      theirs = "ct",
      both = "cb",
      next = "]x",
      prev = "[x",
    },
    highlights = {
      current = "DiffText",   -- Highlight for original code
      incoming = "DiffAdd",   -- Highlight for AI suggestion
    },
  },
})
```

The plugin creates two highlight groups (`NvimRedraftCurrent` and `NvimRedraftIncoming`) linked to the configured highlights. Override them directly for custom styling:

```lua
vim.api.nvim_set_hl(0, "NvimRedraftCurrent", { bg = "#3c3836" })
vim.api.nvim_set_hl(0, "NvimRedraftIncoming", { bg = "#3c5c3c" })
```

### All Options

```lua
{
  system_prompt = string,      -- Custom system prompt for the LLM
  keys = table,                -- Array of keybindings: { key, function, mode?, desc? }
  llm = {
    provider = string,         -- "openai", "anthropic", "xai", "copilot", "openrouter", or "cerebras" (default: "openai")
    model = string,            -- Model name (optional, uses provider default)
    models = table,            -- Array of {provider, model, label?} for multi-model setup
    default_model_index = number, -- Starting model index (default: 1)
    timeout = number,          -- Request timeout in ms (default: 30000)
    max_output_tokens = number,-- Max response tokens (default: 4096)
  },
  diff_mode = boolean,         -- Show changes as conflict markers (default: false)
  diff = {
    autojump = boolean,        -- Jump to next conflict after resolution (default: true)
    mappings = {
      ours = string,           -- Keep original (default: "co")
      theirs = string,         -- Accept AI version (default: "ct")
      both = string,           -- Keep both (default: "cb")
      next = string,           -- Next conflict (default: "]x")
      prev = string,           -- Previous conflict (default: "[x")
    },
    highlights = {
      current = string,        -- Original code highlight (default: "DiffText")
      incoming = string,       -- AI suggestion highlight (default: "DiffAdd")
    },
  },
  input = {
    prompt = string,           -- Input prompt text (default: "AI Edit: ")
    icon = string,             -- Input icon (default: "󱚣", Snacks.nvim only)
    win = table,               -- Window options (Snacks.nvim only)
  },
  debug = boolean,             -- Enable debug logging (default: false)
  log_file = string,           -- Log file path (default: "~/.local/state/nvim/nvim-redraft.log")
  debug_max_log_size = number, -- Max chars to log (default: 5000, 0 = unlimited)
}
```

**Note:** The `input.icon` and `input.win` options only apply when [Snacks.nvim](https://github.com/folke/snacks.nvim) is installed. Without Snacks.nvim, the plugin uses `vim.ui.input()` which displays prompts at the command line with only the `prompt` text.

## Troubleshooting

### Debug Logging

Enable detailed logging for any issues:

```lua
require("nvim-redraft").setup({
  debug = true,
  log_file = "~/.local/state/nvim/nvim-redraft.log",  -- optional, this is the default
})
```

The log contains:
- User instructions and selected code
- LLM requests/responses and timing
- Code transformations
- All errors with stack traces

**Warning:** Logs contain full code content. Store securely and delete when done.

### Common Issues

| Issue | Solution |
|-------|----------|
| **API key not set** | Export the appropriate key: `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `XAI_API_KEY`, `OPENROUTER_API_KEY`, or `CEREBRAS_API_KEY` in your shell profile (`.bashrc`, `.zshrc`, etc.) |
| **Copilot not authenticated** | Install [copilot.lua](https://github.com/zbirenbaum/copilot.lua) and run `:Copilot auth` or `gh auth login` |
| **TypeScript service fails** | Run `cd ts && npm install && npm run build`, verify `ts/dist/index.js` exists |
| **Service won't start** | Check Node.js >= 18.0.0 with `node --version` |
| **Large selections timeout** | Increase timeout: `llm = { timeout = 60000 }` |
| **Edits not applying** | Enable debug logging to see transformation steps |

## Development

```bash
make test             # Run tests
make format           # Format Lua and TypeScript
make lint             # Lint Lua and TypeScript
make install-hooks    # Copy pre-commit hook into .git/hooks
cd ts && npm run build  # Build TypeScript service
```

The pre-commit hook runs `make format` followed by `make lint`. Install it once per clone:

```bash
make install-hooks
```

> **Note**
> - `stylua` must be available on your PATH.
> - `luacheck` is required for Lua linting (`luarocks install luacheck`).
> - Run `npm install` inside `ts/` to install TypeScript lint/format dependencies.

## License

MIT
