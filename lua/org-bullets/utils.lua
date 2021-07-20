local M = {}
local fmt = string.format

_G.__bullets = __bullets or {}

local function _create(f)
  table.insert(__bullets, f)
  return #__bullets
end

function M._execute(id, args)
  __bullets[id](args)
end

---@class Autocmd
---@field events string[] list of autocommand events
---@field targets string[] list of autocommand patterns
---@field modifiers string[] e.g. nested, once
---@field command string | function

---Create an autocommand
---@param name string
---@param commands Autocmd[]
function M.augroup(name, commands)
  vim.cmd("augroup " .. name)
  vim.cmd("autocmd!")
  for _, c in ipairs(commands) do
    local command = c.command
    if type(command) == "function" then
      local fn_id = _create(command)
      command = fmt("lua require('org-bullets.utils')._execute(%s)", fn_id)
    end
    vim.cmd(
      string.format(
        "autocmd %s %s %s %s",
        table.concat(c.events, ","),
        table.concat(c.targets or {}, ","),
        table.concat(c.modifiers or {}, " "),
        command
      )
    )
  end
  vim.cmd("augroup END")
end

function M.throttle(ms, fn)
  local timer = vim.loop.new_timer()
  local running = false
  return function(...)
    if not running then
      local argv = { ... }
      local argc = select("#", ...)

      timer:start(ms, 0, function()
        running = false
        pcall(vim.schedule_wrap(fn), unpack(argv, 1, argc))
      end)
      running = true
    end
  end
end

return M
