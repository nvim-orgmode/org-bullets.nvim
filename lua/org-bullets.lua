local M = {}

local fn = vim.fn
local api = vim.api

local NAMESPACE = api.nvim_create_namespace("org-bullets")
local org_headline_hl = "OrgHeadlineLevel"

local list_groups = {
  ["-"] = "OrgHeadlineLevel1",
  ["+"] = "OrgHeadlineLevel2",
  ["*"] = "OrgHeadlineLevel3",
}

---@class BulletsConfig
---@field public show_current_line boolean
---@field public symbols string[] | function(symbols: string[]): string[]
---@field public indent boolean
local defaults = {
  show_current_line = false,
  symbols = { "◉", "○", "✸", "✿" },
  indent = true,
}

local config = {}

---Merge a user config with the defaults
---@param user_config BulletsConfig
local function set_config(user_config)
  if user_config.symbols and type(user_config.symbols) == "function" then
    user_config.symbols = user_config.symbols(defaults.symbols) or defaults.symbols
  end
  config = vim.tbl_deep_extend("keep", user_config, defaults)
end

---Add padding to the given symbol
---@param symbol string
---@param padding_spaces number
---@param padding_in_front boolean
local function add_symbol_padding(symbol, padding_spaces, padding_in_front)
  if padding_in_front then
    return string.rep(" ", padding_spaces - 1) .. symbol
  else
    return symbol .. string.rep(" ", padding_spaces)
  end
end

---Sets of pairs {pattern = handler}
---handler
---@param str string
---@param conf BulletsConfig
---@return string symbol, string highlight_group
local markers = {
  stars = function(str, conf)
    local level = #str
    local symbol = add_symbol_padding(
      (conf.symbols[level] or conf.symbols[1]),
      (level <= 0 and 0 or level),
      conf.indent
    )
    local highlight = org_headline_hl .. level
    return { symbol, highlight }
  end,
  -- Checkboxes [x]
  checkboxes = function(_)
    return { "✓", "OrgDone" }
  end,
  -- List bullets *,+,-
  bullet = function(str)
    local symbol = add_symbol_padding("•", (#str - 1), true)
    return { symbol, list_groups[vim.trim(str)] }
  end,
}

---Set an extmark (safely)
---@param bufnr number
---@param virt_text string[] a tuple of character and highlight
---@param lnum integer
---@param start_col integer
---@param end_col integer
---@param highlight string?
local function set_mark(bufnr, virt_text, lnum, start_col, end_col, highlight)
  local ok, result = pcall(api.nvim_buf_set_extmark, bufnr, NAMESPACE, lnum, start_col, {
    end_col = end_col,
    hl_group = highlight,
    virt_text = { virt_text },
    virt_text_pos = "overlay",
    hl_mode = "combine",
    ephemeral = true,
  })
  if not ok then
    vim.schedule(function()
      vim.notify_once(result, "error", { title = "Org bullets" })
    end)
  end
end

--- Get the position objects for each time of item we are concealing
---@param bufnr number
---@param start_row number
---@param end_row number
---@param root table treesitter root node
---@return Position[]
local function get_ts_positions(bufnr, start_row, end_row, root)
  local positions = {}
  local query = vim.treesitter.parse_query(
    "org",
    [[
      (stars) @stars
      (bullet) @bullet
    ]]
  )
  for _, node, metadata in query:iter_captures(root, bufnr, start_row, end_row) do
    local type = node:type()
    local row1, col1, row2, col2 = node:range()
    positions[#positions + 1] = {
      type = type,
      item = vim.treesitter.get_node_text(node, bufnr),
      start_row = row1,
      start_col = col1,
      end_row = row2,
      end_col = col2,
      metadata = metadata,
    }
  end
  return positions
end

---@class Position
---@field start_row number
---@field start_col number
---@field end_row number
---@field end_col number
---@field item string

---Set a single line extmark
---@param bufnr number
---@param positions table<string, Position[]>
---@param conf BulletsConfig
local function set_position_marks(bufnr, positions, conf)
  for _, position in ipairs(positions) do
    local str = position.item
    local start_row = position.start_row
    local start_col = position.start_col
    local end_col = position.end_col
    local handler = markers[position.type]
    if start_col > -1 and end_col > -1 and handler then
      set_mark(bufnr, handler(str, conf), start_row, start_col, end_col)
    end
  end
end

local get_parser = (function()
  local parsers = {}
  return function(bufnr)
    if parsers[bufnr] then
      return parsers[bufnr]
    end
    parsers[bufnr] = vim.treesitter.get_parser(bufnr, "org", {})
    return parsers[bufnr]
  end
end)()

--- Get the position of the relevant org mode items to conceal
---@param bufnr number
---@param start_row number
---@param end_row number
---@return Position[]
local function get_mark_positions(bufnr, start_row, end_row)
  local parser = get_parser(bufnr)
  local positions = {}
  parser:for_each_tree(function(tstree, _)
    positions = get_ts_positions(bufnr, start_row, end_row, tstree:root())
  end)
  return positions
end

---Save the user config and initialise the plugin
---@param conf BulletsConfig
function M.setup(conf)
  conf = conf or {}
  set_config(conf)
  api.nvim_set_decoration_provider(NAMESPACE, {
    on_win = function(_, _, bufnr, topline, botline)
      if vim.bo[bufnr].filetype ~= "org" then
        return false
      end
      local positions = get_mark_positions(bufnr, topline, botline)
      set_position_marks(bufnr, positions, config)
    end,
    on_line = function(_, _, bufnr, row)
      local positions = get_mark_positions(bufnr, row, row + 1)
      set_position_marks(bufnr, positions, config)
    end,
  })
end

return M
