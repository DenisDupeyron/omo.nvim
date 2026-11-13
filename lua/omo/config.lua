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

local notify = require("omo.util").notify

---@class omo.Opts.Keys
---@field toggle? string|false Keymap to toggle the Omo terminal.
---@field range? string|false Visual-mode keymap to send the selection to Omo.
---@field line? string|false Normal-mode keymap to send the current line to Omo.
---@field side? string|false Keymap to toggle the split between bottom and right.

---@class omo.Opts
---@field height? number Split height: a ratio (0 < h <= 1) of the window, or a row count (h > 1).
---@field width? number Split width: a ratio (0 < w <= 1) of the window, or a column count (w > 1).
---@field side? "bottom"|"right" Side for a new split.
---@field keys? omo.Opts.Keys|false Keymaps to register. Set to false to register none.

local defaults = {
  height = 0.30,
  width = 0.40,
  side = "right",
  keys = {
    toggle = "<leader>o.",
    range = "<leader>or",
    line = "<leader>ol",
    side = "<leader>os",
  },
}

local M = {}

---Resolve the effective options by merging vim.g.omo_opts over the defaults.
---@return omo.Opts
function M.get()
  return vim.tbl_deep_extend("force", {}, defaults, vim.g.omo_opts or {})
end

---Validate a sizing option (height or width). Returns the value when it is a positive number,
---otherwise warns and returns the configured default for that option.
---@param name "height"|"width"
---@param value unknown
---@return number
function M.number(name, value)
  local default = defaults[name] --[[@as number]]
  if type(value) ~= "number" or value <= 0 then
    notify(string.format("Invalid %s %s, falling back to %s.", name, vim.inspect(value), default), vim.log.levels.WARN)
    return default
  end
  return value
end

---Validate the split side. Returns the value when it is "bottom" or "right", otherwise warns and
---returns "right".
---@param value unknown
---@return "bottom"|"right"
function M.side(value)
  if value == "bottom" or value == "right" then
    return value
  end
  local default = defaults.side --[[@as "bottom"|"right"]]
  notify(string.format("Invalid side %s, falling back to %q.", vim.inspect(value), default), vim.log.levels.WARN)
  return default
end

return M
