-- Copyright (C) 2026 Denis Dupeyron
-- SPDX-License-Identifier: GPL-3.0-only
-- Run with nvim --headless -u NONE -i NONE -c 'luafile tests/terminal_mode_spec.lua'

local plugin = vim.env.OMO_TEST_PLUGIN_ROOT or vim.fn.getcwd()
vim.opt.runtimepath:prepend(plugin)
local terminal = require("omo.terminal")
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
vim.fn.writefile({ "#!/bin/sh", "exec cat" }, root .. "/omo")
assert(vim.fn.setfperm(root .. "/omo", "rwx------") == 1)
vim.env.PATH = root .. ":" .. vim.env.PATH
vim.fn.chdir(root)
vim.g.omo_opts = { side = "bottom" }
local source_win = vim.api.nvim_get_current_win()
vim.api.nvim_buf_set_name(0, root .. "/context.lua")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three", "four" })

local group = vim.api.nvim_create_augroup("OmoTerminalModeRegression", { clear = true })
local timer = assert(vim.uv.new_timer())
local scenario = "current line"
local finished = false

local function finish(failure)
  if finished then
    return
  end
  finished = true
  timer:stop()
  vim.api.nvim_clear_autocmds({ group = group })
  local function exit()
    timer:stop()
    timer:close()
    vim.fn.chdir(plugin)
    vim.fn.delete(root, "rf")
    if failure then
      io.stderr:write("FAIL send_context enters terminal input (" .. scenario .. "): " .. failure .. "\n")
      vim.cmd("cquit 1")
    else
      io.stdout:write("2 passed, 0 failed\n")
      io.stdout:flush()
      vim.cmd("qa!")
    end
  end
  local buf = terminal.current_buf()
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_create_autocmd("TermClose", {
      group = group,
      buffer = buf,
      once = true,
      callback = function()
        vim.schedule(exit)
      end,
    })
    timer:start(
      2000,
      0,
      vim.schedule_wrap(function()
        failure = (failure and failure .. "; " or "") .. "terminal cleanup timed out"
        exit()
      end)
    )
    vim.fn.jobstop(vim.b[buf].terminal_job_id)
  else
    exit()
  end
end

local cases = {
  {
    name = "current line",
    send = function()
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      terminal.send_line()
    end,
  },
  {
    name = "visual selection",
    send = function()
      vim.api.nvim_win_set_cursor(0, { 3, 0 })
      vim.api.nvim_create_autocmd("ModeChanged", {
        group = group,
        pattern = "*:V",
        once = true,
        callback = function()
          vim.schedule(function()
            local ok, err = pcall(function()
              assert(vim.fn.mode() == "V", "fixture must enter linewise visual mode")
              vim.api.nvim_win_set_cursor(0, { 4, 0 })
              terminal.send_selection()
            end)
            if not ok then
              finish(tostring(err))
            end
          end)
        end,
      })
      vim.api.nvim_feedkeys("V", "nt", false)
    end,
  },
}

local function run(index)
  local case = cases[index]
  if not case then
    finish()
    return
  end
  scenario = case.name
  vim.cmd("stopinsert")
  vim.api.nvim_set_current_win(source_win)
  vim.api.nvim_create_autocmd("ModeChanged", {
    group = group,
    pattern = "*:t",
    once = true,
    callback = function()
      timer:stop()
      local ok, err = pcall(function()
        assert(vim.fn.mode() == "t", "ModeChanged must report actual terminal input mode")
        assert(vim.bo.buftype == "terminal", "focused buffer must be a real terminal")
        assert(vim.api.nvim_get_current_win() == terminal.current_win(), "terminal must receive focus")
      end)
      if not ok then
        finish(tostring(err))
        return
      end
      io.stdout:write("PASS send_context enters terminal input (" .. scenario .. "): mode=t\n")
      io.stdout:flush()
      vim.schedule(function()
        run(index + 1)
      end)
    end,
  })
  timer:start(
    2000,
    0,
    vim.schedule_wrap(function()
      finish("expected mode=t, actual mode=" .. vim.fn.mode())
    end)
  )
  local ok, err = pcall(case.send)
  if not ok then
    finish(tostring(err))
  end
end

vim.schedule(function()
  run(1)
end)
