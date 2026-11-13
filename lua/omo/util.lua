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

local M = {}

---Notify the user with a "OMO" titled message.
---@param message string
---@param level integer|nil
function M.notify(message, level)
  vim.notify(message, level, { title = "OMO" })
end

return M
