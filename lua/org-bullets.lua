local M = {}

local api, treesitter = vim.api, vim.treesitter

local NAMESPACE = api.nvim_create_namespace("org-bullets")
local org_headline_hl = "@org.headline.level"

local list_groups = {
  ["-"] = "OrgBulletsDash",
  ["+"] = "OrgBulletsPlus",
  ["*"] = "OrgBulletsStar",
}

---@class OrgBulletsSymbols
---@field list? string | false
---@field headlines? string[] | function(symbols: string[]) | false
---@field checkboxes? table<'half' | 'done' | 'todo', string[]> | false

---@class BulletsConfig
---@field public symbols OrgBulletsSymbols
---@field public indent? boolean
local defaults = {
  symbols = {
    wrap = false,
    list = "•",
    headlines = { "◉", "○", "✸", "✿" },
    checkboxes = {
      half = { "", "@org.checkbox.halfchecked" },
      done = { "✓", "@org.keyword.done" },
      todo = { "˟", "@org.keyword.todo" },
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

--- @alias Markers table<fun(str: string, conf: BulletsConfig): string[][]>

---@type Markers
local markers = {
  -- FIXME relying on the TS node types as keys for each marker is brittle
  -- these should be changed to distinct constants
  stars = function(str, conf)
    local level = #str <= 0 and 0 or #str
    local symbols = conf.symbols.headlines
    if not symbols then
      return false
    end
    local symbol
    if not conf.symbols.wrap then
      symbol = add_symbol_padding((symbols[level] or symbols[1]), level, conf.indent)
    else
      local symbolIndex = ((level - 1) % #symbols) + 1
      symbol = add_symbol_padding(symbols[symbolIndex], level, conf.indent)
    end
    local highlight = org_headline_hl .. level
    return { { symbol, highlight } }
  end,
  -- Checkboxes [x]
  checkbox = function(str, conf)
    local symbols = conf.symbols.checkboxes
    if not symbols then
      return false
    end
    local text = symbols.todo
    if str:match("[Xx]") then
      text = symbols.done
    elseif str:match("-") then
      text = symbols.half
    end
    return { { "[", "NonText" }, text, { "]", "NonText" } }
  end,
  -- List bullets *,+,-
  bullet = function(str, conf)
    local symbols = conf.symbols.list
    if not symbols then
      return false
    end
    local symbol = add_symbol_padding(symbols, (#str - 1), true)
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
  if not virt_text then
    return
  end

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
      vim.notify_once(tostring(result), vim.log.levels.ERROR, { title = "Org bullets" })
    end)
  end
end

--- Create a position object
---@param bufnr number
---@param name string
---@param node TSNode
---@return Position
local function create_position(bufnr, name, node)
  local type = node:type()
  local row1, col1, row2, col2 = node:range()
  return {
    name = name,
    type = type,
    item = treesitter.get_node_text(node, bufnr),
    start_row = row1,
    start_col = col1,
    end_row = row2,
    end_col = col2,
  }
end

-- TODO: remove this when treesitter.query is stable
---@diagnostic disable-next-line: undefined-field
local parse = treesitter.query and treesitter.query.parse or treesitter.parse_query

--- Get the position objects for each time of item we are concealing
---@param bufnr number
---@param start_row number
---@param end_row number
---@param root table treesitter root node
---@return Position[]
local function get_ts_positions(bufnr, start_row, end_row, root)
  local positions = {}
  local query = parse(
    "org",
    [[
      (stars) @stars
      ((bullet) @bullet
        (#match? @bullet "[-\*\+]"))

      (checkbox "[ ]") @org_checkbox
      (checkbox status: (expr "str") @_org_checkbox_done_str (#any-of? @_org_checkbox_done_str "x" "X")) @org_checkbox_done
      (checkbox status: (expr "-")) @org_checkbox_half
    ]]
  )
  for _, match, _ in query:iter_matches(root, bufnr, start_row, end_row) do
    for id, node in pairs(match) do
      local name = query.captures[id]
      if not vim.startswith(name, "_") then
        positions[#positions + 1] = create_position(bufnr, name, node)
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

--- Get the position of the relevant org mode items to conceal
---@param bufnr number
---@param start_row number
---@param end_row number
---@return Position[]
local function get_mark_positions(bufnr, start_row, end_row)
  local parser = treesitter.get_parser(bufnr, "org", {})
  if not parser then
    return {}
  end
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

local function set_highlights()
  api.nvim_set_hl(0, "OrgBulletsDash", { link = "@org.headline.level1" })
  api.nvim_set_hl(0, "OrgBulletsPlus", { link = "@org.headline.level2" })
  api.nvim_set_hl(0, "OrgBulletsStar", { link = "@org.headline.level3" })
end

local ticks = {}
---Save the user config and initialise the plugin
---@param conf? BulletsConfig
function M.setup(conf)
  conf = conf or {}
  set_highlights()
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
