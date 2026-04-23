local M = {}

--- @class KanjiOpts
--- @field signs KanjiSignsOpts
---
--- @class KanjiSignsOpts
--- @field add KanjiSignOpts
---
--- @class KanjiSignOpts
--- @field text string

--- @type KanjiOpts
M.defaults = {
	signs = {
		add = { text = "A" },
		change = { text = "M" },
		delete = { text = "D" },
	},
}

--- @param user_opts KanjiOpts
function M.merge(user_opts)
	user_opts = user_opts or {}
	local config = vim.deepcopy(M.defaults)

	if user_opts.signs then
		for sig_type, sig_opts in pairs(user_opts.signs) do
			if config.signs[sig_type] and sig_opts.text then
				config.signs[sig_type].text = sig_opts.text
			end
		end
	end

	return config
end

return M

