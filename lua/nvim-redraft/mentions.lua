local M = {}

local MAX_CONTEXT_FILES = 10

local function is_word_char(char)
  return char:match("[%w_./%-]") ~= nil
end

local function is_mention_boundary(prev)
  if not prev or prev == "" then
    return true
  end

  return prev:match("[%s%(%)%[%]%{%},:;]") ~= nil
end

local function normalize_instruction(text)
  local normalized = text:gsub("[ \t][ \t]+", " ")
  normalized = normalized:gsub(" *\n *", "\n")
  normalized = normalized:gsub("\n\n\n+", "\n\n")
  normalized = normalized:gsub("%s+([,.;:!?])", "%1")
  return vim.trim(normalized)
end

local function find_workspace_root()
  return vim.fn.getcwd()
end

local function is_within_root(path, root)
  local escaped_root = vim.pesc(root)
  return path == root or path:match("^" .. escaped_root .. "/") ~= nil
end

local function file_readable(path)
  return vim.fn.filereadable(path) == 1 and vim.fn.isdirectory(path) == 0
end

local function make_relative_path(path, root)
  local relative = vim.fn.fnamemodify(path, ":.")
  if relative ~= path and relative ~= "" then
    return relative
  end

  if is_within_root(path, root) then
    return path:sub(#root + 2)
  end

  return path
end

local function build_current_buffer_entry(workspace_root)
  local bufnr = vim.api.nvim_get_current_buf()
  local current_file = vim.api.nvim_buf_get_name(bufnr)
  local content = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")

  if current_file == "" then
    return {
      path = "[Current Buffer]",
      absolutePath = "",
      content = content,
    }
  end

  local absolute_path = vim.fn.fnamemodify(current_file, ":p"):gsub("/$", "")

  return {
    path = make_relative_path(absolute_path, workspace_root),
    absolutePath = absolute_path,
    content = content,
  }
end

local function resolve_candidate(raw_path, base_dir, workspace_root)
  if raw_path == "" then
    return nil
  end

  local expanded = vim.fn.expand(raw_path)
  local candidate = expanded

  if not candidate:match("^/") then
    candidate = vim.fn.fnamemodify(base_dir .. "/" .. candidate, ":p")
  else
    candidate = vim.fn.fnamemodify(candidate, ":p")
  end

  candidate = candidate:gsub("/$", "")

  if not is_within_root(candidate, workspace_root) or not file_readable(candidate) then
    return nil
  end

  return {
    path = make_relative_path(candidate, workspace_root),
    absolutePath = candidate,
  }
end

local function resolve_path(raw_path, opts)
  local workspace_root = opts.workspace_root or find_workspace_root()
  local current_file = vim.api.nvim_buf_get_name(0)
  local current_dir = current_file ~= "" and vim.fn.fnamemodify(current_file, ":p:h") or workspace_root

  local candidates = {
    resolve_candidate(raw_path, current_dir, workspace_root),
  }

  if current_dir ~= workspace_root then
    table.insert(candidates, resolve_candidate(raw_path, workspace_root, workspace_root))
  end

  for _, candidate in ipairs(candidates) do
    if candidate then
      return candidate
    end
  end

  return nil
end

function M.parse(instruction, opts)
  opts = opts or {}

  local resolved = {}
  local skipped = {}
  local seen = {}
  local output = {}
  local i = 1
  local length = #instruction

  while i <= length do
    local char = instruction:sub(i, i)
    local prev = i > 1 and instruction:sub(i - 1, i - 1) or nil

    if char == "\\" and instruction:sub(i + 1, i + 1) == "@" then
      table.insert(output, "@")
      i = i + 2
    elseif char == "@" and is_mention_boundary(prev) then
      local mention_path = nil
      local next_char = instruction:sub(i + 1, i + 1)
      local consumed = i

      if next_char == '"' then
        local j = i + 2
        while j <= length and instruction:sub(j, j) ~= '"' do
          j = j + 1
        end

        if j <= length then
          mention_path = instruction:sub(i + 2, j - 1)
          consumed = j
        end
      else
        local j = i + 1
        while j <= length and is_word_char(instruction:sub(j, j)) do
          j = j + 1
        end

        if j > i + 1 then
          mention_path = instruction:sub(i + 1, j - 1)
          consumed = j - 1
        end
      end

      if mention_path then
        local entry
        if mention_path == "buffer" then
          entry = build_current_buffer_entry(opts.workspace_root or find_workspace_root())
        else
          entry = resolve_path(mention_path, opts)
        end

        local key = entry and (entry.absolutePath ~= "" and entry.absolutePath or entry.path) or nil
        if entry and not seen[key] and #resolved < MAX_CONTEXT_FILES then
          seen[key] = true
          table.insert(resolved, entry)
        elseif not entry then
          table.insert(skipped, mention_path)
        end
        i = consumed + 1
      else
        table.insert(output, char)
        i = i + 1
      end
    else
      table.insert(output, char)
      i = i + 1
    end
  end

  return {
    instruction = normalize_instruction(table.concat(output)),
    context_files = resolved,
    skipped_mentions = skipped,
  }
end

function M.format_path_for_mention(path)
  if path:find(" ") then
    return '@"' .. path .. '"'
  end

  return "@" .. path
end

function M.get_picker_root()
  local current_file = vim.api.nvim_buf_get_name(0)
  if current_file == "" then
    return find_workspace_root()
  end

  return vim.fn.fnamemodify(current_file, ":p:h")
end

function M.get_workspace_root()
  return find_workspace_root()
end

return M
