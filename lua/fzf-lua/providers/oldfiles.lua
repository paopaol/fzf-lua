if not pcall(require, "fzf") then
  return
end

local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"

local M = {}

M.oldfiles = function(opts)
  opts = config.normalize_opts(opts, config.globals.oldfiles)
  if not opts then return end

  local current_buffer = vim.api.nvim_get_current_buf()
  local current_file = vim.api.nvim_buf_get_name(current_buffer)
  local results = {}

  if opts.include_current_session then
    for _, buffer in ipairs(vim.split(vim.fn.execute(':buffers! t'), "\n")) do
      local match = tonumber(string.match(buffer, '%s*(%d+)'))
      if match then
        local file = vim.api.nvim_buf_get_name(match)
        if vim.loop.fs_stat(file) and match ~= current_buffer then
          table.insert(results, file)
        end
      end
    end
  end

  for _, file in ipairs(vim.v.oldfiles) do
    -- if vim.loop.fs_stat(file) and not vim.tbl_contains(results, file) and file ~= current_file then
    if vim.loop.fs_stat(file) and file ~= current_file then
      table.insert(results, file)
    end
  end

  opts.fzf_fn = function (cb)
    for _, x in ipairs(results) do
      x = core.my_make_entry_file(opts, x)
      if x then
        cb(x, function(err)
          if err then return end
          -- close the pipe to fzf, this
          -- removes the loading indicator in fzf
          cb(nil, function() end)
        end)
      end
    end
    utils.delayed_cb(cb)
  end

  --[[ opts.cb_selected = function(_, x)
    print("o:", x)
  end ]]

  return core.my_fzf_files(opts)
end

return M
