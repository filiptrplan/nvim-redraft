local selection = require("nvim-redraft.selection")

describe("selection", function()
  before_each(function()
    vim.cmd("enew!")
  end)

  describe("get_visual_selection", function()
    it("should return error when not in visual mode", function()
      local result, err = selection.get_visual_selection()
      assert.is_nil(result)
      assert.equals("No active visual selection", err)
    end)

    it("should capture single line selection", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "hello world" })
      vim.cmd("normal! gg0vee")
      vim.cmd("normal! \27")

      local result = selection.get_visual_selection()
      assert.is_not_nil(result)
      assert.equals("hello world", result.text)
      assert.equals(1, result.start_line)
      assert.equals(1, result.end_line)
    end)

    it("should capture multi-line selection", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "line 1", "line 2", "line 3" })
      vim.cmd("normal! ggVjj")
      vim.cmd("normal! \27")

      local result = selection.get_visual_selection()
      assert.is_not_nil(result)
      assert.equals("line 1\nline 2\nline 3", result.text)
      assert.equals(1, result.start_line)
      assert.equals(3, result.end_line)
    end)

    it("should capture partial line character selection", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "hello world foo bar" })
      vim.cmd("normal! gg6lv3l")
      vim.cmd("normal! \27")

      local result = selection.get_visual_selection()
      assert.is_not_nil(result)
      assert.equals("worl", result.text)
      assert.equals(1, result.start_line)
      assert.equals(1, result.end_line)
      assert.equals(
        "hello "
          .. selection.SELECTION_START_MARKER
          .. "worl"
          .. selection.SELECTION_END_MARKER
          .. "d foo bar",
        result.context_text
      )
    end)

    it("should capture character selection across multiple lines", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "first line", "second line", "third line" })
      vim.cmd("normal! gg$vjj0")
      vim.cmd("normal! \27")

      local result = selection.get_visual_selection()
      assert.is_not_nil(result)
      assert.is_true(#result.text > 0)
      assert.equals(1, result.start_line)
      assert.equals(3, result.end_line)
    end)

    it("should return correct column positions", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "hello world" })
      vim.cmd("normal! gg0v4l")
      vim.cmd("normal! \27")

      local result = selection.get_visual_selection()
      assert.is_not_nil(result)
      assert.equals(1, result.start_col)
      assert.is_true(result.end_col > result.start_col)
    end)

    it("should handle empty buffer", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, {})

      local result, err = selection.get_visual_selection()
      assert.is_nil(result)
      assert.equals("No active visual selection", err)
    end)

    it("should handle single empty line", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
      vim.cmd("normal! ggv$")
      vim.cmd("normal! \27")

      local result = selection.get_visual_selection()
      assert.is_not_nil(result)
      assert.equals("", result.text)
    end)

    it("should handle visual line mode selection", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "line 1", "line 2" })
      vim.cmd("normal! ggVj")
      vim.cmd("normal! \27")

      local result = selection.get_visual_selection()
      assert.is_not_nil(result)
      assert.equals("line 1\nline 2", result.text)
      assert.equals(1, result.start_line)
      assert.equals(2, result.end_line)
      assert.equals(
        selection.SELECTION_START_MARKER .. "line 1\nline 2" .. selection.SELECTION_END_MARKER,
        result.context_text
      )
    end)

    it("should handle selection with special characters", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "hello\ttab" })
      vim.cmd("normal! ggV")
      vim.cmd("normal! \27")

      local result = selection.get_visual_selection()
      assert.is_not_nil(result)
      assert.is_true(result.text:find("\t") ~= nil)
    end)

    it("should handle selection at end of buffer", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "line 1", "line 2", "line 3" })
      vim.cmd("normal! GV")
      vim.cmd("normal! \27")

      local result = selection.get_visual_selection()
      assert.is_not_nil(result)
      assert.equals("line 3", result.text)
      assert.equals(3, result.start_line)
      assert.equals(3, result.end_line)
    end)

    it("should include 30 lines of surrounding context by default", function()
      local lines = {}
      for i = 1, 70 do
        lines[i] = string.format("line %d", i)
      end

      vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
      vim.cmd("normal! 35G0V36G")
      vim.cmd("normal! \27")

      local result = selection.get_visual_selection()
      local context_lines = vim.split(result.context_text, "\n", { plain = true })

      assert.is_not_nil(result)
      assert.equals(5, result.context_start_line)
      assert.equals(66, result.context_end_line)
      assert.equals(62, #context_lines)
      assert.equals(selection.SELECTION_START_MARKER .. "line 35", context_lines[31])
      assert.equals("line 36" .. selection.SELECTION_END_MARKER, context_lines[32])
    end)
  end)

  describe("get_cursor_context", function()
    it("should insert the cursor marker at the current column", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local value = 1" })
      vim.api.nvim_win_set_cursor(0, { 1, 6 })

      local result = selection.get_cursor_context(30)

      assert.is_not_nil(result)
      assert.equals("local " .. selection.CURSOR_MARKER .. "value = 1", result.text)
      assert.equals(1, result.cursor_line)
      assert.equals(6, result.cursor_col)
    end)

    it("should clip the context window at the top of the buffer", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three", "four" })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local result = selection.get_cursor_context(2)

      assert.is_not_nil(result)
      assert.equals(1, result.start_line)
      assert.equals(3, result.end_line)
      assert.equals(selection.CURSOR_MARKER .. "one\ntwo\nthree", result.text)
    end)

    it("should clip the context window at the bottom of the buffer", function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three", "four" })
      vim.api.nvim_win_set_cursor(0, { 4, 3 })

      local result = selection.get_cursor_context(2)

      assert.is_not_nil(result)
      assert.equals(2, result.start_line)
      assert.equals(4, result.end_line)
      assert.equals("two\nthree\nfou" .. selection.CURSOR_MARKER .. "r", result.text)
    end)
  end)
end)
