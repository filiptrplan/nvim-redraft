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
        multiline = {
          enabled = false,
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
          multiline = {
            enabled = false,
          },
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

    it("should open a multiline floating buffer when enabled", function()
      local original_create_buf = vim.api.nvim_create_buf
      local original_buf_set_option = vim.api.nvim_buf_set_option
      local original_buf_set_lines = vim.api.nvim_buf_set_lines
      local original_open_win = vim.api.nvim_open_win
      local original_keymap_set = vim.keymap.set
      local original_cmd = vim.cmd
      local original_columns = vim.o.columns
      local original_lines = vim.o.lines
      local original_cmdheight = vim.o.cmdheight
      local keymap_calls = {}
      local created_buffer
      local opened_window
      local startinsert_called = false

      package.loaded["snacks"] = nil
      vim.o.columns = 160
      vim.o.lines = 50
      vim.o.cmdheight = 1

      vim.api.nvim_create_buf = function(_, _)
        created_buffer = 44
        return created_buffer
      end

      vim.api.nvim_buf_set_option = function(buf, option)
        assert.equals(created_buffer, buf)
        assert.is_true(option == "buftype" or option == "bufhidden" or option == "swapfile")
      end

      vim.api.nvim_buf_set_lines = function(buf, _, _, _, lines)
        assert.equals(created_buffer, buf)
        assert.same({ "" }, lines)
      end

      vim.api.nvim_open_win = function(buf, enter, opts)
        opened_window = 55
        assert.equals(created_buffer, buf)
        assert.is_true(enter)
        assert.equals("editor", opts.relative)
        assert.equals("minimal", opts.style)
        assert.equals("rounded", opts.border)
        return opened_window
      end

      vim.keymap.set = function(mode, lhs, rhs, opts)
        table.insert(keymap_calls, {
          mode = mode,
          lhs = lhs,
          rhs = rhs,
          opts = opts,
        })
      end

      vim.cmd = function(command)
        if command == "startinsert" then
          startinsert_called = true
        end
      end

      local multiline_config = vim.tbl_deep_extend("force", mock_config, {
        input = {
          multiline = {
            enabled = true,
          },
        },
      })

      input.get_instruction(multiline_config, function() end)

      vim.api.nvim_create_buf = original_create_buf
      vim.api.nvim_buf_set_option = original_buf_set_option
      vim.api.nvim_buf_set_lines = original_buf_set_lines
      vim.api.nvim_open_win = original_open_win
      vim.keymap.set = original_keymap_set
      vim.cmd = original_cmd
      vim.o.columns = original_columns
      vim.o.lines = original_lines
      vim.o.cmdheight = original_cmdheight

      assert.equals(44, created_buffer)
      assert.equals(55, opened_window)
      assert.is_true(startinsert_called)
      assert.equals(3, #keymap_calls)
      assert.same({ "i", "n" }, keymap_calls[1].mode)
      assert.equals("<C-s>", keymap_calls[1].lhs)
      assert.equals(44, keymap_calls[1].opts.buffer)
      assert.equals("n", keymap_calls[2].mode)
      assert.equals("<CR>", keymap_calls[2].lhs)
      assert.same({ "i", "n" }, keymap_calls[3].mode)
      assert.equals("<Esc>", keymap_calls[3].lhs)
    end)

    it("should submit multiline input with Ctrl-S", function()
      local original_create_buf = vim.api.nvim_create_buf
      local original_buf_set_option = vim.api.nvim_buf_set_option
      local original_buf_set_lines = vim.api.nvim_buf_set_lines
      local original_buf_get_lines = vim.api.nvim_buf_get_lines
      local original_open_win = vim.api.nvim_open_win
      local original_win_is_valid = vim.api.nvim_win_is_valid
      local original_win_close = vim.api.nvim_win_close
      local original_keymap_set = vim.keymap.set
      local original_cmd = vim.cmd
      local keymaps = {}
      local closed_window
      local result

      package.loaded["snacks"] = nil

      vim.api.nvim_create_buf = function()
        return 60
      end

      vim.api.nvim_buf_set_option = function() end
      vim.api.nvim_buf_set_lines = function() end
      vim.api.nvim_open_win = function()
        return 61
      end
      vim.api.nvim_buf_get_lines = function(buf)
        assert.equals(60, buf)
        return { "line one", "line two" }
      end
      vim.api.nvim_win_is_valid = function(win)
        return win == 61
      end
      vim.api.nvim_win_close = function(win, force)
        closed_window = { win = win, force = force }
      end
      vim.keymap.set = function(_, lhs, rhs)
        keymaps[lhs] = rhs
      end
      vim.cmd = function() end

      input.get_instruction({ input = { prompt = "AI Edit: ", multiline = { enabled = true } } }, function(instruction)
        result = instruction
      end)

      keymaps["<C-s>"]()

      vim.api.nvim_create_buf = original_create_buf
      vim.api.nvim_buf_set_option = original_buf_set_option
      vim.api.nvim_buf_set_lines = original_buf_set_lines
      vim.api.nvim_buf_get_lines = original_buf_get_lines
      vim.api.nvim_open_win = original_open_win
      vim.api.nvim_win_is_valid = original_win_is_valid
      vim.api.nvim_win_close = original_win_close
      vim.keymap.set = original_keymap_set
      vim.cmd = original_cmd

      assert.equals("line one\nline two", result)
      assert.same({ win = 61, force = true }, closed_window)
    end)

    it("should submit multiline input with normal mode Enter", function()
      local original_create_buf = vim.api.nvim_create_buf
      local original_buf_set_option = vim.api.nvim_buf_set_option
      local original_buf_set_lines = vim.api.nvim_buf_set_lines
      local original_buf_get_lines = vim.api.nvim_buf_get_lines
      local original_open_win = vim.api.nvim_open_win
      local original_win_is_valid = vim.api.nvim_win_is_valid
      local original_win_close = vim.api.nvim_win_close
      local original_keymap_set = vim.keymap.set
      local original_cmd = vim.cmd
      local keymaps = {}
      local result

      package.loaded["snacks"] = nil

      vim.api.nvim_create_buf = function()
        return 70
      end

      vim.api.nvim_buf_set_option = function() end
      vim.api.nvim_buf_set_lines = function() end
      vim.api.nvim_open_win = function()
        return 71
      end
      vim.api.nvim_buf_get_lines = function()
        return { "submit with enter" }
      end
      vim.api.nvim_win_is_valid = function()
        return true
      end
      vim.api.nvim_win_close = function() end
      vim.keymap.set = function(_, lhs, rhs)
        keymaps[lhs] = rhs
      end
      vim.cmd = function() end

      input.get_instruction({ input = { prompt = "AI Edit: ", multiline = { enabled = true } } }, function(instruction)
        result = instruction
      end)

      keymaps["<CR>"]()

      vim.api.nvim_create_buf = original_create_buf
      vim.api.nvim_buf_set_option = original_buf_set_option
      vim.api.nvim_buf_set_lines = original_buf_set_lines
      vim.api.nvim_buf_get_lines = original_buf_get_lines
      vim.api.nvim_open_win = original_open_win
      vim.api.nvim_win_is_valid = original_win_is_valid
      vim.api.nvim_win_close = original_win_close
      vim.keymap.set = original_keymap_set
      vim.cmd = original_cmd

      assert.equals("submit with enter", result)
    end)

    it("should cancel multiline input with Esc", function()
      local original_create_buf = vim.api.nvim_create_buf
      local original_buf_set_option = vim.api.nvim_buf_set_option
      local original_buf_set_lines = vim.api.nvim_buf_set_lines
      local original_open_win = vim.api.nvim_open_win
      local original_win_is_valid = vim.api.nvim_win_is_valid
      local original_win_close = vim.api.nvim_win_close
      local original_keymap_set = vim.keymap.set
      local original_cmd = vim.cmd
      local keymaps = {}
      local callback_called = false
      local closed_window

      package.loaded["snacks"] = nil

      vim.api.nvim_create_buf = function()
        return 80
      end

      vim.api.nvim_buf_set_option = function() end
      vim.api.nvim_buf_set_lines = function() end
      vim.api.nvim_open_win = function()
        return 81
      end
      vim.api.nvim_win_is_valid = function(win)
        return win == 81
      end
      vim.api.nvim_win_close = function(win, force)
        closed_window = { win = win, force = force }
      end
      vim.keymap.set = function(_, lhs, rhs)
        keymaps[lhs] = rhs
      end
      vim.cmd = function() end

      input.get_instruction({ input = { prompt = "AI Edit: ", multiline = { enabled = true } } }, function()
        callback_called = true
      end)

      keymaps["<Esc>"]()

      vim.api.nvim_create_buf = original_create_buf
      vim.api.nvim_buf_set_option = original_buf_set_option
      vim.api.nvim_buf_set_lines = original_buf_set_lines
      vim.api.nvim_open_win = original_open_win
      vim.api.nvim_win_is_valid = original_win_is_valid
      vim.api.nvim_win_close = original_win_close
      vim.keymap.set = original_keymap_set
      vim.cmd = original_cmd

      assert.is_false(callback_called)
      assert.same({ win = 81, force = true }, closed_window)
    end)

    it("should not call callback for empty multiline input", function()
      local original_create_buf = vim.api.nvim_create_buf
      local original_buf_set_option = vim.api.nvim_buf_set_option
      local original_buf_set_lines = vim.api.nvim_buf_set_lines
      local original_buf_get_lines = vim.api.nvim_buf_get_lines
      local original_open_win = vim.api.nvim_open_win
      local original_win_is_valid = vim.api.nvim_win_is_valid
      local original_win_close = vim.api.nvim_win_close
      local original_keymap_set = vim.keymap.set
      local original_cmd = vim.cmd
      local keymaps = {}
      local callback_called = false

      package.loaded["snacks"] = nil

      vim.api.nvim_create_buf = function()
        return 90
      end

      vim.api.nvim_buf_set_option = function() end
      vim.api.nvim_buf_set_lines = function() end
      vim.api.nvim_open_win = function()
        return 91
      end
      vim.api.nvim_buf_get_lines = function()
        return { "", "" }
      end
      vim.api.nvim_win_is_valid = function()
        return true
      end
      vim.api.nvim_win_close = function() end
      vim.keymap.set = function(_, lhs, rhs)
        keymaps[lhs] = rhs
      end
      vim.cmd = function() end

      input.get_instruction({ input = { prompt = "AI Edit: ", multiline = { enabled = true } } }, function()
        callback_called = true
      end)

      keymaps["<C-s>"]()

      vim.api.nvim_create_buf = original_create_buf
      vim.api.nvim_buf_set_option = original_buf_set_option
      vim.api.nvim_buf_set_lines = original_buf_set_lines
      vim.api.nvim_buf_get_lines = original_buf_get_lines
      vim.api.nvim_open_win = original_open_win
      vim.api.nvim_win_is_valid = original_win_is_valid
      vim.api.nvim_win_close = original_win_close
      vim.keymap.set = original_keymap_set
      vim.cmd = original_cmd

      assert.is_false(callback_called)
    end)

    it("should attach mention completion in multiline mode when Snacks picker is available", function()
      local original_create_buf = vim.api.nvim_create_buf
      local original_buf_set_option = vim.api.nvim_buf_set_option
      local original_buf_set_lines = vim.api.nvim_buf_set_lines
      local original_open_win = vim.api.nvim_open_win
      local original_keymap_set = vim.keymap.set
      local original_cmd = vim.cmd
      local keymap_calls = {}

      package.loaded["snacks"] = {
        picker = {
          pick = function() end,
        },
      }

      vim.api.nvim_create_buf = function()
        return 100
      end

      vim.api.nvim_buf_set_option = function() end
      vim.api.nvim_buf_set_lines = function() end
      vim.api.nvim_open_win = function()
        return 101
      end
      vim.keymap.set = function(mode, lhs, _, opts)
        table.insert(keymap_calls, {
          mode = mode,
          lhs = lhs,
          opts = opts,
        })
      end
      vim.cmd = function() end

      input.get_instruction({ input = { prompt = "AI Edit: ", multiline = { enabled = true } } }, function() end)

      vim.api.nvim_create_buf = original_create_buf
      vim.api.nvim_buf_set_option = original_buf_set_option
      vim.api.nvim_buf_set_lines = original_buf_set_lines
      vim.api.nvim_open_win = original_open_win
      vim.keymap.set = original_keymap_set
      vim.cmd = original_cmd
      package.loaded["snacks"] = nil

      assert.equals(4, #keymap_calls)
      assert.same({ "i", "n" }, keymap_calls[1].mode)
      assert.equals("<C-s>", keymap_calls[1].lhs)
      assert.equals("n", keymap_calls[2].mode)
      assert.equals("<CR>", keymap_calls[2].lhs)
      assert.same({ "i", "n" }, keymap_calls[3].mode)
      assert.equals("<Esc>", keymap_calls[3].lhs)
      assert.equals("i", keymap_calls[4].mode)
      assert.equals("@", keymap_calls[4].lhs)
      assert.equals(100, keymap_calls[4].opts.buffer)
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
          pick = function() end,
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
          pick = function(opts)
            assert.equals("input", opts.focus)
            assert.is_true(opts.enter)
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

    it("should insert @buffer from the mention picker", function()
      local current_buf = vim.api.nvim_get_current_buf()
      local current_win = vim.api.nvim_get_current_win()

      vim.api.nvim_buf_set_lines(current_buf, 0, -1, false, { "@" })
      vim.api.nvim_win_set_cursor(current_win, { 1, 1 })

      local snacks = {
        picker = {
          pick = function(opts)
            assert.equals("input", opts.focus)
            assert.is_true(opts.enter)
            assert.equals(2, #opts.multi)
            local items = opts.multi[1].finder()
            assert.equals("@buffer", items[1].text)
            assert.equals("buffer", items[1].mention)
            opts.confirm({ close = function() end }, { mention = "buffer", text = "@buffer" })
          end,
        },
      }

      input.open_mention_picker(snacks, { buf = current_buf, win = current_win })

      vim.wait(1000, function()
        return vim.api.nvim_buf_get_lines(current_buf, 0, 1, false)[1] == "@buffer"
      end)

      assert.equals("@buffer", vim.api.nvim_buf_get_lines(current_buf, 0, 1, false)[1])
    end)
  end)
end)
