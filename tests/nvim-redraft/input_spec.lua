local input = require("nvim-redraft.input")

describe("input", function()
  describe("get_instruction", function()
    local mock_config = {
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
    }

    it("should call callback with user input", function()
      local result = nil
      local callback_called = false

      package.loaded["snacks"] = {
        input = function(opts, callback)
          assert.equals("AI Edit: ", opts.prompt)
          assert.equals("󱚣", opts.icon)
          callback("test instruction")
        end,
      }

      input.get_instruction(mock_config, function(instruction)
        callback_called = true
        result = instruction
      end)

      package.loaded["snacks"] = nil

      assert.is_true(callback_called)
      assert.equals("test instruction", result)
    end)

    it("should not call callback when input is empty", function()
      local callback_called = false

      package.loaded["snacks"] = {
        input = function(opts, callback)
          callback("")
        end,
      }

      input.get_instruction(mock_config, function(instruction)
        callback_called = true
      end)

      package.loaded["snacks"] = nil

      assert.is_false(callback_called)
    end)

    it("should not call callback when input is nil", function()
      local callback_called = false

      package.loaded["snacks"] = {
        input = function(opts, callback)
          callback(nil)
        end,
      }

      input.get_instruction(mock_config, function(instruction)
        callback_called = true
      end)

      package.loaded["snacks"] = nil

      assert.is_false(callback_called)
    end)

    it("should handle multi-word instructions", function()
      local result = nil

      package.loaded["snacks"] = {
        input = function(opts, callback)
          callback("add error handling with try catch")
        end,
      }

      input.get_instruction(mock_config, function(instruction)
        result = instruction
      end)

      package.loaded["snacks"] = nil

      assert.equals("add error handling with try catch", result)
    end)

    it("should preserve whitespace in instructions", function()
      local result = nil

      package.loaded["snacks"] = {
        input = function(opts, callback)
          callback("  leading and trailing spaces  ")
        end,
      }

      input.get_instruction(mock_config, function(instruction)
        result = instruction
      end)

      package.loaded["snacks"] = nil

      assert.equals("  leading and trailing spaces  ", result)
    end)

    it("should fallback to vim.ui.input when Snacks.nvim is not available", function()
      package.loaded["snacks"] = nil
      local result = nil
      local callback_called = false

      local original_vim_ui_input = vim.ui.input
      vim.ui.input = function(opts, callback)
        assert.equals("AI Edit: ", opts.prompt)
        callback("fallback instruction")
      end

      input.get_instruction(mock_config, function(instruction)
        callback_called = true
        result = instruction
      end)

      vim.ui.input = original_vim_ui_input

      assert.is_true(callback_called)
      assert.equals("fallback instruction", result)
    end)

    it("should not pass icon or win options to vim.ui.input fallback", function()
      package.loaded["snacks"] = nil

      local original_vim_ui_input = vim.ui.input
      vim.ui.input = function(opts, callback)
        assert.equals("AI Edit: ", opts.prompt)
        assert.is_nil(opts.icon)
        assert.is_nil(opts.win)
        callback("test")
      end

      input.get_instruction(mock_config, function() end)

      vim.ui.input = original_vim_ui_input
    end)

    it("should use custom input options from config", function()
      local custom_config = {
        input = {
          prompt = "Custom Prompt: ",
          icon = "🤖",
          win = { relative = "editor", row = 10 },
        },
      }

      package.loaded["snacks"] = {
        input = function(opts, callback)
          assert.equals("Custom Prompt: ", opts.prompt)
          assert.equals("🤖", opts.icon)
          assert.equals("editor", opts.win.relative)
          assert.equals(10, opts.win.row)
          callback("test")
        end,
      }

      input.get_instruction(custom_config, function() end)

      package.loaded["snacks"] = nil
    end)

    it("should attach mention completion when Snacks picker is available", function()
      local original_keymap_set = vim.keymap.set
      local keymap_calls = {}

      vim.keymap.set = function(mode, lhs, rhs, opts)
        table.insert(keymap_calls, {
          mode = mode,
          lhs = lhs,
          opts = opts,
          rhs = rhs,
        })
      end

      package.loaded["snacks"] = {
        input = function(_, callback)
          return { buf = 11, win = 22 }
        end,
        picker = {
          files = function() end,
        },
      }

      input.get_instruction(mock_config, function() end)

      vim.keymap.set = original_keymap_set
      package.loaded["snacks"] = nil

      assert.equals(1, #keymap_calls)
      assert.equals("i", keymap_calls[1].mode)
      assert.equals("@", keymap_calls[1].lhs)
      assert.equals(11, keymap_calls[1].opts.buffer)
      assert.is_true(keymap_calls[1].opts.expr)
    end)

    it("should insert selected file path from the mention picker", function()
      local original_cwd = vim.fn.getcwd()
      local temp_dir = vim.fn.tempname()
      local current_buf = vim.api.nvim_get_current_buf()
      local current_win = vim.api.nvim_get_current_win()

      vim.fn.mkdir(temp_dir, "p")
      vim.fn.chdir(temp_dir)
      vim.api.nvim_buf_set_name(current_buf, temp_dir .. "/current.lua")
      vim.api.nvim_buf_set_lines(current_buf, 0, -1, false, { "@" })
      vim.api.nvim_win_set_cursor(current_win, { 1, 1 })

      local snacks = {
        picker = {
          files = function(opts)
            opts.confirm({ close = function() end }, { file = "src/helper.lua" })
          end,
        },
      }

      input.open_mention_picker(snacks, { buf = current_buf, win = current_win })

      vim.wait(1000, function()
        return vim.api.nvim_buf_get_lines(current_buf, 0, 1, false)[1] == "@src/helper.lua"
      end)

      vim.fn.chdir(original_cwd)

      assert.equals("@src/helper.lua", vim.api.nvim_buf_get_lines(current_buf, 0, 1, false)[1])
    end)
  end)
end)
