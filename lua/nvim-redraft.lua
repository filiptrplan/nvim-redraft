local selection = require("nvim-redraft.selection")
local input = require("nvim-redraft.input")
local ipc = require("nvim-redraft.ipc")
local replace = require("nvim-redraft.replace")
local logger = require("nvim-redraft.logger")
local spinner = require("nvim-redraft.spinner")
local model_selector = require("nvim-redraft.model_selector")
local diff = require("nvim-redraft.diff")
local mentions = require("nvim-redraft.mentions")

local M = {}

local INSERT_SYSTEM_PROMPT_SUFFIX = [[

For insertion requests, the provided code is surrounding context and contains the marker __NVIM_REDRAFT_CURSOR__ at the exact insertion point.
Return ONLY the code that should be inserted at that marker.
Do not repeat the surrounding context.
Do not include the marker in your response.]]

local SELECTION_CONTEXT_SYSTEM_PROMPT_SUFFIX = [[

Selection edit requests may include surrounding selection context marked with __NVIM_REDRAFT_SELECTION_START__ and __NVIM_REDRAFT_SELECTION_END__.
Use that surrounding context only as reference material.
The surrounding context is read-only and MUST NOT be edited.
Return edits for the selected code only, never the extra surrounding context or selection markers.]]

local DIRECT_APPLY_SYSTEM_PROMPT_SUFFIX = [[

Direct-apply mode is enabled for selection edits.
Return ONLY the final replacement for the selected code.
Do not return a diff, patch, conflict markers, before/after comparison, or instructions.
Do not include line numbers, fences, or commentary.]]

local PYTHON_SYSTEM_PROMPT_SUFFIX = [[

When editing Python, preserve syntactic indentation exactly.
Use the surrounding code as the source of truth for indentation depth, tabs vs spaces, and block structure.
Do not shift edited lines left or right unless the requested change requires entering or leaving a block.
If you add new Python lines, indent them to the same level required by the surrounding block.]]

local PYTHON_INSERT_SYSTEM_PROMPT_SUFFIX = [[

For Python insertions, the indentation of the inserted code MUST match the block indentation at __NVIM_REDRAFT_CURSOR__.
Return the inserted text already indented correctly relative to the surrounding code.]]

local DIFF_MODE_SYSTEM_PROMPT_SUFFIX = [[

Diff mode is enabled for selection edits.
Return ONLY the edited version of the selected code.
Do not return conflict markers, a unified diff, a patch, or before/after sections.
The editor will render the diff view separately.]]

M.config = {
  system_prompt = [[You are a code editing assistant. Analyze the user's instruction and the selected code to determine the appropriate action.

Based on the instruction, intelligently:
- ADD new code if the instruction requests new functionality, features, or additions
- MODIFY existing code if the instruction asks to change, update, refactor, or improve existing lines
- DELETE code if the instruction asks to remove, delete, or eliminate specific parts
- REPLACE code when the instruction implies substitution or complete rewrites

Generate a sparse edit showing only the changes needed:
- Show only the lines being changed plus minimal context
- For deletions, show context before and after with the marker, omitting the deleted section
- Make your edit clear and unambiguous
- Return ONLY the modified code, no explanations or markdown formatting

Be intelligent about preserving code structure, indentation, and style.

If additional file context is provided, use it only as reference material.
Return edits for the selected code only.
Do not edit, rewrite, or return any code outside the selected code.]],
  keys = {
    {
      "<leader>ae",
      function()
        require("nvim-redraft").edit()
      end,
      mode = "v",
      desc = "AI Edit Selection",
    },
    {
      "<leader>ai",
      function()
        require("nvim-redraft").insert()
      end,
      mode = "n",
      desc = "AI Insert At Cursor",
    },
    {
      "<leader>am",
      function()
        require("nvim-redraft").select_model()
      end,
      desc = "Select AI Model",
    },
  },
  llm = {
    provider = "openai",
    model = nil,
    models = nil,
    default_model_index = 1,
    current_index = 1,
    timeout = 30000,
    base_url = nil,
    max_output_tokens = nil,
  },
  input = {
    prompt = "AI Edit: ",
    icon = "󱚣",
    win = {
      title_pos = "left",
      relative = "cursor",
      row = -3,
      col = 0,
    },
  },
  selection_context_radius = 30,
  diff_mode = false,
  diff = {
    autojump = true,
    mappings = {
      ours = "co",
      theirs = "ct",
      both = "cb",
      next = "]x",
      prev = "[x",
    },
    highlights = {
      current = "DiffText",
      incoming = "DiffAdd",
    },
  },
  debug = false,
  log_file = vim.fn.stdpath("state") .. "/nvim-redraft.log",
  debug_max_log_size = 5000,
}

local function setup_highlight_groups()
  vim.api.nvim_set_hl(0, "NvimRedraftCurrent", { link = M.config.diff.highlights.current, default = true })
  vim.api.nvim_set_hl(0, "NvimRedraftIncoming", { link = M.config.diff.highlights.incoming, default = true })
end

function M.setup(opts)
  opts = opts or {}

  if type(opts.llm) == "table" and type(opts.llm.timeout) == "number" and opts.llm.timeout <= 0 then
    error("llm.timeout must be a positive number")
  end

  if opts.selection_context_radius ~= nil then
    if type(opts.selection_context_radius) ~= "number" or opts.selection_context_radius < 0 then
      error("selection_context_radius must be a non-negative number")
    end
  end

  if type(opts.llm) == "table" and opts.llm.models and (opts.llm.provider or opts.llm.model) then
    vim.notify(
      "[nvim-redraft] Both llm.models and llm.provider/model configured. Using llm.models.",
      vim.log.levels.WARN
    )
  end

  M.config = vim.tbl_deep_extend("force", M.config, opts)

  if not M.config.llm.models then
    if M.config.llm.provider or M.config.llm.model then
      M.config.llm.models = {
        {
          provider = M.config.llm.provider or "openai",
          model = M.config.llm.model,
        },
      }
    else
      M.config.llm.models = {
        { provider = "openai", model = nil },
      }
    end
  end

  if type(M.config.llm.models) ~= "table" or #M.config.llm.models == 0 then
    error("llm.models must be a non-empty array of model configurations")
  end

  for i, model_config in ipairs(M.config.llm.models) do
    if type(model_config) ~= "table" then
      error(string.format("llm.models[%d] must be a table", i))
    end
    if not model_config.provider then
      error(string.format("llm.models[%d] must have a provider field", i))
    end
    local valid_providers =
      { openai = true, anthropic = true, xai = true, openrouter = true, copilot = true, cerebras = true }
    if not valid_providers[model_config.provider] then
      error(
        string.format(
          "llm.models[%d].provider must be one of: openai, anthropic, xai, openrouter, copilot, cerebras (got: %s)",
          i,
          model_config.provider
        )
      )
    end
  end

  if M.config.llm.default_model_index then
    if
      type(M.config.llm.default_model_index) ~= "number"
      or M.config.llm.default_model_index < 1
      or M.config.llm.default_model_index > #M.config.llm.models
    then
      error(string.format("llm.default_model_index must be between 1 and %d", #M.config.llm.models))
    end
    M.config.llm.current_index = M.config.llm.default_model_index
  else
    M.config.llm.current_index = 1
  end

  logger.init(M.config)
  ipc.config = M.config

  setup_highlight_groups()

  if M.config.keys then
    for _, key in ipairs(M.config.keys) do
      local mode = key.mode or "n"
      local key_opts = { desc = key.desc }
      vim.keymap.set(mode, key[1], key[2], key_opts)
    end
  end

  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      ipc.stop_service()
    end,
  })
end

function M.select_model()
  model_selector.get_model_selection(M.config.llm.models, M.config.llm.current_index, function(index)
    if index and index ~= M.config.llm.current_index then
      M.config.llm.current_index = index
      local selected = M.config.llm.models[index]
      local display_name = selected.label or (selected.provider .. ": " .. (selected.model or "default"))
      vim.notify(string.format("[nvim-redraft] Switched to %s", display_name), vim.log.levels.INFO)
      logger.info("select_model", string.format("Switched to model index %d: %s", index, display_name))
    end
  end)
end

local function is_python_filetype(filetype)
  return filetype == "python"
end

local function get_base_system_prompt(filetype)
  local prompt = M.config.system_prompt
  if is_python_filetype(filetype) then
    prompt = prompt .. PYTHON_SYSTEM_PROMPT_SUFFIX
  end
  return prompt
end

local function get_edit_system_prompt(filetype)
  local base_prompt = get_base_system_prompt(filetype) .. SELECTION_CONTEXT_SYSTEM_PROMPT_SUFFIX

  if M.config.diff_mode then
    return base_prompt .. DIFF_MODE_SYSTEM_PROMPT_SUFFIX
  end

  return base_prompt .. DIRECT_APPLY_SYSTEM_PROMPT_SUFFIX
end

local function get_insert_system_prompt(filetype)
  local prompt = get_base_system_prompt(filetype) .. INSERT_SYSTEM_PROMPT_SUFFIX
  if is_python_filetype(filetype) then
    prompt = prompt .. PYTHON_INSERT_SYSTEM_PROMPT_SUFFIX
  end
  return prompt
end

local function run_request(opts)
  local start_time = vim.loop.hrtime()
  local op = opts.op or "edit"
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()

  logger.info(op, string.format("%s operation started", op:gsub("^%l", string.upper)))

  input.get_instruction(M.config, function(instruction)
    local mention_result = mentions.parse(instruction, {
      workspace_root = mentions.get_workspace_root(),
    })

    logger.debug(op, "User instruction: " .. instruction)
    logger.debug(op, "Resolved instruction: " .. mention_result.instruction)
    logger.debug(op, "Selected code:", opts.code)

    if opts.log_details then
      logger.debug(op, opts.log_details)
    end

    if #mention_result.context_files > 0 then
      logger.debug(op, "Mentioned files:", vim.inspect(mention_result.context_files))
    end

    if #mention_result.skipped_mentions > 0 then
      logger.debug(op, "Skipped mentions:", table.concat(mention_result.skipped_mentions, ", "))
    end

    local current_model = M.config.llm.models[M.config.llm.current_index]
    logger.debug(
      op,
      string.format("Using model: %s (provider: %s)", current_model.model or "default", current_model.provider)
    )

    spinner.start(opts.spinner_message or "Processing edit...")

    ipc.send_request({
      code = opts.code,
      instruction = mention_result.instruction,
      systemPrompt = opts.system_prompt or M.config.system_prompt,
      filetype = opts.filetype,
      provider = current_model.provider,
      model = current_model.model,
      baseURL = M.config.llm.base_url,
      maxOutputTokens = M.config.llm.max_output_tokens,
      selectionContext = opts.selection_context,
      contextFiles = mention_result.context_files,
    }, function(result, error)
      spinner.stop()

      if error then
        local elapsed = (vim.loop.hrtime() - start_time) / 1e9
        logger.error(op, string.format("%s failed after %.2fs: %s", op:gsub("^%l", string.upper), elapsed, error))
        vim.notify("[nvim-redraft] " .. error, vim.log.levels.ERROR)
        return
      end

      logger.debug(op, "Final result:", result)

      opts.apply_result(result, bufnr)

      local elapsed = (vim.loop.hrtime() - start_time) / 1e9
      logger.info(op, string.format("%s completed successfully in %.2fs", op:gsub("^%l", string.upper), elapsed))
      vim.notify(opts.success_message or "[nvim-redraft] Edit applied", vim.log.levels.INFO)
    end)
  end)
end

function M.edit()
  vim.cmd('normal! "vy')
  local sel, err = selection.get_visual_selection(M.config.selection_context_radius)
  if not sel then
    logger.error("edit", "Failed to get selection: " .. err)
    vim.notify("[nvim-redraft] " .. err, vim.log.levels.ERROR)
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local filetype = vim.bo[bufnr].filetype
  run_request({
    op = "edit",
    bufnr = bufnr,
    code = sel.text,
    selection_context = sel.context_text,
    system_prompt = get_edit_system_prompt(filetype),
    filetype = filetype,
    log_details = string.format(
      "Selection details: lines %d-%d, cols %d-%d, context lines %d-%d",
      sel.start_line,
      sel.end_line,
      sel.start_col,
      sel.end_col,
      sel.context_start_line or sel.start_line,
      sel.context_end_line or sel.end_line
    ),
    spinner_message = "Processing edit...",
    success_message = "[nvim-redraft] Edit applied",
    apply_result = function(result, target_bufnr)
      if M.config.diff_mode then
        diff.inject_conflict_markers(target_bufnr, sel, result)
        return
      end

      replace.replace_selection(sel, result, target_bufnr)
    end,
  })
end

function M.insert()
  local context, err = selection.get_cursor_context(30)
  if not context then
    logger.error("insert", "Failed to get cursor context: " .. err)
    vim.notify("[nvim-redraft] " .. err, vim.log.levels.ERROR)
    return
  end

  local filetype = vim.bo[context.bufnr].filetype
  run_request({
    op = "insert",
    bufnr = context.bufnr,
    code = context.text,
    system_prompt = get_insert_system_prompt(filetype),
    filetype = filetype,
    log_details = string.format(
      "Cursor context details: lines %d-%d around %d:%d",
      context.start_line,
      context.end_line,
      context.cursor_line,
      context.cursor_col
    ),
    spinner_message = "Processing insert...",
    success_message = "[nvim-redraft] Insert applied",
    apply_result = function(result)
      replace.insert_at_cursor({
        bufnr = context.bufnr,
        line = context.cursor_line,
        col = context.cursor_col,
      }, result)
    end,
  })
end

M.diff = diff

return M
