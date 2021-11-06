-- help to inspect results, e.g.:
-- ':lua _G.dump(vim.fn.getwininfo())'
-- use ':messages' to see the dump
function _G.dump(...)
  local objects = vim.tbl_map(vim.inspect, { ... })
  print(unpack(objects))
end

local M = {}

-- sets an invisible unicode character as icon seaprator
-- the below was reached after many iterations, a short summary of everything
-- that was tried and why it failed:
--
-- nbsp, U+00a0: the original separator, fails with files that contain nbsp
-- nbsp + zero-width space (U+200b): works only with `sk` (`fzf` shows <200b>)
-- word joiner (U+2060): display works fine, messes up fuzzy search highlights
-- line separator (U+2028), paragraph separator (U+2029): created extra space
-- EN space (U+2002): seems to work well
--
-- For more unicode SPACE options see:
-- http://unicode-search.net/unicode-namesearch.pl?term=SPACE&.submit=Search

-- DO NOT USE '\u{}' escape, it will fail with
-- "invalid escape sequence" if Lua < 5.3
-- '\x' escape sequence requires Lua 5.2
-- M.nbsp = "\xc2\xa0"    -- "\u{00a0}"
M.nbsp = "\xe2\x80\x82"   -- "\u{2002}"

-- Lua 5.1 compatibility, not sure if required since we're running LuaJIT
-- but it's harmless anyways since if the '\x' escape worked it will do nothing
-- https://stackoverflow.com/questions/29966782/how-to-embed-hex-values-in-a-lua-string-literal-i-e-x-equivalent
if _VERSION and type(_VERSION) == 'string' then
  local ver= tonumber(_VERSION:match("%d+.%d+"))
  if ver< 5.2 then
    M.nbsp = M.nbsp:gsub("\\x(%x%x)",
      function (x) return string.char(tonumber(x,16))
    end)
  end
end

M._if = function(bool, a, b)
    if bool then
        return a
    else
        return b
    end
end

M.strsplit = function(inputstr, sep)
  local t={}
  for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
    table.insert(t, str)
  end
  return t
end

function M.round(num, limit)
  if not num then return nil end
  if not limit then limit = 0.5 end
  local fraction = num - math.floor(num)
  if fraction > limit then return math.ceil(num) end
  return math.floor(num)
end

function M.nvim_has_option(option)
  return vim.fn.exists('&' .. option) == 1
end

function M._echo_multiline(msg)
  for _, s in ipairs(vim.fn.split(msg, "\n")) do
    vim.cmd("echom '" .. s:gsub("'", "''").."'")
  end
end

function M.info(msg)
  vim.cmd('echohl Directory')
  M._echo_multiline("[Fzf-lua] " .. msg)
  vim.cmd('echohl None')
end

function M.warn(msg)
  vim.cmd('echohl WarningMsg')
  M._echo_multiline("[Fzf-lua] " .. msg)
  vim.cmd('echohl None')
end

function M.err(msg)
  vim.cmd('echohl ErrorMsg')
  M._echo_multiline("[Fzf-lua] " .. msg)
  vim.cmd('echohl None')
end

function M.shell_error()
  return vim.v.shell_error ~= 0
end

function M.rg_escape(str)
  if not str then return str end
  --  [(~'"\/$?'`*&&||;[]<>)]
  --  escape "\~$?*|[()"
  return str:gsub('[\\~$?*|{\\[()-]', function(x)
    return '\\' .. x
  end)
end

function M.sk_escape(str)
  if not str then return str end
  return str:gsub('["`]', function(x)
    return '\\' .. x
  end)
end

function M.lua_escape(str)
  if not str then return str end
  return str:gsub('[%%]', function(x)
    return '%' .. x
  end)
end

-- TODO: why does `file --dereference --mime` return
-- wrong result for some lua files ('charset=binary')?
M.file_is_binary = function(filepath)
  filepath = vim.fn.expand(filepath)
  if vim.fn.executable("file") ~= 1 or
     not vim.loop.fs_stat(filepath) then
    return false
  end
  local out = M.io_system("file --dereference --mime " ..
    vim.fn.shellescape(filepath))
  return out:match("charset=binary") ~= nil
end

M.perl_file_is_binary = function(filepath)
  filepath = vim.fn.expand(filepath)
  if vim.fn.executable("perl") ~= 1 or
     not vim.loop.fs_stat(filepath) then
    return false
  end
  -- can also use '-T' to test for text files
  -- `perldoc -f -x` to learn more about '-B|-T'
  M.io_system("perl -E 'exit((-B $ARGV[0])?0:1);' " ..
    vim.fn.shellescape(filepath))
  return not M.shell_error()
end

M.read_file = function(filepath)
  local fd = vim.loop.fs_open(filepath, "r", 438)
  if fd == nil then return '' end
  local stat = assert(vim.loop.fs_fstat(fd))
  if stat.type ~= 'file' then return '' end
  local data = assert(vim.loop.fs_read(fd, stat.size, 0))
  assert(vim.loop.fs_close(fd))
  return data
end

M.read_file_async = function(filepath, callback)
  vim.loop.fs_open(filepath, "r", 438, function(err_open, fd)
    if err_open then
      M.warn("We tried to open this file but couldn't. We failed with following error message: " .. err_open)
      return
    end
    vim.loop.fs_fstat(fd, function(err_fstat, stat)
      assert(not err_fstat, err_fstat)
      if stat.type ~= 'file' then return callback('') end
      vim.loop.fs_read(fd, stat.size, 0, function(err_read, data)
        assert(not err_read, err_read)
        vim.loop.fs_close(fd, function(err_close)
          assert(not err_close, err_close)
          return callback(data)
        end)
      end)
    end)
  end)
end


function M.tbl_deep_clone(t)
  if not t then return end
  local clone = {}

  for k, v in pairs(t) do
    if type(v) == "table" then
      clone[k] = M.tbl_deep_clone(v)
    else
      clone[k] = v
    end
  end

  return clone
end

function M.tbl_length(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end

function M.tbl_isempty(T)
  if not T or not next(T) then return true end
  return false
end

function M.tbl_concat(...)
  local result = {}
  local n = 0

  for _, t in ipairs({...}) do
    for i, v in ipairs(t) do
      result[n + i] = v
    end
    n = n + #t
  end

  return result
end

function M.tbl_pack(...)
  return {n=select('#',...); ...}
end

function M.tbl_unpack(t, i, j)
  return unpack(t, i or 1, j or t.n or #t)
end

M.ansi_codes = {}
M.ansi_colors = {
    -- the "\x1b" esc sequence causes issues
    -- with older Lua versions
    -- clear    = "\x1b[0m",
    clear       = "[0m",
    bold        = "[1m",
    black       = "[0;30m",
    red         = "[0;31m",
    green       = "[0;32m",
    yellow      = "[0;33m",
    blue        = "[0;34m",
    magenta     = "[0;35m",
    cyan        = "[0;36m",
    grey        = "[0;90m",
    dark_grey   = "[0;97m",
    white       = "[0;98m",
}

M.add_ansi_code = function(name, escseq)
  M.ansi_codes[name] = function(string)
    if string == nil or #string == 0 then return '' end
    return escseq .. string .. M.ansi_colors.clear
  end
end

for color, escseq in pairs(M.ansi_colors) do
  M.add_ansi_code(color, escseq)
end


function M.strip_ansi_coloring(str)
  if not str then return str end
  -- remove escape sequences of the following formats:
  -- 1. ^[[34m
  -- 2. ^[[0;34m
  return str:gsub("%[[%d;]+m", "")
end

function M.get_visual_selection()
    -- this will exit visual mode
    -- use 'gv' to reselect the text
    local _, csrow, cscol, cerow, cecol
    local mode = vim.fn.mode()
    if mode == 'v' or mode == 'V' or mode == '' then
      -- if we are in visual mode use the live position
      _, csrow, cscol, _ = unpack(vim.fn.getpos("."))
      _, cerow, cecol, _ = unpack(vim.fn.getpos("v"))
      if mode == 'V' then
        -- visual line doesn't provide columns
        cscol, cecol = 0, 999
      end
      -- exit visual mode
      vim.api.nvim_feedkeys(
        vim.api.nvim_replace_termcodes("<Esc>",
          true, false, true), 'n', true)
    else
      -- otherwise, use the last known visual position
      _, csrow, cscol, _ = unpack(vim.fn.getpos("'<"))
      _, cerow, cecol, _ = unpack(vim.fn.getpos("'>"))
    end
    -- swap vars if needed
    if cerow < csrow then csrow, cerow = cerow, csrow end
    if cecol < cscol then cscol, cecol = cecol, cscol end
    local lines = vim.fn.getline(csrow, cerow)
    -- local n = cerow-csrow+1
    local n = M.tbl_length(lines)
    if n <= 0 then return '' end
    lines[n] = string.sub(lines[n], 1, cecol)
    lines[1] = string.sub(lines[1], cscol)
    return table.concat(lines, "\n")
end

function M.send_ctrl_c()
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes("<C-c>", true, false, true), 'n', true)
end

function M.feed_keys_termcodes(key)
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes(key, true, false, true), 'n', true)
end

function M.delayed_cb(cb, fn)
  -- HACK: slight delay to prevent missing results
  -- otherwise the input stream closes too fast
  -- sleep was causing all sorts of issues
  -- vim.cmd("sleep! 10m")
  if fn == nil then fn = function() end end
  vim.defer_fn(function()
    cb(nil, fn)
  end, 20)
end

function M.is_term_bufname(bufname)
  if bufname and bufname:match("term://") then return true end
  return false
end

function M.is_term_buffer(bufnr)
  local bufname = vim.api.nvim_buf_get_name(bufnr or 0)
  return M.is_term_bufname(bufname)
end

function M.buffer_is_dirty(bufnr, warn)
  bufnr = tonumber(bufnr) or vim.api.nvim_get_current_buf()
  local info = bufnr and vim.fn.getbufinfo(bufnr)[1]
  if info and info.changed ~= 0 then
    if warn then
      M.warn(('buffer %d has unsaved changes "%s"'):format(bufnr, info.name))
    end
    return true
  end
  return false
end

function M.winid_from_tab_buf(tabnr, bufnr)
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(tabnr)) do
    if bufnr == vim.api.nvim_win_get_buf(w) then
      return w
    end
  end
  return nil
end

function M.zz()
  -- skip for terminal buffers
  if M.is_term_buffer() then return end
  local lnum1 = vim.api.nvim_win_get_cursor(0)[1]
  local lcount = vim.api.nvim_buf_line_count(0)
  local zb = 'keepj norm! %dzb'
  if lnum1 == lcount then
    vim.fn.execute(zb:format(lnum1))
    return
  end
  vim.cmd('norm! zvzz')
  lnum1 = vim.api.nvim_win_get_cursor(0)[1]
  vim.cmd('norm! L')
  local lnum2 = vim.api.nvim_win_get_cursor(0)[1]
  if lnum2 + vim.fn.getwinvar(0, '&scrolloff') >= lcount then
    vim.fn.execute(zb:format(lnum2))
  end
  if lnum1 ~= lnum2 then
    vim.cmd('keepj norm! ``')
  end
end

function M.nvim_win_call(winid, func)
  vim.validate({
    winid = {
      winid, function(w)
        return w and vim.api.nvim_win_is_valid(w)
      end, 'a valid window'
    },
    func = {func, 'function'}
  })

  local cur_winid = vim.api.nvim_get_current_win()
  local noa_set_win = 'noa call nvim_set_current_win(%d)'
  if cur_winid ~= winid then
    vim.cmd(noa_set_win:format(winid))
  end
  local ret = func()
  if cur_winid ~= winid then
    vim.cmd(noa_set_win:format(cur_winid))
  end
  return ret
end

function M.ft_detect(ext)
  local ft = ''
  if not ext then return ft end
  local tmp_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(tmp_buf, 'bufhidden', 'wipe')
  pcall(vim.api.nvim_buf_call, tmp_buf, function()
    local filename = (vim.fn.tempname() .. '.' .. ext)
    vim.cmd("file " .. filename)
    vim.cmd("doautocmd BufEnter")
    vim.cmd("filetype detect")
    ft = vim.api.nvim_buf_get_option(tmp_buf, 'filetype')
  end)
  if vim.api.nvim_buf_is_valid(tmp_buf) then
    vim.api.nvim_buf_delete(tmp_buf, {force=true})
  end
  return ft
end

-- speed up exteral commands (issue #126)
local _use_lua_io = false
function M.set_lua_io(b)
  _use_lua_io = b
  if _use_lua_io then
    M.warn("using experimental feature 'lua_io'")
  end
end

function M.io_systemlist(cmd, use_lua_io)
  if not use_lua_io then use_lua_io = _use_lua_io end
  if use_lua_io then
    local rc = 0
    local stdout = ''
    local handle = io.popen(cmd .. " 2>&1; echo $?", "r")
    if handle then
      stdout = {}
      for h in handle:lines() do
        stdout[#stdout + 1] = h
      end
      -- last line contains the exit status
      rc = tonumber(stdout[#stdout])
      stdout[#stdout] = nil
    end
    handle:close()
    return stdout, rc
  else
    return vim.fn.systemlist(cmd), vim.v.shell_error
  end
end

function M.io_system(cmd, use_lua_io)
  if not use_lua_io then use_lua_io = _use_lua_io end
  if use_lua_io then
    local stdout, rc = M.io_systemlist(cmd, true)
    if type(stdout) == 'table' then
      stdout = table.concat(stdout, "\n")
    end
    return stdout, rc
  else
    return vim.fn.system(cmd), vim.v.shell_error
  end
end

local uv = vim.loop
function M.process_kill(pid, signal)
  if not pid or not tonumber(pid) then return false end
  if type(uv.os_getpriority(pid)) == 'number' then
    uv.kill(pid, signal or 9)
    return true
  end
  return false
end

function M.fzf_bind_to_neovim(key)
  local conv_map  = {
    ['alt'] = 'A',
    ['ctrl'] = 'C',
    ['shift'] = 'S',
  }
  key = key:lower()
  for k, v in pairs(conv_map) do
    key = key:gsub(k, v)
  end
  return ("<%s>"):format(key)
end

function M.git_version()
  local out = M.io_system("git --version")
  return tonumber(out:match("(%d+.%d+)."))
end

function M.find_version()
  local out, rc = M.io_systemlist("find --version")
  return rc==0 and tonumber(out[1]:match("(%d+.%d+)")) or nil
end

return M
