local ipc = require("nvim-redraft.ipc")

describe("ipc", function()
  after_each(function()
    ipc.stop_service()
  end)

  describe("service lifecycle", function()
    it("should start service successfully", function()
      local started = ipc.start_service()
      assert.is_true(started)
      assert.is_not_nil(ipc.job_id)
    end)

    it("should reuse existing service", function()
      ipc.start_service()
      local first_job = ipc.job_id

      ipc.start_service()
      local second_job = ipc.job_id

      assert.equals(first_job, second_job)
    end)

    it("should stop service cleanly", function()
      ipc.start_service()
      assert.is_not_nil(ipc.job_id)

      ipc.stop_service()
      assert.is_nil(ipc.job_id)
    end)
  end)

  describe("request handling", function()
    it("should send request and receive response", function()
      local original_start_service = ipc.start_service
      local original_chansend = vim.fn.chansend
      local result_text = nil
      local done = false

      ipc.start_service = function()
        ipc.job_id = 99
        return true
      end

      vim.fn.chansend = function(_, data)
        local request = vim.fn.json_decode(data)
        ipc.handle_response(vim.fn.json_encode({
          id = request.id,
          result = "const x = 1;",
        }))
      end

      ipc.send_request({
        code = "const x = 1",
        instruction = "add semicolon",
        systemPrompt = "test",
      }, function(result, error)
        done = true
        result_text = result
      end)

      ipc.start_service = original_start_service
      vim.fn.chansend = original_chansend

      assert.is_true(done)
      assert.equals("const x = 1;", result_text)
    end)

    it("should encode context files in the request payload", function()
      local original_start_service = ipc.start_service
      local original_chansend = vim.fn.chansend
      local payload = nil

      ipc.start_service = function()
        ipc.job_id = 99
        return true
      end

      vim.fn.chansend = function(_, data)
        payload = vim.fn.json_decode(data)
      end

      ipc.send_request({
        code = "const x = 1",
        instruction = "use helper",
        contextFiles = {
          { path = "helper.lua", absolutePath = "/tmp/helper.lua" },
        },
      }, function() end)

      ipc.start_service = original_start_service
      vim.fn.chansend = original_chansend

      assert.equals("helper.lua", payload.params.contextFiles[1].path)
    end)
  end)
end)
