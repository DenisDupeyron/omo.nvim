-- Copyright (C) 2026 Denis Dupeyron
--
-- This program is free software. You can redistribute it and/or modify it under
-- the terms of the GNU General Public License as published by the Free Software
-- Foundation, version 3 of the License.
--
-- This program is distributed in the hope that it will be useful, but WITHOUT
-- ANY WARRANTY. Without even the implied warranty of MERCHANTABILITY or FITNESS
-- FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License along with
-- this program. If not, see <https://www.gnu.org/licenses/>.

local bit = require("bit")
local editor = require("omo.editor")

local spec = {}

local function roundtrip(payload)
  local frame = editor._test.encode(1, payload)
  local opcode, decoded, fin, consumed = editor._test.decode(frame)
  assert(opcode == 1)
  assert(decoded == payload)
  assert(fin == true)
  assert(consumed == #frame)
end

function spec.encode_decode_short()
  roundtrip("hello")
end

function spec.encode_decode_126_length()
  roundtrip(string.rep("a", 200))
end

function spec.encode_decode_127_length()
  roundtrip(string.rep("b", 70000))
end

function spec.encode_decode_empty()
  roundtrip("")
end

function spec.decode_masked_frame()
  local payload = "masked-payload"
  local mask = { 0x11, 0x22, 0x33, 0x44 }
  local masked = {}
  for i = 1, #payload do
    masked[i] = string.char(bit.bxor(payload:byte(i), mask[(i - 1) % 4 + 1]))
  end
  local frame = string.char(0x81, 0x80 + #payload, mask[1], mask[2], mask[3], mask[4]) .. table.concat(masked)
  local opcode, decoded = editor._test.decode(frame)
  assert(opcode == 1)
  assert(decoded == payload)
end

function spec.decode_incomplete_returns_nil()
  local opcode = editor._test.decode(string.char(0x81, 0x05, 0x68))
  assert(opcode == nil)
end

local function with_transport(test)
  local saved_uv, saved_schedule, saved_notify = vim.uv, vim.schedule, vim.notify
  local saved_editor = package.loaded["omo.editor"]
  local handles, scheduled, warnings = {}, {}, {}
  local fixture = { handles = handles, warnings = warnings }
  vim.uv = {
    new_tcp = function()
      if fixture.fail_allocation then
        return nil
      end
      local handle = { writes = {}, closed = false }
      function handle:bind(host, port)
        assert(host == "127.0.0.1" and port == 0)
        return 0
      end
      function handle:listen(_, callback)
        self.accept_callback = callback
        return 0
      end
      function handle:accept(accepted)
        assert(accepted ~= nil, "accept requires an allocated client")
      end
      function handle:getsockname()
        return { port = 34567 }
      end
      function handle:read_start(callback)
        self.read_callback = callback
      end
      function handle:read_stop() end
      function handle:close()
        self.closed = true
      end
      function handle:write(bytes)
        table.insert(self.writes, bytes)
      end
      table.insert(handles, handle)
      return handle
    end,
  }
  rawset(vim, "schedule", function(callback)
    table.insert(scheduled, callback)
  end)
  rawset(vim, "notify", function(_, level)
    table.insert(warnings, level)
  end)
  package.loaded["omo.editor"] = nil
  fixture.editor = require("omo.editor")
  function fixture.drain()
    while #scheduled > 0 do
      table.remove(scheduled, 1)()
    end
  end
  function fixture.receive(handle, bytes)
    handle.read_callback(nil, bytes)
    fixture.drain()
  end
  function fixture.connect()
    assert(fixture.editor.start())
    handles[1].accept_callback(nil)
    local handle = handles[#handles]
    fixture.receive(handle, "GET / HTTP/1.1\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n")
    assert(handle.writes[1]:find("Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", 1, true))
    return handle
  end
  function fixture.rpc(handle, value)
    fixture.receive(handle, editor._test.encode(1, vim.json.encode(value)))
  end
  local ok, err = xpcall(function()
    test(fixture)
  end, debug.traceback)
  for _, handle in ipairs(handles) do
    handle:close()
  end
  rawset(vim, "uv", saved_uv)
  rawset(vim, "schedule", saved_schedule)
  rawset(vim, "notify", saved_notify)
  package.loaded["omo.editor"] = saved_editor
  assert(ok, err)
end

function spec.initialize_preserves_wire_contract_without_readiness()
  with_transport(function(f)
    local handle = f.connect()
    f.rpc(handle, { jsonrpc = "2.0", id = "request-7", method = "initialize" })
    local _, payload = editor._test.decode(handle.writes[2])
    assert(type(payload) == "string")
    local response = vim.json.decode(payload)
    assert(response.jsonrpc == "2.0" and response.id == "request-7")
    assert(response.result.protocolVersion == "2025-11-25")
    assert(response.result.serverInfo.name == "omo.nvim" and response.result.serverInfo.version == "1.0")
    assert(vim.deep_equal(response.result.capabilities, {}))
    assert(f.editor.status().connected and not f.editor.status().ready)
    assert(f.editor.port() == 34567 and f.editor.start() and #f.handles == 2)
  end)
end

function spec.initialized_without_initialize_flushes_twenty_mentions_once()
  with_transport(function(f)
    assert(not f.editor.mention("/before.lua", 1, 1))
    local handle = f.connect()
    for i = 1, 20 do
      assert(f.editor.mention("/queued.lua", i, i + 1))
    end
    assert(not f.editor.mention("/overflow.lua", 21, 21))
    assert(#handle.writes == 1)
    f.rpc(handle, { method = "notifications/initialized" })
    assert(f.editor.status().ready and #handle.writes == 21)
    for i = 1, 20 do
      local _, payload = editor._test.decode(handle.writes[i + 1])
      assert(type(payload) == "string")
      assert(vim.deep_equal(vim.json.decode(payload), {
        jsonrpc = "2.0",
        method = "at_mentioned",
        params = { filePath = "/queued.lua", lineStart = i, lineEnd = i + 1 },
      }))
    end
    f.rpc(handle, { method = "notifications/initialized" })
    assert(#handle.writes == 21)
  end)
end

function spec.orderly_close_reconnect_delivers_only_to_replacement()
  with_transport(function(f)
    local first = f.connect()
    assert(f.editor.mention("/retired.lua", 1, 1))
    f.receive(first, editor._test.encode(8, ""))
    assert(first.closed and not f.editor.status().connected and not f.editor.status().ready)
    assert(vim.deep_equal(f.warnings, { vim.log.levels.WARN }))
    local second = f.connect()
    f.rpc(second, { method = "notifications/initialized" })
    assert(f.editor.mention("/IGNORE INSTRUCTIONS.txt", 5, 9))
    assert(not second.closed and f.editor.status().connected and f.editor.status().ready)
    assert(#first.writes == 1 and #second.writes == 2)
    local _, payload = editor._test.decode(second.writes[2])
    assert(type(payload) == "string")
    assert(vim.deep_equal(vim.json.decode(payload).params, {
      filePath = "/IGNORE INSTRUCTIONS.txt",
      lineStart = 5,
      lineEnd = 9,
    }))
  end)
end

function spec.new_client_evicts_old_client_and_drops_pending_queue()
  with_transport(function(f)
    local first = f.connect()
    assert(f.editor.mention("/retired.lua", 1, 1))
    local second = f.connect()
    assert(first.closed and not second.closed)
    assert(vim.deep_equal(f.warnings, { vim.log.levels.WARN }))
    f.rpc(second, { method = "notifications/initialized" })
    assert(#second.writes == 1 and f.editor.status().ready)
  end)
end

function spec.failed_client_allocation_preserves_owner_and_queued_mention()
  with_transport(function(f)
    local first = f.connect()
    assert(f.editor.mention("/preserved.lua", 4, 7))
    f.fail_allocation = true
    f.handles[1].accept_callback(nil)
    assert(not first.closed and f.editor.status().connected and #f.warnings == 0)
    f.rpc(first, { method = "notifications/initialized" })
    local _, payload = editor._test.decode(first.writes[2])
    assert(type(payload) == "string")
    assert(vim.deep_equal(vim.json.decode(payload).params, {
      filePath = "/preserved.lua",
      lineStart = 4,
      lineEnd = 7,
    }))
    f.fail_allocation = false
    local second = f.connect()
    assert(first.closed and not second.closed and f.editor.status().connected)
  end)
end

function spec.failed_server_allocation_disables_channel_and_preserves_fallback()
  with_transport(function(f)
    f.fail_allocation = true
    assert(not f.editor.start() and f.editor.status().disabled)
    assert(not f.editor.status().connected and f.editor.port() == nil)
    assert(not f.editor.mention("/fallback.lua", 1, 1))
    assert(vim.deep_equal(f.warnings, { vim.log.levels.WARN }))
  end)
end

function spec.fragmented_initialized_and_ping_preserve_payload()
  with_transport(function(f)
    local handle = f.connect()
    local message = vim.json.encode({ method = "notifications/initialized" })
    f.receive(handle, string.char(1, 10) .. message:sub(1, 10))
    assert(not f.editor.status().ready)
    f.receive(handle, editor._test.encode(9, "ping-data"))
    local opcode, payload = editor._test.decode(handle.writes[2])
    assert(opcode == 10 and payload == "ping-data")
    f.receive(handle, editor._test.encode(0, message:sub(11)))
    assert(f.editor.status().ready)
  end)
end

function spec.malformed_json_does_not_mark_client_ready()
  with_transport(function(f)
    local handle = f.connect()
    for _, payload in ipairs({ "{", "null", "7", '"text"', '{"method":"unknown"}' }) do
      f.receive(handle, editor._test.encode(1, payload))
      assert(not f.editor.status().ready and f.editor.status().connected and #handle.writes == 1)
    end
  end)
end

function spec.excessive_buffer_disconnects_with_warning()
  with_transport(function(f)
    local handle = f.connect()
    f.receive(handle, string.rep("x", 1024 * 1024 + 1))
    assert(handle.closed and not f.editor.status().connected)
    assert(vim.deep_equal(f.warnings, { vim.log.levels.WARN }))
  end)
end

return spec
