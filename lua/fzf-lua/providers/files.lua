if not pcall(require, "fzf") then
  return
end

local fzf_helpers = require("fzf.helpers")
local core = require "fzf-lua.core"
local utils = require "fzf-lua.utils"
local config = require "fzf-lua.config"

local M = {}

local get_files_cmd = function(opts)
  if opts.raw_cmd and #opts.raw_cmd>0 then
    return opts.raw_cmd
  end
  if opts.cmd and #opts.cmd>0 then
    return opts.cmd
  end
  local command = nil
  if vim.fn.executable("fd") == 1 then
    command = string.format('fd %s', opts.fd_opts)
  else
    command = string.format('find -L . %s', opts.find_opts)
  end
  return command
end

M.files = function(opts)

  opts = config.normalize_opts(opts, config.globals.files)
  if not opts then return end

  local command = get_files_cmd(opts)

  opts.fzf_fn = fzf_helpers.cmd_line_transformer(
    {cmd = command, cwd = opts.cwd},
    function(x)
      return core.make_entry_file(opts, x)
    end)

  return core.fzf_files(opts)
end

local last_query = ""

M.files_resume = function(opts)

  opts = config.normalize_opts(opts, config.globals.files)
  if not opts then return end
  if opts._is_skim then
    utils.info("'files_resume' is not supported with 'sk'")
    return
  end

  local raw_act = require("fzf.actions").raw_action(function(args)
    last_query = args[1]
  end, "{q}")

  local command = get_files_cmd(opts)

  opts.fzf_opts['--query'] = vim.fn.shellescape(last_query)
  opts._fzf_cli_args = ('--bind=change:execute-silent:%s'):
    format(vim.fn.shellescape(raw_act))

  opts.fzf_fn = fzf_helpers.cmd_line_transformer(
    {cmd = command, cwd = opts.cwd},
    function(x)
      return core.make_entry_file(opts, x)
    end)

  return core.fzf_files(opts)
end


M.my_files = function(opts)

  opts = config.normalize_opts(opts, config.globals.files)
  if not opts then return end

  local command = get_files_cmd(opts)

  opts.fzf_fn = fzf_helpers.cmd_line_transformer(
    {cmd = command, cwd = opts.cwd},
    function(x)
      return core.my_make_entry_file(opts, x)
    end)

  return core.my_fzf_files(opts)
end

return M
