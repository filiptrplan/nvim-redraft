local logger = require("nvim-redraft.logger")

local M = {}

local NAMESPACE = vim.api.nvim_create_namespace("nvim-redraft-diff")
local CONFLICT_START = "<<<<<<< Current"
local CONFLICT_MIDDLE = "======="
local CONFLICT_END = ">>>>>>> Incoming"
local CURSOR_MARKER = "__NVIM_REDRAFT_CURSOR__"

local CONFLICT_START_PATTERN = "^<<<<<<< "
local CONFLICT_MIDDLE_PATTERN = "^=======$"
local CONFLICT_END_PATTERN = "^>>>>>>> "

---@class ConflictPosition
---@field current_start integer 0-indexed line of <<<<<<< marker
---@field current_content_start integer 0-indexed first line of current content
---@field current_content_end integer 0-indexed last line of current content
---@field middle integer 0-indexed line of ======= marker
---@field incoming_content_start integer 0-indexed first line of incoming content
---@field incoming_content_end integer 0-indexed last line of incoming content
---@field incoming_end integer 0-indexed line of >>>>>>> marker

---@class BufferConflictState
---@field positions ConflictPosition[]
---@field mappings_set boolean
---@field diagnostics_disabled boolean

---@type table<integer, BufferConflictState>
local buffer_states = {}

local function disable_diagnostics(bufnr)
  local state = buffer_states[bufnr]
  if state and state.diagnostics_disabled then
    return
  end
  vim.diagnostic.enable(false, { bufnr = bufnr })
  if state then
    state.diagnostics_disabled = true
  end
  logger.debug("diff", "Disabled diagnostics for buffer " .. bufnr)
end

local function enable_diagnostics(bufnr)
  local state = buffer_states[bufnr]
  if not state or not state.diagnostics_disabled then
    return
  end
  vim.diagnostic.enable(true, { bufnr = bufnr })
  state.diagnostics_disabled = false
  logger.debug("diff", "Re-enabled diagnostics for buffer " .. bufnr)
end

local autocmd_group = nil

local function split_lines(text)
  return vim.split(text or "", "\n", { plain = true })
end

local function strip_diff_fences(text)
  local trimmed = vim.trim(text or "")
  if vim.startswith(trimmed, "```diff\n") and vim.endswith(trimmed, "\n```") then
    return trimmed:sub(8, -5)
  end

  if vim.startswith(trimmed, "```\n") and vim.endswith(trimmed, "\n```") then
    return trimmed:sub(5, -5)
  end

  return trimmed
end

local function parse_hunk_header(line)
  local old_start, old_count, new_start, new_count = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
  if not old_start then
    return nil
  end

  return {
    old_start = tonumber(old_start),
    old_count = old_count == "" and 1 or tonumber(old_count),
    new_start = tonumber(new_start),
    new_count = new_count == "" and 1 or tonumber(new_count),
    lines = {},
  }
end

function M.parse_unified_diff(text)
  local payload = strip_diff_fences(text)
  local lines = split_lines(payload)
  local hunks = {}
  local current_hunk = nil
  local saw_hunk = false
  local file_header_count = 0

  for _, line in ipairs(lines) do
    if line:match("^@@ ") then
      current_hunk = parse_hunk_header(line)
      if not current_hunk then
        return nil, "Invalid unified diff hunk header"
      end
      table.insert(hunks, current_hunk)
      saw_hunk = true
    elseif current_hunk and line:match("^[ +%-]") then
      table.insert(current_hunk.lines, line)
    elseif current_hunk and line == "\\ No newline at end of file" then
      table.insert(current_hunk.lines, line)
    elseif line:match("^diff %-%-git ") or line:match("^index ") then
      if saw_hunk then
        return nil, "Only a single unified diff is supported"
      end
    elseif line:match("^%-%-%- ") or line:match("^%+%+%+ ") then
      file_header_count = file_header_count + 1
      if file_header_count > 2 then
        return nil, "Only a single unified diff is supported"
      end
    elseif line == "" and not saw_hunk then
      -- Allow leading blank lines.
    else
      return nil, "Response must be a unified diff only"
    end
  end

  if #hunks == 0 then
    return nil, "Response did not contain any unified diff hunks"
  end

  return {
    raw = payload,
    hunks = hunks,
  }
end

function M.apply_unified_diff(original_text, parsed_diff)
  local original_lines = split_lines(original_text)
  local result_lines = {}
  local current_index = 1

  for _, hunk in ipairs(parsed_diff.hunks) do
    local prefix_end = hunk.old_count == 0 and hunk.old_start or (hunk.old_start - 1)

    if prefix_end >= current_index then
      for i = current_index, prefix_end do
        table.insert(result_lines, original_lines[i] or "")
      end
    end

    local original_index = prefix_end + 1
    local consumed_old = 0
    local produced_new = 0

    for _, hunk_line in ipairs(hunk.lines) do
      local prefix = hunk_line:sub(1, 1)
      local content = hunk_line:sub(2)

      if prefix == " " then
        if original_lines[original_index] ~= content then
          return nil, string.format("Diff context mismatch at line %d", original_index)
        end
        table.insert(result_lines, content)
        original_index = original_index + 1
        consumed_old = consumed_old + 1
        produced_new = produced_new + 1
      elseif prefix == "-" then
        if original_lines[original_index] ~= content then
          return nil, string.format("Diff removal mismatch at line %d", original_index)
        end
        original_index = original_index + 1
        consumed_old = consumed_old + 1
      elseif prefix == "+" then
        table.insert(result_lines, content)
        produced_new = produced_new + 1
      elseif hunk_line ~= "\\ No newline at end of file" then
        return nil, "Invalid unified diff hunk body"
      end
    end

    if consumed_old ~= hunk.old_count then
      return nil, string.format("Diff expected %d original lines but consumed %d", hunk.old_count, consumed_old)
    end

    if produced_new ~= hunk.new_count then
      return nil, string.format("Diff expected %d new lines but produced %d", hunk.new_count, produced_new)
    end

    current_index = original_index
  end

  for i = current_index, #original_lines do
    table.insert(result_lines, original_lines[i])
  end

  return table.concat(result_lines, "\n")
end

function M.apply_model_diff(original_text, response_text)
  local parsed_diff, parse_err = M.parse_unified_diff(response_text)
  if not parsed_diff then
    return nil, parse_err
  end

  return M.apply_unified_diff(original_text, parsed_diff)
end

function M.extract_insert_result(original_text, patched_text, marker)
  marker = marker or CURSOR_MARKER

  local marker_start = original_text:find(marker, 1, true)
  if not marker_start then
    return nil, "Cursor marker missing from original insert context"
  end

  if patched_text:find(marker, 1, true) then
    return nil, "Patched insert context must remove the cursor marker"
  end

  local original_prefix = original_text:sub(1, marker_start - 1)
  local original_suffix = original_text:sub(marker_start + #marker)

  local prefix_len = 0
  local max_prefix = math.min(#original_prefix, #patched_text)
  while prefix_len < max_prefix and original_prefix:sub(prefix_len + 1, prefix_len + 1) == patched_text:sub(prefix_len + 1, prefix_len + 1) do
    prefix_len = prefix_len + 1
  end

  local suffix_len = 0
  local max_suffix = math.min(#original_suffix, #patched_text - prefix_len)
  while suffix_len < max_suffix do
    local original_char = original_suffix:sub(#original_suffix - suffix_len, #original_suffix - suffix_len)
    local patched_char = patched_text:sub(#patched_text - suffix_len, #patched_text - suffix_len)
    if original_char ~= patched_char then
      break
    end
    suffix_len = suffix_len + 1
  end

  local inserted_end = #patched_text - suffix_len
  local inserted_text = patched_text:sub(prefix_len + 1, inserted_end)

  return {
    patched_text = patched_text,
    inserted_text = inserted_text,
  }
end

local function get_config()
  local ok, redraft = pcall(require, "nvim-redraft")
  if ok then
    return redraft.config
  end
  return {}
end

local function setup_autocmds()
  if autocmd_group then
    return
  end

  autocmd_group = vim.api.nvim_create_augroup("nvim-redraft-diff", { clear = true })

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = autocmd_group,
    callback = function(args)
      if buffer_states[args.buf] then
        buffer_states[args.buf] = nil
        logger.debug("diff", "Cleaned up state for deleted buffer " .. args.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd("TextChanged", {
    group = autocmd_group,
    callback = function(args)
      if buffer_states[args.buf] then
        M.process_buffer(args.buf)
      end
    end,
  })
end

function M.inject_conflict_markers(bufnr, selection, new_text)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local original_lines = vim.api.nvim_buf_get_lines(bufnr, selection.start_line - 1, selection.end_line, false)
  local new_lines = vim.split(new_text, "\n")

  local conflict_lines = { CONFLICT_START }
  vim.list_extend(conflict_lines, original_lines)
  table.insert(conflict_lines, CONFLICT_MIDDLE)
  vim.list_extend(conflict_lines, new_lines)
  table.insert(conflict_lines, CONFLICT_END)

  vim.api.nvim_buf_set_lines(bufnr, selection.start_line - 1, selection.end_line, false, conflict_lines)

  logger.debug(
    "diff",
    string.format("Injected conflict markers at lines %d-%d", selection.start_line, selection.end_line)
  )

  setup_autocmds()
  M.process_buffer(bufnr)
end

function M.detect_conflicts(lines)
  local positions = {}
  local current_position = nil
  local in_conflict = false

  for i, line in ipairs(lines) do
    local lnum = i - 1

    if line:match(CONFLICT_START_PATTERN) then
      if in_conflict and current_position then
        logger.warn(
          "diff",
          string.format("Incomplete conflict at line %d (missing end marker)", current_position.current_start + 1)
        )
      end
      current_position = {
        current_start = lnum,
        current_content_start = lnum + 1,
      }
      in_conflict = true
    elseif in_conflict and line:match(CONFLICT_MIDDLE_PATTERN) then
      current_position.current_content_end = lnum - 1
      current_position.middle = lnum
      current_position.incoming_content_start = lnum + 1
    elseif in_conflict and line:match(CONFLICT_END_PATTERN) then
      current_position.incoming_content_end = lnum - 1
      current_position.incoming_end = lnum
      table.insert(positions, current_position)
      current_position = nil
      in_conflict = false
    end
  end

  if in_conflict and current_position then
    logger.warn(
      "diff",
      string.format("Incomplete conflict at line %d (missing end marker)", current_position.current_start + 1)
    )
  end

  return positions
end

function M.highlight_conflicts(bufnr, positions)
  vim.api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)

  local config = get_config()
  local current_hl = config.diff and config.diff.highlights and config.diff.highlights.current or "DiffText"
  local incoming_hl = config.diff and config.diff.highlights and config.diff.highlights.incoming or "DiffAdd"
  local mappings = config.diff and config.diff.mappings
    or {
      ours = "co",
      theirs = "ct",
      both = "cb",
      next = "]x",
      prev = "[x",
    }

  local hint_text = string.format(
    "[%s: ours, %s: theirs, %s: both, %s/%s: prev/next]",
    mappings.ours,
    mappings.theirs,
    mappings.both,
    mappings.prev,
    mappings.next
  )

  for _, pos in ipairs(positions) do
    -- Add hint virtual text on the <<<<<<< line
    vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, pos.current_start, 0, {
      virt_text = { { "  " .. hint_text, "Comment" } },
      virt_text_pos = "eol",
      priority = 100,
    })

    if pos.current_content_start <= pos.current_content_end then
      vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, pos.current_content_start, 0, {
        end_row = pos.current_content_end + 1,
        hl_group = current_hl,
        hl_eol = true,
        priority = 100,
      })
    end

    if pos.incoming_content_start <= pos.incoming_content_end then
      vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, pos.incoming_content_start, 0, {
        end_row = pos.incoming_content_end + 1,
        hl_group = incoming_hl,
        hl_eol = true,
        priority = 100,
      })
    end
  end
end

function M.process_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local positions = M.detect_conflicts(lines)

  if not buffer_states[bufnr] then
    buffer_states[bufnr] = { positions = {}, mappings_set = false, diagnostics_disabled = false }
  end

  buffer_states[bufnr].positions = positions

  if #positions > 0 then
    M.highlight_conflicts(bufnr, positions)
    M.setup_buffer_mappings(bufnr)
    disable_diagnostics(bufnr)
  else
    vim.api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)
    M.clear_buffer_mappings(bufnr)
    enable_diagnostics(bufnr)
  end

  return positions
end

function M.get_conflict_at_cursor(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local state = buffer_states[bufnr]
  if not state or #state.positions == 0 then
    return nil
  end

  local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1

  for _, pos in ipairs(state.positions) do
    if cursor_line >= pos.current_start and cursor_line <= pos.incoming_end then
      return pos
    end
  end

  return nil
end

function M.get_conflict_by_index(bufnr, index)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local state = buffer_states[bufnr]
  if not state or #state.positions == 0 then
    return nil
  end
  return state.positions[index]
end

function M.resolve_conflict(bufnr, pos, side)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local lines_to_keep = {}

  if side == "ours" then
    if pos.current_content_start <= pos.current_content_end then
      for i = pos.current_content_start, pos.current_content_end do
        table.insert(lines_to_keep, vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1])
      end
    end
    logger.info("diff", "Chose 'ours' - keeping original code")
  elseif side == "theirs" then
    if pos.incoming_content_start <= pos.incoming_content_end then
      for i = pos.incoming_content_start, pos.incoming_content_end do
        table.insert(lines_to_keep, vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1])
      end
    end
    logger.info("diff", "Chose 'theirs' - keeping AI code")
  elseif side == "both" then
    if pos.current_content_start <= pos.current_content_end then
      for i = pos.current_content_start, pos.current_content_end do
        table.insert(lines_to_keep, vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1])
      end
    end
    if pos.incoming_content_start <= pos.incoming_content_end then
      for i = pos.incoming_content_start, pos.incoming_content_end do
        table.insert(lines_to_keep, vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1])
      end
    end
    logger.info("diff", "Chose 'both' - keeping both versions")
  elseif side == "none" then
    logger.info("diff", "Chose 'none' - removing both versions")
  end

  vim.api.nvim_buf_set_lines(bufnr, pos.current_start, pos.incoming_end + 1, false, lines_to_keep)
  M.process_buffer(bufnr)
end

function M.choose(side)
  local bufnr = vim.api.nvim_get_current_buf()
  local pos = M.get_conflict_at_cursor(bufnr)

  if not pos then
    vim.notify("[nvim-redraft] No conflict at cursor", vim.log.levels.WARN)
    return
  end

  M.resolve_conflict(bufnr, pos, side)

  local config = get_config()
  if config.diff and config.diff.autojump and buffer_states[bufnr] and #buffer_states[bufnr].positions > 0 then
    M.jump_to_next()
  end
end

function M.jump_to_next()
  local bufnr = vim.api.nvim_get_current_buf()
  local state = buffer_states[bufnr]
  if not state or #state.positions == 0 then
    return
  end

  local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1

  for _, pos in ipairs(state.positions) do
    if pos.current_start > cursor_line then
      vim.api.nvim_win_set_cursor(0, { pos.current_start + 1, 0 })
      vim.cmd("normal! zz")
      return
    end
  end
end

function M.jump_to_prev()
  local bufnr = vim.api.nvim_get_current_buf()
  local state = buffer_states[bufnr]
  if not state or #state.positions == 0 then
    return
  end

  local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1

  for i = #state.positions, 1, -1 do
    local pos = state.positions[i]
    if pos.incoming_end < cursor_line then
      vim.api.nvim_win_set_cursor(0, { pos.current_start + 1, 0 })
      vim.cmd("normal! zz")
      return
    end
  end
end

function M.setup_buffer_mappings(bufnr)
  local state = buffer_states[bufnr]
  if state and state.mappings_set then
    return
  end

  local config = get_config()
  local mappings = config.diff and config.diff.mappings
    or {
      ours = "co",
      theirs = "ct",
      both = "cb",
      next = "]x",
      prev = "[x",
    }

  local function opts(desc)
    return { buffer = bufnr, silent = true, desc = "nvim-redraft: " .. desc }
  end

  vim.keymap.set("n", mappings.ours, function()
    M.choose("ours")
  end, opts("choose ours"))
  vim.keymap.set("n", mappings.theirs, function()
    M.choose("theirs")
  end, opts("choose theirs"))
  vim.keymap.set("n", mappings.both, function()
    M.choose("both")
  end, opts("choose both"))
  vim.keymap.set("n", mappings.next, function()
    M.jump_to_next()
  end, opts("next conflict"))
  vim.keymap.set("n", mappings.prev, function()
    M.jump_to_prev()
  end, opts("previous conflict"))

  if state then
    state.mappings_set = true
  end

  logger.debug("diff", "Set up conflict keybindings for buffer " .. bufnr)
end

function M.clear_buffer_mappings(bufnr)
  local state = buffer_states[bufnr]
  if not state or not state.mappings_set then
    return
  end

  local config = get_config()
  local mappings = config.diff and config.diff.mappings
    or {
      ours = "co",
      theirs = "ct",
      both = "cb",
      next = "]x",
      prev = "[x",
    }

  pcall(vim.keymap.del, "n", mappings.ours, { buffer = bufnr })
  pcall(vim.keymap.del, "n", mappings.theirs, { buffer = bufnr })
  pcall(vim.keymap.del, "n", mappings.both, { buffer = bufnr })
  pcall(vim.keymap.del, "n", mappings.next, { buffer = bufnr })
  pcall(vim.keymap.del, "n", mappings.prev, { buffer = bufnr })

  state.mappings_set = false

  logger.debug("diff", "Cleared conflict keybindings for buffer " .. bufnr)
end

function M.conflict_count(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local state = buffer_states[bufnr]
  if not state then
    return 0
  end
  return #state.positions
end

function M.clear(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)
  M.clear_buffer_mappings(bufnr)
  enable_diagnostics(bufnr)
  buffer_states[bufnr] = nil
end

return M
