local M = {}

local mentions = require("nvim-redraft.mentions")

local function insert_text(winid, bufnr, text)
  if not (winid and vim.api.nvim_win_is_valid(winid)) then
    return
  end

  local cursor = vim.api.nvim_win_get_cursor(winid)
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1] or ""
  local col = cursor[2]

  if line:sub(col + 1, col + 1) == "@" then
    col = col + 1
  end

  vim.api.nvim_buf_set_text(bufnr, cursor[1] - 1, col, cursor[1] - 1, col, { text })
  vim.api.nvim_win_set_cursor(winid, { cursor[1], col + #text })
end

function M.open_mention_picker(snacks, target)
  local picker_root = mentions.get_picker_root()
  local workspace_root = mentions.get_workspace_root()
  local workspace_prefix = vim.pesc(workspace_root)

  snacks.picker.pick({
    title = "Mention File",
    focus = "input",
    multi = {
      {
        source = "select",
        title = "Special",
        items = {
          {
            text = "@buffer",
            mention = "buffer",
          },
        },
        format = "text",
        preview = "none",
      },
      {
        source = "files",
        cwd = picker_root,
      },
    },
    confirm = function(picker, item)
      picker:close()
      if not item then
        return
      end

      local mention_text
      if item.mention == "buffer" then
        mention_text = "buffer"
      else
        local selected = item.file or item.text
        if not selected or selected == "" then
          return
        end

        local absolute_path = selected:match("^/") and selected or vim.fn.fnamemodify(picker_root .. "/" .. selected, ":p")
        local relative_path = vim.fn.fnamemodify(absolute_path, ":.")
        if (relative_path == absolute_path or relative_path == "") and absolute_path:match("^" .. workspace_prefix .. "/") then
          relative_path = absolute_path:sub(#workspace_root + 2)
        end

        mention_text = mentions.format_path_for_mention(relative_path):sub(2)
      end

      vim.schedule(function()
        if target.win and vim.api.nvim_win_is_valid(target.win) and vim.api.nvim_buf_is_valid(target.buf) then
          vim.api.nvim_set_current_win(target.win)
          insert_text(target.win, target.buf, mention_text)
          vim.cmd("startinsert")
        end
      end)
    end,
  })
end

function M.attach_mention_completion(snacks, target)
  vim.keymap.set("i", "@", function()
    vim.schedule(function()
      M.open_mention_picker(snacks, target)
    end)
    return "@"
  end, {
    buffer = target.buf,
    expr = true,
    noremap = true,
    silent = true,
  })
end

function M.get_instruction(config, callback)
  local ok, snacks = pcall(require, "snacks")

  if ok and snacks.input then
    local input_opts = vim.tbl_deep_extend("force", {
      prompt = config.input.prompt or "AI Edit: ",
      icon = config.input.icon,
      win = config.input.win or {},
    }, {})

    local input_win = snacks.input(input_opts, function(input)
      if input and input ~= "" then
        callback(input)
      end
    end)

    local target = {
      buf = input_win and input_win.buf or vim.api.nvim_get_current_buf(),
      win = input_win and input_win.win or vim.api.nvim_get_current_win(),
    }

    if snacks.picker then
      M.attach_mention_completion(snacks, target)
    end
  else
    vim.ui.input({
      prompt = config.input.prompt or "AI Edit: ",
    }, function(input)
      if input and input ~= "" then
        callback(input)
      end
    end)
  end
end

return M
