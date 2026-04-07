describe("nvim-redraft", function()
  local repo_root = vim.fn.getcwd()
  local module_names = {
    "nvim-redraft",
    "nvim-redraft.selection",
    "nvim-redraft.input",
    "nvim-redraft.ipc",
    "nvim-redraft.replace",
    "nvim-redraft.logger",
    "nvim-redraft.spinner",
    "nvim-redraft.model_selector",
    "nvim-redraft.diff",
    "nvim-redraft.mentions",
  }

  local function with_stubbed_modules(stubs, callback)
    local original_modules = {}
    for _, module_name in ipairs(module_names) do
      original_modules[module_name] = package.loaded[module_name]
      package.loaded[module_name] = nil
    end

    for module_name, value in pairs(stubs) do
      package.loaded[module_name] = value
    end

    local ok, err = pcall(callback)

    for module_name, value in pairs(original_modules) do
      package.loaded[module_name] = value
    end

    if not ok then
      error(err)
    end
  end

  it("sends cleaned instructions and context files to the service", function()
    local captured_request
    local original_cwd = vim.fn.getcwd()
    local temp_dir = vim.fn.tempname()
    local bufnr = vim.api.nvim_get_current_buf()
    local original_filetype = vim.bo[bufnr].filetype

    vim.fn.mkdir(temp_dir, "p")
    vim.fn.chdir(temp_dir)
    vim.fn.writefile({ "return helper" }, temp_dir .. "/helper.lua")
    vim.api.nvim_buf_set_name(0, temp_dir .. "/current.lua")
    vim.bo[bufnr].filetype = "lua"

    with_stubbed_modules({
      ["nvim-redraft.selection"] = {
        get_visual_selection = function()
          return {
            text = "local x = 1",
            context_text = "before\n__NVIM_REDRAFT_SELECTION_START__local x = 1__NVIM_REDRAFT_SELECTION_END__\nafter",
            context_start_line = 1,
            context_end_line = 3,
            start_line = 1,
            end_line = 1,
            start_col = 0,
            end_col = 10,
          }
        end,
      },
      ["nvim-redraft.input"] = {
        get_instruction = function(_, callback)
          callback("refactor this using @helper.lua")
        end,
      },
      ["nvim-redraft.ipc"] = {
        config = {},
        send_request = function(params, callback)
          captured_request = params
          callback("updated", nil)
        end,
        stop_service = function() end,
      },
      ["nvim-redraft.replace"] = {
        replace_selection = function() end,
      },
      ["nvim-redraft.logger"] = {
        init = function() end,
        info = function() end,
        debug = function() end,
        error = function() end,
        warn = function() end,
      },
      ["nvim-redraft.spinner"] = {
        start = function() end,
        stop = function() end,
      },
      ["nvim-redraft.model_selector"] = {
        get_model_selection = function() end,
      },
      ["nvim-redraft.diff"] = {
        inject_conflict_markers = function() end,
      },
      ["nvim-redraft.mentions"] = dofile(repo_root .. "/lua/nvim-redraft/mentions.lua"),
    }, function()
      local redraft = dofile(repo_root .. "/lua/nvim-redraft.lua")
      redraft.config.llm.models = {
        { provider = "openai", model = "gpt-4o-mini" },
      }
      redraft.config.llm.current_index = 1
      redraft.edit()
    end)

    vim.fn.chdir(original_cwd)
    vim.bo[bufnr].filetype = original_filetype

    assert.is_not_nil(captured_request)
    assert.equals("refactor this using", captured_request.instruction)
    assert.equals(
      "before\n__NVIM_REDRAFT_SELECTION_START__local x = 1__NVIM_REDRAFT_SELECTION_END__\nafter",
      captured_request.selectionContext
    )
    assert.equals(1, #captured_request.contextFiles)
    assert.equals("helper.lua", captured_request.contextFiles[1].path)
    assert.equals("lua", captured_request.filetype)
    assert.is_true(captured_request.systemPrompt:find("Selection edit requests may include surrounding selection context", 1, true) ~= nil)
    assert.is_true(captured_request.systemPrompt:find("The surrounding context is read-only and MUST NOT be edited.", 1, true) ~= nil)
    assert.is_true(captured_request.systemPrompt:find("Direct-apply mode is enabled for selection edits.", 1, true) ~= nil)
    assert.is_true(captured_request.systemPrompt:find("Do not return a diff, patch, conflict markers", 1, true) ~= nil)
    assert.is_nil(captured_request.systemPrompt:find("When editing Python, preserve syntactic indentation exactly.", 1, true))
  end)

  it("adds Python-specific indentation guidance for selection edits in Python buffers", function()
    local captured_request
    local bufnr = vim.api.nvim_get_current_buf()
    local original_filetype = vim.bo[bufnr].filetype

    vim.bo[bufnr].filetype = "python"

    with_stubbed_modules({
      ["nvim-redraft.selection"] = {
        get_visual_selection = function()
          return {
            text = "print('hi')",
            context_text = "def main():\n    __NVIM_REDRAFT_SELECTION_START__print('hi')__NVIM_REDRAFT_SELECTION_END__",
            context_start_line = 1,
            context_end_line = 2,
            start_line = 2,
            end_line = 2,
            start_col = 4,
            end_col = 15,
          }
        end,
      },
      ["nvim-redraft.input"] = {
        get_instruction = function(_, callback)
          callback("add logging")
        end,
      },
      ["nvim-redraft.ipc"] = {
        config = {},
        send_request = function(params, callback)
          captured_request = params
          callback("updated", nil)
        end,
        stop_service = function() end,
      },
      ["nvim-redraft.replace"] = {
        replace_selection = function() end,
      },
      ["nvim-redraft.logger"] = {
        init = function() end,
        info = function() end,
        debug = function() end,
        error = function() end,
        warn = function() end,
      },
      ["nvim-redraft.spinner"] = {
        start = function() end,
        stop = function() end,
      },
      ["nvim-redraft.model_selector"] = {
        get_model_selection = function() end,
      },
      ["nvim-redraft.diff"] = {
        inject_conflict_markers = function() end,
      },
      ["nvim-redraft.mentions"] = {
        parse = function(instruction)
          return {
            instruction = instruction,
            context_files = {},
            skipped_mentions = {},
          }
        end,
        get_workspace_root = function()
          return vim.fn.getcwd()
        end,
      },
    }, function()
      local redraft = dofile(repo_root .. "/lua/nvim-redraft.lua")
      redraft.config.llm.models = {
        { provider = "openai", model = "gpt-4o-mini" },
      }
      redraft.config.llm.current_index = 1
      redraft.edit()
    end)

    vim.bo[bufnr].filetype = original_filetype

    assert.is_not_nil(captured_request)
    assert.equals("python", captured_request.filetype)
    assert.is_true(captured_request.systemPrompt:find("When editing Python, preserve syntactic indentation exactly.", 1, true) ~= nil)
    assert.is_true(captured_request.systemPrompt:find("Use the surrounding code as the source of truth for indentation depth, tabs vs spaces, and block structure.", 1, true) ~= nil)
  end)

  it("adds diff-mode-specific output instructions for selection edits", function()
    local captured_request

    with_stubbed_modules({
      ["nvim-redraft.selection"] = {
        get_visual_selection = function()
          return {
            text = "local x = 1",
            context_text = "before\n__NVIM_REDRAFT_SELECTION_START__local x = 1__NVIM_REDRAFT_SELECTION_END__\nafter",
            context_start_line = 1,
            context_end_line = 3,
            start_line = 1,
            end_line = 1,
            start_col = 0,
            end_col = 10,
          }
        end,
      },
      ["nvim-redraft.input"] = {
        get_instruction = function(_, callback)
          callback("rewrite this")
        end,
      },
      ["nvim-redraft.ipc"] = {
        config = {},
        send_request = function(params, callback)
          captured_request = params
          callback("updated", nil)
        end,
        stop_service = function() end,
      },
      ["nvim-redraft.replace"] = {
        replace_selection = function() end,
      },
      ["nvim-redraft.logger"] = {
        init = function() end,
        info = function() end,
        debug = function() end,
        error = function() end,
        warn = function() end,
      },
      ["nvim-redraft.spinner"] = {
        start = function() end,
        stop = function() end,
      },
      ["nvim-redraft.model_selector"] = {
        get_model_selection = function() end,
      },
      ["nvim-redraft.diff"] = {
        inject_conflict_markers = function() end,
      },
      ["nvim-redraft.mentions"] = {
        parse = function(instruction)
          return {
            instruction = instruction,
            context_files = {},
            skipped_mentions = {},
          }
        end,
        get_workspace_root = function()
          return vim.fn.getcwd()
        end,
      },
    }, function()
      local redraft = dofile(repo_root .. "/lua/nvim-redraft.lua")
      redraft.config.llm.models = {
        { provider = "openai", model = "gpt-4o-mini" },
      }
      redraft.config.llm.current_index = 1
      redraft.config.diff_mode = true
      redraft.edit()
    end)

    assert.is_not_nil(captured_request)
    assert.is_true(captured_request.systemPrompt:find("Diff mode is enabled for selection edits.", 1, true) ~= nil)
    assert.is_true(captured_request.systemPrompt:find("Do not return conflict markers, a unified diff, a patch", 1, true) ~= nil)
  end)

  it("uses the configured selection context radius for visual edits", function()
    local captured_radius

    with_stubbed_modules({
      ["nvim-redraft.selection"] = {
        get_visual_selection = function(radius)
          captured_radius = radius
          return {
            text = "local x = 1",
            context_text = "__NVIM_REDRAFT_SELECTION_START__local x = 1__NVIM_REDRAFT_SELECTION_END__",
            context_start_line = 1,
            context_end_line = 1,
            start_line = 1,
            end_line = 1,
            start_col = 0,
            end_col = 10,
          }
        end,
      },
      ["nvim-redraft.input"] = {
        get_instruction = function(_, callback)
          callback("rewrite this")
        end,
      },
      ["nvim-redraft.ipc"] = {
        config = {},
        send_request = function(_, callback)
          callback("updated", nil)
        end,
        stop_service = function() end,
      },
      ["nvim-redraft.replace"] = {
        replace_selection = function() end,
      },
      ["nvim-redraft.logger"] = {
        init = function() end,
        info = function() end,
        debug = function() end,
        error = function() end,
        warn = function() end,
      },
      ["nvim-redraft.spinner"] = {
        start = function() end,
        stop = function() end,
      },
      ["nvim-redraft.model_selector"] = {
        get_model_selection = function() end,
      },
      ["nvim-redraft.diff"] = {
        inject_conflict_markers = function() end,
      },
      ["nvim-redraft.mentions"] = {
        parse = function(instruction)
          return {
            instruction = instruction,
            context_files = {},
            skipped_mentions = {},
          }
        end,
        get_workspace_root = function()
          return vim.fn.getcwd()
        end,
      },
    }, function()
      local redraft = dofile(repo_root .. "/lua/nvim-redraft.lua")
      redraft.setup({
        selection_context_radius = 12,
        keys = {},
        llm = {
          models = {
            { provider = "openai", model = "gpt-4o-mini" },
          },
        },
      })
      redraft.edit()
    end)

    assert.equals(12, captured_radius)
  end)

  it("validates selection_context_radius during setup", function()
    with_stubbed_modules({
      ["nvim-redraft.selection"] = {},
      ["nvim-redraft.input"] = {},
      ["nvim-redraft.ipc"] = { config = {}, stop_service = function() end },
      ["nvim-redraft.replace"] = {},
      ["nvim-redraft.logger"] = { init = function() end },
      ["nvim-redraft.spinner"] = {},
      ["nvim-redraft.model_selector"] = {},
      ["nvim-redraft.diff"] = {},
      ["nvim-redraft.mentions"] = {},
    }, function()
      local redraft = dofile(repo_root .. "/lua/nvim-redraft.lua")

      assert.has_error(function()
        redraft.setup({ selection_context_radius = -1, keys = {} })
      end, "selection_context_radius must be a non-negative number")
    end)
  end)

  it("validates input.multiline.enabled during setup", function()
    with_stubbed_modules({
      ["nvim-redraft.selection"] = {},
      ["nvim-redraft.input"] = {},
      ["nvim-redraft.ipc"] = { config = {}, stop_service = function() end },
      ["nvim-redraft.replace"] = {},
      ["nvim-redraft.logger"] = { init = function() end },
      ["nvim-redraft.spinner"] = {},
      ["nvim-redraft.model_selector"] = {},
      ["nvim-redraft.diff"] = {},
      ["nvim-redraft.mentions"] = {},
    }, function()
      local redraft = dofile(repo_root .. "/lua/nvim-redraft.lua")

      assert.has_error(function()
        redraft.setup({ input = { multiline = { enabled = "yes" } }, keys = {} })
      end, "input.multiline.enabled must be a boolean")
    end)
  end)

  it("sends cursor context and inserts directly in normal mode", function()
    local captured_request
    local inserted_position
    local inserted_text
    local diff_called = false
    local bufnr = vim.api.nvim_get_current_buf()
    local original_filetype = vim.bo[bufnr].filetype

    vim.bo[bufnr].filetype = "lua"

    with_stubbed_modules({
      ["nvim-redraft.selection"] = {
        get_visual_selection = function()
          error("visual selection should not be used")
        end,
        get_cursor_context = function()
          return {
            bufnr = bufnr,
            text = "before\n__NVIM_REDRAFT_CURSOR__after",
            start_line = 5,
            end_line = 6,
            cursor_line = 6,
            cursor_col = 2,
          }
        end,
      },
      ["nvim-redraft.input"] = {
        get_instruction = function(_, callback)
          callback("add logging")
        end,
      },
      ["nvim-redraft.ipc"] = {
        config = {},
        send_request = function(params, callback)
          captured_request = params
          callback("print('hi')", nil)
        end,
        stop_service = function() end,
      },
      ["nvim-redraft.replace"] = {
        replace_selection = function()
          error("selection replacement should not be used")
        end,
        insert_at_cursor = function(position, text)
          inserted_position = position
          inserted_text = text
        end,
      },
      ["nvim-redraft.logger"] = {
        init = function() end,
        info = function() end,
        debug = function() end,
        error = function() end,
        warn = function() end,
      },
      ["nvim-redraft.spinner"] = {
        start = function() end,
        stop = function() end,
      },
      ["nvim-redraft.model_selector"] = {
        get_model_selection = function() end,
      },
      ["nvim-redraft.diff"] = {
        inject_conflict_markers = function()
          diff_called = true
        end,
      },
      ["nvim-redraft.mentions"] = {
        parse = function(instruction)
          return {
            instruction = instruction,
            context_files = {},
            skipped_mentions = {},
          }
        end,
        get_workspace_root = function()
          return vim.fn.getcwd()
        end,
      },
    }, function()
      local redraft = dofile(repo_root .. "/lua/nvim-redraft.lua")
      redraft.config.llm.models = {
        { provider = "openai", model = "gpt-4o-mini" },
      }
      redraft.config.llm.current_index = 1
      redraft.config.diff_mode = true
      redraft.insert()
    end)

    vim.bo[bufnr].filetype = original_filetype

    assert.is_not_nil(captured_request)
    assert.equals("lua", captured_request.filetype)
    assert.equals("before\n__NVIM_REDRAFT_CURSOR__after", captured_request.code)
    assert.is_true(captured_request.systemPrompt:find("Return ONLY the code that should be inserted", 1, true) ~= nil)
    assert.is_nil(captured_request.systemPrompt:find("For Python insertions, the indentation of the inserted code MUST match the block indentation at __NVIM_REDRAFT_CURSOR__.", 1, true))
    assert.is_false(diff_called)
    assert.same({ bufnr = bufnr, line = 6, col = 2 }, inserted_position)
    assert.equals("print('hi')", inserted_text)
  end)

  it("adds Python-specific indentation guidance for insert mode in Python buffers", function()
    local captured_request
    local bufnr = vim.api.nvim_get_current_buf()
    local original_filetype = vim.bo[bufnr].filetype

    vim.bo[bufnr].filetype = "python"

    with_stubbed_modules({
      ["nvim-redraft.selection"] = {
        get_visual_selection = function()
          error("visual selection should not be used")
        end,
        get_cursor_context = function()
          return {
            bufnr = bufnr,
            text = "def main():\n    __NVIM_REDRAFT_CURSOR__pass",
            start_line = 1,
            end_line = 2,
            cursor_line = 2,
            cursor_col = 4,
          }
        end,
      },
      ["nvim-redraft.input"] = {
        get_instruction = function(_, callback)
          callback("add logging")
        end,
      },
      ["nvim-redraft.ipc"] = {
        config = {},
        send_request = function(params, callback)
          captured_request = params
          callback("print('hi')", nil)
        end,
        stop_service = function() end,
      },
      ["nvim-redraft.replace"] = {
        replace_selection = function()
          error("selection replacement should not be used")
        end,
        insert_at_cursor = function() end,
      },
      ["nvim-redraft.logger"] = {
        init = function() end,
        info = function() end,
        debug = function() end,
        error = function() end,
        warn = function() end,
      },
      ["nvim-redraft.spinner"] = {
        start = function() end,
        stop = function() end,
      },
      ["nvim-redraft.model_selector"] = {
        get_model_selection = function() end,
      },
      ["nvim-redraft.diff"] = {
        inject_conflict_markers = function() end,
      },
      ["nvim-redraft.mentions"] = {
        parse = function(instruction)
          return {
            instruction = instruction,
            context_files = {},
            skipped_mentions = {},
          }
        end,
        get_workspace_root = function()
          return vim.fn.getcwd()
        end,
      },
    }, function()
      local redraft = dofile(repo_root .. "/lua/nvim-redraft.lua")
      redraft.config.llm.models = {
        { provider = "openai", model = "gpt-4o-mini" },
      }
      redraft.config.llm.current_index = 1
      redraft.insert()
    end)

    vim.bo[bufnr].filetype = original_filetype

    assert.is_not_nil(captured_request)
    assert.equals("python", captured_request.filetype)
    assert.is_true(captured_request.systemPrompt:find("When editing Python, preserve syntactic indentation exactly.", 1, true) ~= nil)
    assert.is_true(captured_request.systemPrompt:find("For Python insertions, the indentation of the inserted code MUST match the block indentation at __NVIM_REDRAFT_CURSOR__.", 1, true) ~= nil)
  end)
end)
