-- Copyright (C) 2026 Denis Dupeyron
--
-- This program is free software. You can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, version 3 of the License.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY. Without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program. If not, see <https://www.gnu.org/licenses/>.

local config = require("omo.config")
local health = require("omo.health")

local spec = {}

function spec.defaults_when_no_opts()
  vim.g.omo_opts = nil
  local opts = config.get()
  assert(opts.height == 0.30)
  assert(opts.width == 0.40)
  assert(opts.side == "right")
  assert(opts.keys.toggle == "<leader>o.")
  assert(opts.keys.range == "<leader>or")
  assert(opts.keys.line == "<leader>ol")
  assert(opts.keys.side == "<leader>os")
end

function spec.merges_user_opts_over_defaults()
  vim.g.omo_opts = { height = 0.5 }
  local opts = config.get()
  assert(opts.height == 0.5)
  assert(opts.keys.toggle == "<leader>o.")
end

function spec.keys_false_disables_all()
  vim.g.omo_opts = { keys = false }
  local opts = config.get()
  assert(opts.keys == false)
end

function spec.partial_keys_keep_defaults()
  vim.g.omo_opts = { keys = { line = false } }
  local opts = config.get()
  assert(opts.keys.line == false)
  assert(opts.keys.toggle == "<leader>o.")
  assert(opts.keys.range == "<leader>or")
  assert(opts.keys.side == "<leader>os")
end

function spec.get_returns_fresh_table()
  vim.g.omo_opts = nil
  local a = config.get()
  a.height = 99
  assert(config.get().height == 0.30)
end

function spec.health_reports_rendered_messages()
  local previous_health = vim.health
  local editor = require("omo.editor")
  local previous_status = editor.status
  local reports = {}
  local version = vim.version()
  vim.health = {
    start = function(message)
      reports[#reports + 1] = { "start", message }
    end,
    ok = function(message)
      reports[#reports + 1] = { "ok", message }
    end,
    warn = function(message)
      reports[#reports + 1] = { "warn", message }
    end,
    error = function(message)
      reports[#reports + 1] = { "error", message }
    end,
    info = function(message)
      reports[#reports + 1] = { "info", message }
    end,
  }
  rawset(editor, "status", function()
    return { disabled = false, connected = true, ready = true, port = 43210 }
  end)

  local ok, err = pcall(health.check)

  vim.health = previous_health
  rawset(editor, "status", previous_status)
  assert(ok, err)

  local version_message
  local editor_message
  for _, report in ipairs(reports) do
    if report[1] == "ok" and report[2]:find(tostring(version), 1, true) then
      version_message = report[2]
    elseif report[1] == "ok" and report[2]:find("43210", 1, true) then
      editor_message = report[2]
    end
  end
  assert(version_message and not version_message:find("%%s"))
  assert(editor_message and not editor_message:find("%%s") and editor_message:find("43210", 1, true))
end

function spec.number_valid_passththrough()
  assert(config.number("height", 0.5) == 0.5)
  assert(config.number("width", 40) == 40)
end

function spec.number_invalid_falls_back()
  assert(config.number("height", 0) == 0.30)
  assert(config.number("height", "half") == 0.30)
  assert(config.number("width", -5) == 0.40)
end

function spec.side_valid_passthrough()
  assert(config.side("bottom") == "bottom")
  assert(config.side("right") == "right")
end

function spec.side_invalid_falls_back()
  assert(config.side("left") == "right")
  assert(config.side(3) == "right")
end

return spec
