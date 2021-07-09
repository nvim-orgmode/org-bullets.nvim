local M = {}

---@class BulletsConfig
---@field public show_current_line boolean
local config = {
  show_current_line = false,
}

local fn = vim.fn
local api = vim.api

local org_ns = api.nvim_create_namespace("org_bullets")
local org_headline_hl = "OrgHeadlineLevel"

local symbols = {
  "◉",
  "○",
  "✸",
  "✿",
}

---@type table<integer,integer>
local marks = {}

---@type table
local last_lnum = { mark = nil, lnum = nil }

---Check if the current line is the same as the last
---@param lnum integer
---@return table
local line_changed = function(lnum)
  return last_lnum and last_lnum.lnum ~= lnum
end

local function set_mark(virt_text, lnum, start_col, end_col, highlight)
  local ok, result = pcall(api.nvim_buf_set_extmark, 0, org_ns, lnum, start_col, {
    end_col = end_col,
    hl_group = highlight,
    virt_text = { virt_text },
    virt_text_pos = "overlay",
    hl_mode = "combine",
  })
  if not ok then
    api.nvim_echo({ { result, "ErrorMsg" } }, true, {})
  else
    marks[lnum] = result
  end
end

---Set the a single line extmark
---@param lnum number
---@param line number
local function set_line_mark(lnum, line)
  local match = fn.matchstrpos(line, [[^\*\{1,}\ze\s]])
  local str, start_col, end_col = match[1], match[2], match[3]
  if start_col > -1 and end_col > -1 then
    local level = #str
    local padding = level <= 0 and "" or string.rep(" ", level - 1)
    local symbol = padding .. (symbols[level] or symbols[1]) .. " "
    local highlight = org_headline_hl .. level
    set_mark({ symbol, highlight }, lnum, start_col, end_col, highlight)
  end
end

---Apply the the bullet markers to the whole buffer
---used on reloading the buffer or on first entering
local function conceal_buffer()
  marks = {}
  api.nvim_buf_clear_namespace(0, org_ns, 0, -1)
  local lines = api.nvim_buf_get_lines(0, 0, -1, false)
  for index, line in ipairs(lines) do
    set_line_mark(index - 1, line)
  end
end

---Update only a range of changed lines based on a buffer update
---@see: :help api-buffer-updates-lua
---@param _ 'lines' 'the event type'
---@param buf integer 'the buffer number'
---@param __ integer 'the changed tick'
---@param firstline number 'the first line in the changed range'
---@param ___ number 'the last line'
---@param new_lastline number 'the updated last line'
local function update_changed_lines(_, buf, __, firstline, ___, new_lastline)
  local lines = vim.api.nvim_buf_get_lines(buf, firstline, new_lastline, true)
  local index = 1
  for lnum = firstline, new_lastline - 1 do
    local id = marks[lnum]
    if id then
      api.nvim_buf_del_extmark(0, org_ns, id)
    end
    set_line_mark(lnum, lines[index])
    index = index + 1
  end
end

---Re-add the lnum that was revealed on the last cursor move
---@param lnum number
local function apply_previous_extmark(lnum)
  local mark = last_lnum.mark and last_lnum.mark[3] or nil
  if not mark then
    return
  end
  local start_col = last_lnum.mark[2]
  local end_col = mark.end_col
  set_mark(mark.virt_text[1], last_lnum.lnum, start_col, end_col, mark.hl_group)
end

--- Initialise autocommands for the plugin
--- @param conf BulletsConfig
local function setup_autocommands(conf)
  local commands = {}
  if conf and conf.show_current_line then
    table.insert(commands, {
      events = { "CursorMoved" },
      targets = { "<buffer>" },
      command = function()
        local pos = api.nvim_win_get_cursor(0)
        local lnum = pos[1] - 1
        local changed = line_changed(lnum)
        if changed then
          apply_previous_extmark(lnum)
        end
        -- order matters here, this should happen AFTER re-adding previous marks
        -- also update the line number no matter what
        local id = marks[lnum]
        if not id then
          return
        end
        local mark = api.nvim_buf_get_extmark_by_id(0, org_ns, id, { details = true })
        api.nvim_buf_del_extmark(0, org_ns, id)
        marks[lnum] = nil
        if changed then
          last_lnum = {
            lnum = lnum,
            mark = mark,
          }
        end
      end,
    })
  end
  require("org-bullets.utils").augroup("OrgBullets", commands)
end

function M.bullets()
  conceal_buffer()
  --- TODO: on_lines is not triggered for undo events??
  api.nvim_buf_attach(0, true, { on_lines = update_changed_lines, on_reload = conceal_buffer })
  setup_autocommands(config)
end

---Save the user config and initialise the plugin
---@param user_config BulletsConfig
function M.setup(user_config)
  config = user_config
  require("org-bullets.utils").augroup("OrgBulletsInit", {
    {
      events = { "Filetype" },
      targets = { "org" },
      command = M.bullets,
    },
  })
end

return M
