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

if vim.g.loaded_omo then
  return
end
vim.g.loaded_omo = true

local config = require("omo.config")
local terminal = require("omo.terminal")

local function register_keymaps()
  local keys = config.get().keys
  if keys == false then
    return
  end

  local toggle = keys.toggle
  if toggle then
    vim.keymap.set("n", toggle, function()
      terminal.toggle()
    end, { desc = "Toggle Omo", silent = true })
    vim.keymap.set("t", toggle, "<C-\\><C-N><Cmd>OmoToggle<CR>", { desc = "Toggle Omo", nowait = true, silent = true })
  end

  local range = keys.range
  if range then
    vim.keymap.set("x", range, function()
      terminal.send_selection()
    end, { desc = "Send selection to Omo", silent = true })
  end

  local line = keys.line
  if line then
    vim.keymap.set("n", line, function()
      terminal.send_line()
    end, { desc = "Send line to Omo", silent = true })
  end

  local side = keys.side
  if side then
    vim.keymap.set("n", side, function()
      terminal.toggle_side()
    end, { desc = "Toggle Omo side", silent = true })
    -- Call Lua directly instead of the <C-\><C-N><Cmd>...<CR> string form so toggle_side()
    -- can detect terminal mode before relocating the split.
    vim.keymap.set("t", side, function()
      terminal.toggle_side()
    end, { desc = "Toggle Omo side", nowait = true, silent = true })
  end
end

if vim.v.vim_did_enter == 1 then
  register_keymaps()
else
  vim.api.nvim_create_autocmd("VimEnter", {
    callback = register_keymaps,
    once = true,
  })
end

vim.api.nvim_create_user_command("OmoToggle", function()
  terminal.toggle()
end, { force = true })

vim.api.nvim_create_user_command("OmoToggleSide", function()
  terminal.toggle_side()
end, { force = true })

vim.api.nvim_create_user_command("OmoSend", function(args)
  if args.range == 0 then
    terminal.send_line()
  else
    terminal.send_context(args.line1, args.line2)
  end
end, { force = true, range = true })

local group = vim.api.nvim_create_augroup("omo_terminal", { clear = true })
vim.api.nvim_create_autocmd("TermOpen", {
  group = group,
  callback = function(args)
    if args.buf ~= terminal.current_buf() then
      return
    end
    vim.schedule(function()
      local win = terminal.current_win()
      if win then
        terminal.configure_window(win)
      end
    end)
    vim.keymap.set("n", "<LeftRelease>", "<LeftRelease>i", {
      buffer = args.buf,
      nowait = true,
      remap = false,
    })
  end,
})

vim.api.nvim_create_autocmd("VimResized", {
  group = group,
  callback = function()
    local win = terminal.current_win()
    if win and terminal.visible() then
      terminal.apply_size(win, terminal.current_side())
    end
  end,
})
