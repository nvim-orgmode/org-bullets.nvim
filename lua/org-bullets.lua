local M = {}

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
  symbols = {
    headlines = { "◉", "○", "✸", "✿" },
    checkboxes = {
      half = { "", "OrgTSCheckboxHalfChecked" },
      done = { "✓", "OrgDone" },
      todo = { "˟", "OrgTODO" },
    },
  },
  indent = true,
  -- TODO: should this read from the user's conceal settings?
  -- maybe but that option is a little complex and will make
  -- the implementation more convoluted
  concealcursor = false,
}

local config = {}

---Merge a user config with the defaults
---@param user_config BulletsConfig
local function set_config(user_config)
  local headlines = vim.tbl_get(user_config, "symbols", "headlines")
  local default_headlines = defaults.symbols.headlines
  if headlines and type(headlines) == "function" then
    user_config.symbols.headlines = user_config.symbols(default_headlines) or default_headlines
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
  -- FIXME relying on the TS node types as keys for each marker is brittle
  -- these should be changed to distinct constants
  stars = function(str, conf)
    local level = #str <= 0 and 0 or #str
    local symbols = conf.symbols.headlines
    local symbol = add_symbol_padding((symbols[level] or symbols[1]), level, conf.indent)
    local highlight = org_headline_hl .. level
    return { { symbol, highlight } }
  end,
  -- Checkboxes [x]
  expr = function(str, conf)
    local symbols = conf.symbols.checkboxes
    local text = symbols.todo
    if str:match("[Xx]") then
      text = symbols.done
    elseif str:match("-") then
      text = symbols.half
    end
    return { { "[", "NonText" }, text, { "]", "NonText" } }
  end,
  -- List bullets *,+,-
  bullet = function(str)
    local symbol = add_symbol_padding("•", (#str - 1), true)
    return { { symbol, list_groups[vim.trim(str)] } }
  end,
}

---Set an extmark (safely)
---@param bufnr number
---@param virt_text string[][] a tuple of character and highlight
---@param lnum integer
---@param start_col integer
---@param end_col integer
---@param highlight string?
local function set_mark(bufnr, virt_text, lnum, start_col, end_col, highlight)
  local ok, result = pcall(api.nvim_buf_set_extmark, bufnr, NAMESPACE, lnum, start_col, {
    end_col = end_col,
    hl_group = highlight,
    virt_text = virt_text,
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

--- Create a position object
---@param bufnr number
---@param name string
---@param node userdata
---@return Position
local function create_position(bufnr, name, node)
  local type = node:type()
  local row1, col1, row2, col2 = node:range()
  return {
    name = name,
    type = type,
    item = vim.treesitter.get_node_text(node, bufnr),
    start_row = row1,
    start_col = col1,
    end_row = row2,
    end_col = col2,
  }
end

--- A workaround for matching an empty checkbox since it is not returned as a single node
---@param bufnr number
---@param name string
---@param match table
---@param query table
---@param position Position
---@param positions Position[]
local function add_empty_checkbox(bufnr, name, match, query, position, positions)
  if name:match("left") then
    return
  end
  local next_id, next_match = next(match)
  local next_name = query.captures[next_id]
  local next_position = create_position(bufnr, next_name, next_match)
  local right, left = position, next_position
  positions[#positions + 1] = {
    name = "org_checkbox_empty",
    type = "expr",
    item = left.item .. " " .. right.item,
    start_row = left.start_row,
    start_col = left.start_col,
    end_row = right.end_row,
    end_col = right.end_col,
  }
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
      ((bullet) @bullet
        (#match? @bullet "[-\*\+]"))

      (listitem . (bullet) . (paragraph .
        (expr "[" "str" @_org_checkbox_check "]") @org_checkbox_done
        (#match? @org_checkbox_done "^\\[[xX]\\]$")))

      (listitem . (bullet) . (paragraph .
        ((expr "[" "-" @_org_check_in_progress "]") @org_checkbox_cancelled
        (#eq? @org_checkbox_cancelled "[-]"))))

      (listitem . (bullet) . (paragraph .
        (expr "[") @org_checkbox.left (#eq? @org_checkbox.left "[") .
        (expr "]") @org_checkbox.right (#eq? @org_checkbox.right "]"))
        @_org_checkbox_empty (#match? @_org_checkbox_empty "^\\[ \\]"))
    ]]
  )
  for _, match, _ in query:iter_matches(root, bufnr, start_row, end_row) do
    for id, node in pairs(match) do
      local name = query.captures[id]
      if not vim.startswith(name, "_") then
        local position = create_position(bufnr, name, node)
        -- FIXME: this logic is a workaround for the lack of a proper node
        -- for an empty check box it should be removed once one is added.
        if name:match("org_checkbox%..+") then
          add_empty_checkbox(bufnr, name, match, query, position, positions)
        else
          positions[#positions + 1] = position
        end
      end
    end
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

    -- Don't add conceal on the current cursor line if the user doesn't want it
    local is_concealed = true
    if not conf.concealcursor then
      local cursor_row = api.nvim_win_get_cursor(0)[1]
      is_concealed = start_row ~= (cursor_row - 1)
    end
    if is_concealed and start_col > -1 and end_col > -1 and handler then
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
    local root = tstree:root()
    local root_start_row, _, root_end_row, _ = root:range()
    if root_start_row > start_row or root_end_row < start_row then
      return
    end
    positions = get_ts_positions(bufnr, start_row, end_row, root)
  end)
  return positions
end

local ticks = {}
---Save the user config and initialise the plugin
---@param conf BulletsConfig
function M.setup(conf)
  conf = conf or {}
  set_config(conf)
  api.nvim_set_decoration_provider(NAMESPACE, {
    on_start = function(_, tick)
      local buf = api.nvim_get_current_buf()
      if ticks[buf] == tick then
        return false
      end
      ticks[buf] = tick
      return true
    end,
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
