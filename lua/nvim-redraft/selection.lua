local logger = require("nvim-redraft.logger")

local M = {}

M.CURSOR_MARKER = "__NVIM_REDRAFT_CURSOR__"

function M.get_visual_selection()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  local start_line = start_pos[2]
  local start_col = start_pos[3]
  local end_line = end_pos[2]
  local end_col = end_pos[3]

  if start_line == 0 or end_line == 0 then
    logger.warn("selection", "No active visual selection (start_line or end_line is 0)")
    return nil, "No active visual selection"
  end

  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

  if #lines == 0 then
    logger.warn("selection", "Empty selection")
    return nil, "Empty selection"
  end

  local mode = vim.fn.visualmode()
  logger.debug("selection", string.format("Visual mode: %s, lines: %d", mode, #lines))

  if mode == "V" then
    -- Visual line mode - don't trim columns
  elseif #lines == 1 then
    -- Character mode, single line
    lines[1] = string.sub(lines[1], start_col, end_col)
  else
    -- Character mode, multiple lines
    lines[1] = string.sub(lines[1], start_col)
    lines[#lines] = string.sub(lines[#lines], 1, end_col)
  end

  local result = {
    text = table.concat(lines, "\n"),
    start_line = start_line,
    end_line = end_line,
    start_col = start_col,
    end_col = end_col,
  }

  logger.debug(
    "selection",
    string.format("Extracted selection: %d chars, lines %d-%d", #result.text, start_line, end_line)
  )

  return result
end

function M.get_cursor_context(radius)
  radius = radius or 30

  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor[1]
  local cursor_col = cursor[2]
  local total_lines = vim.api.nvim_buf_line_count(bufnr)

  if total_lines == 0 then
    logger.warn("selection", "Cannot capture cursor context from an empty buffer")
    return nil, "Empty buffer"
  end

  local start_line = math.max(1, cursor_line - radius)
  local end_line = math.min(total_lines, cursor_line + radius)
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)

  if #lines == 0 then
    logger.warn("selection", "Empty cursor context")
    return nil, "Empty cursor context"
  end

  local relative_cursor_line = cursor_line - start_line + 1
  local current_line = lines[relative_cursor_line] or ""
  lines[relative_cursor_line] = current_line:sub(1, cursor_col) .. M.CURSOR_MARKER .. current_line:sub(cursor_col + 1)

  local result = {
    bufnr = bufnr,
    text = table.concat(lines, "\n"),
    start_line = start_line,
    end_line = end_line,
    cursor_line = cursor_line,
    cursor_col = cursor_col,
    marker = M.CURSOR_MARKER,
  }

  logger.debug(
    "selection",
    string.format(
      "Extracted cursor context: lines %d-%d around %d:%d",
      start_line,
      end_line,
      cursor_line,
      cursor_col
    )
  )

  return result
end

return M
