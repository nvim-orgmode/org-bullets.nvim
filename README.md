# Org-bullets.nvim

This plugin is a clone of [org-bullets](https://github.com/sabof/org-bullets).
It replaces the asterisks in org syntax with unicode characters.

This plugin is an extension intended for use with [orgmode.nvim](https://github.com/kristijanhusak/orgmode.nvim)

This plugin works by using neovim `extmarks`, rather than `conceal` for a few reasons.

- conceal can only have one global highlight see `:help hl-Conceal`.
- conceal doesn't work when a block is folded.

_see below for a simpler conceal-based solution_

![folded](https://user-images.githubusercontent.com/22454918/125088455-525df300-e0c5-11eb-9b36-47c238b46971.png)

## Pre-requisites

- **This plugin requires the use of treesitter with `tree-sitter-org` installed**
- neovim 0.7+

## Installation

#### With packer.nvim

```lua
use 'akinsho/org-bullets.nvim'
```

## Usage

To use the defaults use:

```lua
use {'akinsho/org-bullets.nvim', config = function()
  require('org-bullets').setup()
end}
```

The full options available are:

**NOTE**: Do **NOT** copy and paste this block as it is not valid, it is just intended to show the available configuration options

```lua
use {"akinsho/org-bullets.nvim", config = function()
  require("org-bullets").setup {
    concealcursor = false, -- If false then when the cursor is on a line underlying characters are visible
    symbols = {
      -- headlines can be a list
      headlines = { "◉", "○", "✸", "✿" },
      -- or a function that receives the defaults and returns a list
      headlines = function(default_list)
        table.insert(default_list, "♥")
        return default_list
      end,
      checkboxes = {
        cancelled = { "", "OrgCancelled" },
        done = { "✓", "OrgDone" },
        todo = { "˟", "OrgTODO" },
      },
    }
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
