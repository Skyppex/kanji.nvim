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

## Configuration

Customize sign text:

```lua
require("kanji").setup({
	signs = {
		add = { text = "+" },
		change = { text = "~" },
		delete = { text = "-" },
	},
})
```

Default sign text: `A` (add), `M` (change), `D` (delete)

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

╺ ┍ │ ┕
