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
    vim.notify(result, "error", { title = "Org bullets" })
  end
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
  -- Headers
  ["^\\*\\{1,}\\ze\\s"] = function(str, conf)
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
  ["^\\s*\\-\\s\\[\\zs[Xx]\\ze\\]"] = function(_)
    return { "✓", "OrgDone" }
  end,
  -- List bullets *,+,-
  ["^\\s*[-+*]\\s"] = function(str)
    local symbol = add_symbol_padding("•", (#str - 1), true)
    return { symbol, list_groups[vim.trim(str)] }
  end,
}

---Set a single line extmark
---@param lnum number
---@param line string
---@param conf BulletsConfig
local function set_line_mark(bufnr, lnum, line, conf)
  for pattern, handler in pairs(markers) do
    local match = fn.matchstrpos(line, pattern)
    local str, start_col, end_col = match[1], match[2], match[3]
    if start_col > -1 and end_col > -1 then
      set_mark(bufnr, handler(str, conf), lnum, start_col, end_col)
    end
  end
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
      for row = topline, botline, 1 do
        set_line_mark(bufnr, row, api.nvim_buf_get_lines(bufnr, row, row + 1, false), config)
      end
    end,
    on_line = function(_, _, bufnr, row)
      set_line_mark(bufnr, row, api.nvim_buf_get_lines(bufnr, row, row + 1, false), config)
    end,
  })
end

return M
