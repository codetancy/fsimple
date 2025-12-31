local M = { buffer = -1 }

local commands = {
  fsi_cmd = "dotnet fsi"
}

local create_buffer = function()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = 'fsi'
  return buf
end

local valid_buffer = function(buf_id)
  return buf_id > -1 and vim.api.nvim_buf_is_valid(buf_id)
end

local find_window = function(buf_id)
  for _, win_id in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win_id) == buf_id then
      return win_id
    end
  end

  return -1
end

local focus_window = function(buf_id)
  local win_id = find_window(buf_id)
  if win_id < 1 then
    win_id = vim.api.nvim_open_win(buf_id, false, { split = 'below' })
    vim.wo[win_id].relativenumber = false
  end
end

local run_cmd = function(buf_id)
  local exec = function(cmd)
    return vim.api.nvim_buf_call(buf_id, function()
      return vim.cmd.term(cmd)

      -- Alternatively...
      -- return vim.fn.jobstart(cmd, { term = true })
    end)
  end

  return exec
end

local fsi = function()
  local buf_id = M.buffer
  if not valid_buffer(buf_id) then
    buf_id = create_buffer()
    run_cmd(buf_id)(commands.fsi_cmd)
  end

  focus_window(buf_id)

  M.buffer = buf_id
end

local add_termination = function(cmd)
  return cmd .. "\n" .. ";;" .. "\n"
end

local send_lines = function(count, direction)
  local buf_id = M.buffer
  local chn = vim.bo[buf_id].channel

  local current_line = vim.api.nvim_win_get_cursor(0)[1]

  local start = 0
  local end_ = 0
  if direction == 'above' then
    start = current_line - 1
    end_ = current_line + count
  elseif direction == 'below' then
    start = current_line - count
    end_ = current_line - 1
  else
    start = current_line - 1
    end_ = current_line
  end

  local lines = vim.api.nvim_buf_get_lines(0, start, end_, false)
  local cmd = table.concat(lines, '\n')
  vim.api.nvim_chan_send(chn, add_termination(cmd))
end

local send_selection = function()
  local buf_id = M.buffer
  local chn = vim.bo[buf_id].channel

  -- Whenever we select in visual mode, the <> marks are saved
  -- See :marks for the last selection
  local open = vim.api.nvim_buf_get_mark(0, "<")
  local close = vim.api.nvim_buf_get_mark(0, ">")
  -- Alternatively, we could have yanked selection to a register

  local lines = vim.api.nvim_buf_get_lines(0, open[1] - 1, close[1], true)
  local cmd = table.concat(lines, '\n')
  vim.api.nvim_chan_send(chn, add_termination(cmd))
end

local send_buffer = function()
  local buf_id = M.buffer
  local chn = vim.bo[buf_id].channel
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, true)
  local cmd = table.concat(lines, '\n')
  vim.api.nvim_chan_send(chn, add_termination(cmd))
end

local send_motion = function()
  local buf_id = M.buffer
  local chn = vim.bo[buf_id].channel

  local open = vim.api.nvim_buf_get_mark(0, "[")
  local close = vim.api.nvim_buf_get_mark(0, "]")

  local lines = vim.api.nvim_buf_get_lines(0, open[1] - 1, close[1], false)
  local cmd = table.concat(lines, '\n')
  vim.api.nvim_chan_send(chn, add_termination(cmd))
end

local fsi_line = function(opts)
  fsi()
  vim.defer_fn(function() send_lines(opts.count, opts.args) end, 1000)
end

local fsi_select = function()
  fsi()
  vim.defer_fn(send_selection, 1000)
end

local fsi_buffer = function()
  fsi()
  vim.defer_fn(send_buffer, 1000)
end

local fsi_motion = function(_)
  fsi()
  vim.defer_fn(send_motion, 1000)
end
_G.fsi_motion = fsi_motion

vim.api.nvim_create_user_command("Fsi", fsi,
  { desc = 'Opens fsharp interactive' })
vim.api.nvim_create_user_command("FsiLine", fsi_line,
  { count = 0, nargs = 1, desc = 'Sends n lines to fsharp interactive' })
vim.api.nvim_create_user_command("FsiSelect", fsi_select,
  { desc = 'Sends visual mode selection to fsharp interactive' })
vim.api.nvim_create_user_command("FsiBuffer", fsi_buffer,
  { desc = 'Sends current buffer contents to fsharp interactive' })

vim.api.nvim_create_autocmd("FileType", {
  pattern = { "fsharp", "fs" },
  callback = function(ev)
    vim.keymap.set('n', '<leader>i', function()
      vim.o.operatorfunc = 'v:lua.fsi_motion'
      return 'g@'
    end, { expr = true, buffer = ev.buf })
  end
})
