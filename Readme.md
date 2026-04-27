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
{ "skyppex/kanji.nvim" }
```

## Usage

```lua
require("kanji").setup()
```

Signs will automatically appear in the signcolumn for files in a jj repository.

## Configuration

Customize sign text:

```lua
-- these are the defaults
require("kanji").setup({
	signs = {
		add = { text = "A" },
		change = { text = "M" },
		delete = { text = "D" },
	},
})
```

## Signs

Signs use Neovim's built-in highlight groups:

| Sign | Text | Highlight |
|------|------|----------|
| `kanji_add` | A | `DiffAdd` |
| `kanji_change` | M | `DiffChange` |
| `kanji_delete` | D | `DiffDelete` |

## Features

- [x] signcolumn markers
- [ ] conflict tools
    - [ ] jump to markers
    - [ ] display diff with external diff viewer
- [ ] blame annotations in a separate buffer
- [ ] inline blame
