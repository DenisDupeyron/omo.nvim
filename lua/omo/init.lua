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

local terminal = require("omo.terminal")

local M = {}

---Toggle the Omo terminal split.
function M.toggle()
  terminal.toggle()
end

---Toggle the split between the bottom and the right.
function M.toggle_side()
  terminal.toggle_side()
end

---Send the current line to Omo.
function M.send_line()
  terminal.send_line()
end

---Send the current visual selection to Omo.
function M.send_selection()
  terminal.send_selection()
end

return M
