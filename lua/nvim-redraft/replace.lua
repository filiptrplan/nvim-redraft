local logger = require("nvim-redraft.logger")

local M = {}

function M.replace_selection(selection, new_text, bufnr)
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr

  logger.debug(
    "replace",
    string.format("Replacing lines %d-%d with %d chars", selection.start_line, selection.end_line, #new_text)
  )

  local lines = vim.split(new_text, "\n")

  logger.debug("replace", string.format("Split into %d lines", #lines))

  vim.api.nvim_buf_set_lines(bufnr, selection.start_line - 1, selection.end_line, false, lines)

  logger.info("replace", "Code replacement completed")
end

function M.insert_at_cursor(position, new_text)
  local bufnr = (position.bufnr == nil or position.bufnr == 0) and vim.api.nvim_get_current_buf() or position.bufnr

  logger.debug(
    "replace",
    string.format("Inserting %d chars at %d:%d", #new_text, position.line, position.col)
  )

  if new_text == "" then
    logger.info("replace", "Insert result was empty; skipping buffer update")
    return
  end

  if not vim.api.nvim_buf_is_valid(bufnr) then
    logger.warn("replace", string.format("Buffer %d is no longer valid; skipping insert", bufnr))
    return
  end

  local lines = vim.split(new_text, "\n", { plain = true })
  vim.api.nvim_buf_set_text(bufnr, position.line - 1, position.col, position.line - 1, position.col, lines)

  if vim.api.nvim_get_current_buf() == bufnr then
    local end_line = position.line + #lines - 1
    local end_col = #lines == 1 and position.col + #lines[1] or #lines[#lines]
    vim.api.nvim_win_set_cursor(0, { end_line, end_col })
  end

  logger.info("replace", "Code insertion completed")
end

function M.replace_range(range, new_text, bufnr)
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr

  logger.debug(
    "replace",
    string.format("Replacing range lines %d-%d with %d chars", range.start_line, range.end_line, #new_text)
  )

  local lines = vim.split(new_text, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(bufnr, range.start_line - 1, range.end_line, false, lines)

  logger.info("replace", "Range replacement completed")
end

return M
