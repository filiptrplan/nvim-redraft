describe("nvim-redraft", function()
  it("sends cleaned instructions and context files to the service", function()
    local repo_root = vim.fn.getcwd()
    local original_modules = {}
    for _, module_name in ipairs({
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
    }) do
      original_modules[module_name] = package.loaded[module_name]
    end

    package.loaded["nvim-redraft"] = nil
    package.loaded["nvim-redraft.selection"] = {
      get_visual_selection = function()
        return {
          text = "local x = 1",
          start_line = 1,
          end_line = 1,
          start_col = 0,
          end_col = 10,
        }
      end,
    }
    package.loaded["nvim-redraft.input"] = {
      get_instruction = function(_, callback)
        callback("refactor this using @helper.lua")
      end,
    }

    local captured_request
    package.loaded["nvim-redraft.ipc"] = {
      config = {},
      send_request = function(params, callback)
        captured_request = params
        callback("updated", nil)
      end,
      stop_service = function() end,
    }
    package.loaded["nvim-redraft.replace"] = {
      replace_selection = function() end,
    }
    package.loaded["nvim-redraft.logger"] = {
      init = function() end,
      info = function() end,
      debug = function() end,
      error = function() end,
      warn = function() end,
    }
    package.loaded["nvim-redraft.spinner"] = {
      start = function() end,
      stop = function() end,
    }
    package.loaded["nvim-redraft.model_selector"] = {
      get_model_selection = function() end,
    }
    package.loaded["nvim-redraft.diff"] = {
      inject_conflict_markers = function() end,
    }

    local original_cwd = vim.fn.getcwd()
    local temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")
    vim.fn.chdir(temp_dir)
    vim.fn.writefile({ "return helper" }, temp_dir .. "/helper.lua")
    vim.api.nvim_buf_set_name(0, temp_dir .. "/current.lua")
    package.loaded["nvim-redraft.mentions"] = dofile(repo_root .. "/lua/nvim-redraft/mentions.lua")

    local redraft = dofile(repo_root .. "/lua/nvim-redraft.lua")
    redraft.config.llm.models = {
      { provider = "openai", model = "gpt-4o-mini" },
    }
    redraft.config.llm.current_index = 1
    redraft.edit()

    vim.fn.chdir(original_cwd)

    for module_name, value in pairs(original_modules) do
      package.loaded[module_name] = value
    end

    assert.is_not_nil(captured_request)
    assert.equals("refactor this using", captured_request.instruction)
    assert.equals(1, #captured_request.contextFiles)
    assert.equals("helper.lua", captured_request.contextFiles[1].path)
  end)
end)
