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

local root = vim.fn.getcwd()
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
vim.opt.runtimepath:append(root)

local specs = { "tests.config_spec", "tests.terminal_spec", "tests.editor_spec" }
local total_passed, total_failed = 0, 0

for _, name in ipairs(specs) do
  local spec = require(name)
  for test_name, fn in pairs(spec) do
    local ok, err = pcall(fn)
    if ok then
      total_passed = total_passed + 1
      print("PASS " .. name .. "." .. test_name)
    else
      total_failed = total_failed + 1
      print("FAIL " .. name .. "." .. test_name .. ": " .. tostring(err))
    end
  end
end

print(string.format("%d passed, %d failed", total_passed, total_failed))
if total_failed > 0 then
  os.exit(1)
end
