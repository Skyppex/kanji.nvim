local M = {}

--- @class KanjiOpts
--- @field signs KanjiSignsOpts
--- @field preview KanjiPreviewOpts
--- @field hooks KanjiHooksOpts

--- @class KanjiSignsOpts
--- @field add KanjiSignOpts

--- @class KanjiSignOpts
--- @field text string

--- @class KanjiPreviewOpts
--- @field winopts table<string, any>

--- @class KanjiHooksOpts
--- @field on_preview_show fun(bufnr: number)?
--- @field on_preview_focus fun(bufnr: number)?

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

	M.config = config
end

return M
