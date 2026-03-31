local mentions = require("nvim-redraft.mentions")

describe("mentions", function()
  local original_cwd
  local temp_dir

  before_each(function()
    original_cwd = vim.fn.getcwd()
    temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")
    vim.fn.chdir(temp_dir)
    vim.api.nvim_buf_set_name(0, temp_dir .. "/current.lua")
    vim.fn.writefile({ "return helper" }, temp_dir .. "/helper.lua")
    vim.fn.mkdir(temp_dir .. "/docs", "p")
    vim.fn.writefile({ "hello docs" }, temp_dir .. "/docs/my file.md")
  end)

  after_each(function()
    vim.fn.chdir(original_cwd)
  end)

  it("parses and resolves unquoted mentions", function()
    local result = mentions.parse("refactor this using @helper.lua", {
      workspace_root = temp_dir,
    })

    assert.equals("refactor this using", result.instruction)
    assert.equals(1, #result.context_files)
    assert.equals("helper.lua", result.context_files[1].path)
    assert.equals(temp_dir .. "/helper.lua", result.context_files[1].absolutePath)
  end)

  it("parses quoted mentions with spaces", function()
    local result = mentions.parse('rewrite docs using @"docs/my file.md"', {
      workspace_root = temp_dir,
    })

    assert.equals("rewrite docs using", result.instruction)
    assert.equals("docs/my file.md", result.context_files[1].path)
  end)

  it("skips invalid mentions without failing", function()
    local result = mentions.parse("update this with @missing.lua", {
      workspace_root = temp_dir,
    })

    assert.equals("update this with", result.instruction)
    assert.same({ "missing.lua" }, result.skipped_mentions)
    assert.equals(0, #result.context_files)
  end)

  it("deduplicates repeated mentions", function()
    local result = mentions.parse("use @helper.lua and @helper.lua", {
      workspace_root = temp_dir,
    })

    assert.equals(1, #result.context_files)
  end)

  it("preserves escaped at signs", function()
    local result = mentions.parse("keep \\@literal and use @helper.lua", {
      workspace_root = temp_dir,
    })

    assert.equals("keep @literal and use", result.instruction)
    assert.equals(1, #result.context_files)
  end)

  it("resolves @buffer to current buffer content", function()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local value = 1", "return value" })

    local result = mentions.parse("update this using @buffer", {
      workspace_root = temp_dir,
    })

    assert.equals("update this using", result.instruction)
    assert.equals(1, #result.context_files)
    assert.equals("current.lua", result.context_files[1].path)
    assert.equals("local value = 1\nreturn value", result.context_files[1].content)
  end)
end)
