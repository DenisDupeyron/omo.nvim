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

local editor = require("omo.editor")

local M = {}

function M.check()
  local ok = vim.health.start or vim.health.report_start
  local report_ok = vim.health.ok or vim.health.report_ok
  local report_warn = vim.health.warn or vim.health.report_warn
  local report_error = vim.health.error or vim.health.report_error
  local report_info = vim.health.info or vim.health.report_info

  ok("omo.nvim")

  if vim.version().major == 0 and vim.version().minor < 11 then
    report_error(string.format("Neovim 0.11+ required (uses vim.fs.relpath), found %s", vim.version()))
  else
    report_ok(string.format("Neovim %s", vim.version()))
  end

  if vim.fn.executable("omo") == 1 then
    report_ok("omo executable found on PATH")
  else
    report_error("omo executable not found on PATH")
  end

  if vim.fn.executable("openssl") == 1 then
    report_ok("openssl found on PATH")
  else
    report_warn(
      "openssl not found on PATH: the editor integration is disabled and file mentions fall back to typed @path#5-9 text"
    )
  end

  if vim.fn.exists("+winfixbuf") == 1 then
    report_info("+winfixbuf available: the Omo window refuses buffer swaps")
  else
    report_info("+winfixbuf unavailable: the Omo window can be repointed by :buffer/:edit")
  end

  local status = editor.status()
  if status.disabled then
    report_warn("Editor integration disabled (WebSocket server failed to start)")
  elseif status.connected then
    report_ok(
      string.format("Editor integration connected on port %s%s", status.port, status.ready and " and ready" or "")
    )
  elseif status.port then
    report_info(string.format("Editor integration listening on port %s, no Omo connected", status.port))
  else
    report_info("Editor integration not started (starts with the first Omo terminal)")
  end
end

return M
