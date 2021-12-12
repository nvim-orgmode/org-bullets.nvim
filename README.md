# Org-bullets.nvim

This plugin is a clone of [org-bullets](https://github.com/sabof/org-bullets).
It replaces the asterisks in org syntax with unicode characters.

This plugin is an extension intended for use with [orgmode.nvim](https://github.com/kristijanhusak/orgmode.nvim)

**status**: experimental

This plugin works by using neovim `extmarks`, rather than `conceal` for a few reasons.

- conceal can only have one global highlight see `:help hl-Conceal`.
- conceal doesn't work when a block is folded.

_see below for a simpler conceal-based solution_

![folded](https://user-images.githubusercontent.com/22454918/125088455-525df300-e0c5-11eb-9b36-47c238b46971.png)

## Pre-requisites

- neovim 0.5+

## Installation

```lua
use {"akinsho/org-bullets.nvim", config = function()
  require("org-bullets").setup {
    -- Symbols for different headline bullet levels
    symbols = { "◉", "○", "✸", "✿" }
    -- Can also be overridden with a function to append to the above defaults
    symbols = function(default_list)
      table.insert(default_list, "♥")
      return default_list
    end,
    -- Show the literal text of the current line, similar to 'concealcursor'
    show_current_line = false,
    -- Whether or not to indent bullets
    indent = true,
    -- Characters that will match for bullets, can also be a function similar to 'symbols'
    -- but is passed a string instead of a table
    bullet_chars = "-+*",
    -- The symbol for the above bullets
    bullet_symbol = "•",
  }
end}

```

### Conceal-based alternative

A simpler conceal based alternative is:

```vim
syntax match OrgHeadlineStar1 /^\*\ze\s/me=e-1 conceal cchar=◉ containedin=OrgHeadlineLevel1 contained
syntax match OrgHeadlineStar2 /^\*\{2}\ze\s/me=e-1 conceal cchar=○ containedin=OrgHeadlineLevel2 contained
syntax match OrgHeadlineStar3 /^\*\{3}\ze\s/me=e-1 conceal cchar=✸ containedin=OrgHeadlineLevel3 contained
syntax match OrgHeadlineStar4 /^\*{4}\ze\s/me=e-1 conceal cchar=✿ containedin=OrgHeadlineLevel4 contained
```

## TODO:

- [ ] Add some degree of concealcursor-like behaviour
