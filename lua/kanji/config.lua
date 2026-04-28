local M = {}

--- @class KanjiOpts
--- @field signs KanjiSignsOpts
--- @field preview KanjiPreviewOpts
--- @field hooks KanjiHooksOpts
--- @field blame KanjiBlameOpts

--- @class KanjiSignsOpts
--- @field add KanjiSignOpts

--- @class KanjiSignOpts
--- @field text string

--- @class KanjiPreviewOpts
--- @field winopts table<string, any>

--- @class KanjiHooksOpts
--- @field on_preview_show fun(bufnr: number)?
--- @field on_preview_focus fun(bufnr: number)?

--- @class KanjiBlameOpts
--- @field inline_template string
--- @field inline_separator string
--- @field buffer_template string
--- @field buffer_winopts table<string, any>
--- @field buffer_behavior "transient"|"follow"
--- @field enabled boolean

--- @type KanjiOpts
M.defaults = {
	signs = {
		add = { text = "A" },
		change = { text = "M" },
		delete = { text = "D" },
	},
	preview = {
		winopts = {
			border = "rounded",
			relative = "cursor",
			row = 0,
			col = 2,
		},
	},
	blame = {
		inline_template = 'join(" ", commit.author().name(), "-", commit.author().timestamp().ago(), "\n")',
		inline_separator = "   ",
		buffer_template = 'join("##", commit.change_id().shortest(8), commit.author().name(), commit.author().timestamp().local().format("%v %R")) ++ "\n"',
		buffer_winopts = {
			width = 48,
		},
		buffer_behavior = "transient",
		enabled = false,
	},
	hooks = {},
}

--- @type KanjiOpts
M.config = {}

--- @param user_opts KanjiOpts
function M.configure(user_opts)
	user_opts = user_opts or {}
	local config = vim.tbl_deep_extend("force", {}, M.defaults)

	if user_opts.signs then
		for sig_type, sig_opts in pairs(user_opts.signs) do
			if config.signs[sig_type] and sig_opts.text then
				config.signs[sig_type].text = sig_opts.text
			end
		end
	end

	if user_opts.preview and user_opts.preview.winopts then
		config.preview.winopts = vim.tbl_deep_extend("force", config.preview.winopts, user_opts.preview.winopts)
	end

	if user_opts.hooks then
		config.hooks = vim.tbl_deep_extend("force", config.hooks, user_opts.hooks)
	end

	if user_opts.blame then
		if user_opts.blame.inline_template then
			config.blame.inline_template = user_opts.blame.inline_template
		end
		if user_opts.blame.inline_separator then
			config.blame.inline_separator = user_opts.blame.inline_separator
		end
		if user_opts.blame.buffer_template then
			config.blame.buffer_template = user_opts.blame.buffer_template
		end
		if user_opts.blame.buffer_winopts then
			config.blame.buffer_winopts =
				vim.tbl_deep_extend("force", config.blame.buffer_winopts, user_opts.blame.buffer_winopts)
		end
		if user_opts.blame.buffer_behavior then
			config.blame.buffer_behavior = user_opts.blame.buffer_behavior
		end
		if user_opts.blame.enabled ~= nil then
			config.blame.enabled = user_opts.blame.enabled
		end
	end

	M.config = config
end

return M
