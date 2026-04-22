# kanji.nvim

Deep buffer integration for Jujutsu (jj) VCS, inspired by gitsigns.nvim.

## Requirements

- Neovim 0.11+
- plenary.nvim
- jj CLI

## Installation

Using your plugin manager:

```lua
-- lazy.nvim
{ "your username/kanji.nvim" }
```

## Usage

```lua
require("kanji").setup()
```

Signs will automatically appear in the signcolumn for files in a jj repository.

## Signs

| Sign | Text | Type |
|------|------|------|
| `kanji_add` | A | Added lines |
| `kanji_change` | M | Modified lines |
| `kanji_delete` | D | Deleted lines |

## Features

- [x] signcolumn markers
- [ ] conflict tools
    - [ ] jump to markers
    - [ ] display diff with external diff viewer
- [ ] blame annotations in a separate buffer
- [ ] inline blame