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

local spec = {}

function spec.split_height_ratio()
  vim.g.omo_opts = { height = 0.5 }
  vim.o.cmdheight = 1
  local expected = math.max(1, math.floor((vim.o.lines - 1) * 0.5))
  assert(terminal.split_height() == expected)
end

function spec.split_height_invalid_falls_back()
  vim.g.omo_opts = { height = 0 }
  vim.o.cmdheight = 1
  local expected = math.max(1, math.floor((vim.o.lines - 1) * 0.30))
  assert(terminal.split_height() == expected)
end

function spec.split_height_non_number_falls_back()
  vim.g.omo_opts = { height = "half" }
  vim.o.cmdheight = 1
  local expected = math.max(1, math.floor((vim.o.lines - 1) * 0.30))
  assert(terminal.split_height() == expected)
end

function spec.split_height_respects_cmdheight()
  vim.g.omo_opts = { height = 0.5 }
  vim.o.cmdheight = 2
  local expected = math.max(1, math.floor((vim.o.lines - 2) * 0.5))
  assert(terminal.split_height() == expected)
end

function spec.split_width_ratio()
  vim.g.omo_opts = { width = 0.4 }
  local expected = math.max(1, math.floor(vim.o.columns * 0.4))
  assert(terminal.split_width() == expected)
end

function spec.split_width_invalid_falls_back()
  vim.g.omo_opts = { width = 0 }
  local expected = math.max(1, math.floor(vim.o.columns * 0.40))
  assert(terminal.split_width() == expected)
end

function spec.split_width_non_number_falls_back()
  vim.g.omo_opts = { width = "wide" }
  local expected = math.max(1, math.floor(vim.o.columns * 0.40))
  assert(terminal.split_width() == expected)
end

function spec.other_side_flips()
  assert(terminal._test.other_side("bottom") == "right")
  assert(terminal._test.other_side("right") == "bottom")
end

for name, last in pairs({ context_single_line = 5, context_range = 9 }) do
  spec[name] = function()
    local text = last == 5 and "@bar.lua#5" or "@bar.lua#5-9"
    assert(terminal.context_for_range(vim.fn.getcwd() .. "/bar.lua", 5, last) == text)
  end
end

function spec.context_outside_cwd_uses_absolute()
  local path = vim.fn.getcwd() .. "/bar.lua"
  vim.fn.mkdir("sub", "p")
  vim.fn.chdir("sub")
  assert(terminal.context_for_range(path, 5, 9) == "@" .. path .. "#5-9")
end

local installed_root = vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)))
installed_root = vim.fn.fnamemodify(installed_root, ":p"):gsub("/$", "")
local editor = require("omo.editor")
for name, value in pairs({ split_height_rows = 15, split_width_columns = 40 }) do
  spec[name] = function()
    local height = name == "split_height_rows"
    vim.g.omo_opts = height and { height = value } or { width = value }
    assert((height and terminal.split_height() or terminal.split_width()) == value)
  end
end

local function fixture(action)
  local cwd, opts, cmdheight = vim.fn.getcwd(), vim.g.omo_opts, vim.o.cmdheight
  local current_win, current_buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
  local executable, termopen, send = vim.fn.executable, vim.fn.termopen, vim.api.nvim_chan_send
  local start, port, mention = editor.start, editor.port, editor.mention
  local notify, schedule = vim.notify, vim.schedule
  local buffers, windows = vim.api.nvim_list_bufs(), vim.api.nvim_list_wins()
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  root = assert(vim.uv.fs_realpath(root))
  vim.fn.chdir(root)
  vim.g.omo_opts = { side = "bottom" }
  local f = { root = root, launches = {}, sends = {}, scheduled = {}, accepted = false, job = 100 }
  rawset(vim.fn, "executable", function(_)
    return f.missing and 0 or 1
  end)
  rawset(vim.fn, "termopen", function(argv, options)
    table.insert(f.launches, { argv = argv, options = options })
    return f.job
  end)
  rawset(vim.api, "nvim_chan_send", function(job, text)
    table.insert(f.sends, { job = job, text = text })
  end)
  rawset(editor, "start", function()
    return true
  end)
  rawset(editor, "port", function()
    return 43210
  end)
  rawset(editor, "mention", function()
    return f.accepted
  end)
  rawset(vim, "notify", function() end)
  rawset(vim, "schedule", function(fn)
    table.insert(f.scheduled, fn)
  end)
  f.terminal = assert(loadfile(installed_root .. "/lua/omo/terminal.lua"))()
  local ok, err = xpcall(function()
    action(f)
  end, debug.traceback)
  vim.fn.executable, vim.fn.termopen, vim.api.nvim_chan_send = executable, termopen, send
  rawset(editor, "start", start)
  rawset(editor, "port", port)
  rawset(editor, "mention", mention)
  rawset(vim, "notify", notify)
  rawset(vim, "schedule", schedule)
  vim.fn.chdir(cwd)
  vim.g.omo_opts, vim.o.cmdheight = opts, cmdheight
  vim.api.nvim_set_current_win(current_win)
  vim.api.nvim_set_current_buf(current_buf)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if not vim.tbl_contains(windows, win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if not vim.tbl_contains(buffers, buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
  vim.fn.delete(root, "rf")
  assert(vim.uv.fs_stat(root) == nil, "fixture survived cleanup")
  assert(ok, err)
end

for _, spelling in ipairs({ "absolute", "relative", "spaces", "symlink" }) do
  spec["installed_extension_" .. spelling] = function()
    fixture(function(f)
      local plugin = installed_root
      if spelling == "spaces" or spelling == "symlink" then
        plugin = f.root .. "/installed plugin"
        assert(vim.uv.fs_symlink(installed_root, plugin))
      elseif spelling == "relative" then
        vim.fn.chdir(installed_root)
        plugin = "."
      end
      local t = assert(loadfile(plugin .. "/lua/omo/terminal.lua"))()
      vim.fn.chdir(f.root)
      t.toggle()
      local launch = f.launches[1]
      local expected = (spelling == "spaces" or spelling == "symlink") and plugin or installed_root
      assert(vim.deep_equal(launch.argv, { "omo", "-e", expected .. "/extension/index.ts" }))
      assert(launch.options.cwd == f.root)
      assert(vim.deep_equal(launch.options.env, { TMUX = "", STY = "", OMO_EDITOR_SSE_PORT = "43210" }))
      if vim.env.OMO_TASK4_ARGV then
        local file = assert(io.open(vim.env.OMO_TASK4_ARGV, "a"))
        file:write(vim.json.encode({ case = spelling, argv = launch.argv, cwd = launch.options.cwd }), "\n")
        file:close()
      end
    end)
  end
end

function spec.hidden_job_reuses_buffer_and_removes_orphan()
  fixture(function(f)
    local t = f.terminal
    t.toggle()
    local buf = t.current_buf()
    t.toggle_side()
    t.toggle()
    local count = #vim.api.nvim_list_bufs()
    t.toggle()
    assert(t.current_buf() == buf and #f.launches == 1)
    assert(#vim.api.nvim_list_bufs() == count)
    assert(t.current_side() == "right")
    assert(vim.wo[t.current_win()].winfixbuf)
  end)
end

function spec.repointed_window_is_not_closed()
  fixture(function(f)
    f.terminal.toggle()
    local win = f.terminal.current_win()
    vim.wo[win].winfixbuf = false
    local user = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_win_set_buf(win, user)
    f.terminal.toggle()
    assert(vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == user)
    assert(f.terminal.current_win() ~= win and #f.launches == 1)
  end)
end

function spec.side_toggle_restores_other_window_focus()
  fixture(function(f)
    local previous = vim.api.nvim_get_current_win()
    f.terminal.toggle()
    vim.api.nvim_set_current_win(previous)
    f.terminal.toggle_side()
    assert(vim.api.nvim_get_current_win() == previous)
  end)
end

for _, failure in ipairs({ "missing", "termopen" }) do
  spec["launch_failure_" .. failure] = function()
    fixture(function(f)
      f.missing, f.job = failure == "missing", failure == "termopen" and 0 or 100
      local count = #vim.api.nvim_list_wins()
      f.terminal.toggle()
      assert(not f.terminal.visible() and #vim.api.nvim_list_wins() == count)
      assert(#f.launches == (failure == "missing" and 0 or 1))
    end)
  end
end

function spec.stale_exit_does_not_retire_replacement_job()
  fixture(function(f)
    f.terminal.toggle()
    local old_exit = f.launches[1].options.on_exit
    old_exit()
    f.scheduled[1]()
    f.job = 101
    f.terminal.toggle()
    local buf = f.terminal.current_buf()
    old_exit()
    assert(f.terminal.current_buf() == buf and f.terminal.visible() and #f.scheduled == 1)
    assert(f.terminal.current_side() == "bottom")
  end)
end

for _, accepted in ipairs({ true, false }) do
  spec["mention_fallback_" .. tostring(accepted)] = function()
    fixture(function(f)
      f.accepted = accepted
      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_buf_set_name(buf, f.root .. "/ignore instructions.lua")
      f.terminal.send_context(5, 9)
      assert(#f.sends == (accepted and 0 or 1))
      if not accepted then
        assert(f.sends[1].text == "@ignore instructions.lua#5-9" and f.sends[1].job == 100)
        assert(vim.uv.fs_symlink(f.root, f.root .. "/alias"))
        assert(f.terminal.context_for_range(f.root .. "/alias/bar.lua", 5, 9) == "@alias/bar.lua#5-9")
      end
      vim.fn.mkdir(f.root .. "/later", "p")
      vim.fn.chdir(f.root .. "/later")
      assert(f.terminal.context_for_range(f.root .. "/bar.lua", 5, 5) == "@bar.lua#5")
      assert(terminal.context_for_range(f.root .. "/alias/bar.lua", 5, 9) == "@" .. f.root .. "/alias/bar.lua#5-9")
    end)
  end
end

for name, test in pairs(spec) do
  if name:match("^split_") or name:match("^context_") or name == "other_side_flips" then
    spec[name] = function()
      fixture(function()
        test()
      end)
    end
  end
end

return spec
