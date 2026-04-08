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
local MAX_DIFF_RETRIES = 1

local INSERT_SYSTEM_PROMPT_SUFFIX = [[

For insertion requests, the provided code is surrounding context and contains the marker __NVIM_REDRAFT_CURSOR__ at the exact insertion point.
Return ONLY a single unified diff against the provided context.
You MAY modify the surrounding context when the requested change requires it.
The final patched context MUST remove the cursor marker.
Do not include commentary, line numbers outside the diff, or instructions.]]

local SELECTION_CONTEXT_SYSTEM_PROMPT_SUFFIX = [[

Selection edit requests may include surrounding selection context marked with __NVIM_REDRAFT_SELECTION_START__ and __NVIM_REDRAFT_SELECTION_END__.
Use that surrounding context only as reference material.
The surrounding context is read-only and MUST NOT be edited.
Return a unified diff for the selected code only, never the extra surrounding context or selection markers.]]

local DIRECT_APPLY_SYSTEM_PROMPT_SUFFIX = [[

Direct-apply mode is enabled for selection edits.
Return ONLY a single unified diff for the selected code.
Do not include conflict markers, before/after sections, explanations, or instructions.]]

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
Return ONLY a single unified diff for the selected code.
Do not return conflict markers, before/after sections, explanations, or instructions.
The editor will render the review view separately after applying the diff.]]

M.config = {
  system_prompt = [[You are a code editing assistant. Analyze the user's instruction and the selected code to determine the appropriate action.

Based on the instruction, intelligently:
- ADD new code if the instruction requests new functionality, features, or additions
- MODIFY existing code if the instruction asks to change, update, refactor, or improve existing lines
- DELETE code if the instruction asks to remove, delete, or eliminate specific parts
- REPLACE code when the instruction implies substitution or complete rewrites

Generate a sparse unified diff showing only the changes needed:
- Show only the changed lines plus the minimal context needed for the diff to apply cleanly
- For deletions, include the removed lines in the diff
- Make the diff clear and unambiguous
- Return ONLY the unified diff, with no explanations or markdown formatting

Be intelligent about preserving code structure, indentation, and style.

If additional file context is provided, use it only as reference material.
Return edits for the selected code only unless the request is an insertion context.
Do not edit, rewrite, or return any code outside the provided code snippet or context.]],
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
    multiline = {
      enabled = false,
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

  if type(opts.input) == "table" and opts.input.multiline ~= nil then
    if type(opts.input.multiline) ~= "table" then
      error("input.multiline must be a table")
    end

    if opts.input.multiline.enabled ~= nil and type(opts.input.multiline.enabled) ~= "boolean" then
      error("input.multiline.enabled must be a boolean")
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

local function build_retry_instruction(instruction, normalize_error)
  return instruction
    .. "\n\nYour previous response could not be applied because: "
    .. normalize_error
    .. "\nReturn ONLY a valid unified diff that applies cleanly to the provided code. Do not include commentary or fences."
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

    local function send_request_with_instruction(request_instruction, attempt)
      ipc.send_request({
        code = opts.code,
        instruction = request_instruction,
        systemPrompt = opts.system_prompt or M.config.system_prompt,
        filetype = opts.filetype,
        provider = current_model.provider,
        model = current_model.model,
        baseURL = M.config.llm.base_url,
        maxOutputTokens = M.config.llm.max_output_tokens,
        selectionContext = opts.selection_context,
        contextFiles = mention_result.context_files,
      }, function(result, error)
        if error then
          spinner.stop()
          local elapsed = (vim.loop.hrtime() - start_time) / 1e9
          logger.error(op, string.format("%s failed after %.2fs: %s", op:gsub("^%l", string.upper), elapsed, error))
          vim.notify("[nvim-redraft] " .. error, vim.log.levels.ERROR)
          return
        end

        logger.debug(op, "Final result:", result)

        local normalized_result = result
        if opts.normalize_result then
          local normalized, normalize_error = opts.normalize_result(result)
          if normalize_error then
            logger.warn(op, string.format("Model diff could not be applied on attempt %d: %s", attempt + 1, normalize_error))

            if attempt < MAX_DIFF_RETRIES then
              logger.info(op, string.format("Retrying %s with diff feedback", op))
              send_request_with_instruction(build_retry_instruction(mention_result.instruction, normalize_error), attempt + 1)
              return
            end

            spinner.stop()
            local elapsed = (vim.loop.hrtime() - start_time) / 1e9
            logger.error(
              op,
              string.format("%s failed after %.2fs: %s", op:gsub("^%l", string.upper), elapsed, normalize_error)
            )
            vim.notify("[nvim-redraft] " .. normalize_error, vim.log.levels.ERROR)
            return
          end

          normalized_result = normalized
        end

        spinner.stop()
        opts.apply_result(normalized_result, bufnr)

        local elapsed = (vim.loop.hrtime() - start_time) / 1e9
        logger.info(op, string.format("%s completed successfully in %.2fs", op:gsub("^%l", string.upper), elapsed))
        vim.notify(opts.success_message or "[nvim-redraft] Edit applied", vim.log.levels.INFO)
      end)
    end

    spinner.start(opts.spinner_message or "Processing edit...")
    send_request_with_instruction(mention_result.instruction, 0)
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
     normalize_result = function(result)
       return diff.apply_model_diff(sel.text, result)
     end,
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
     normalize_result = function(result)
       local patched_context, diff_error = diff.apply_model_diff(context.text, result)
       if not patched_context then
         return nil, diff_error
       end

       return diff.extract_insert_result(context.text, patched_context, context.marker)
     end,
     apply_result = function(result)
       replace.replace_range({
         start_line = context.start_line,
         end_line = context.end_line,
       }, result.patched_text, context.bufnr)
     end,
   })
end

M.diff = diff

return M
