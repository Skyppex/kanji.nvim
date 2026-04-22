local M = {}

M.defaults = {
	signs = {
		add = { text = "A" },
		change = { text = "M" },
		delete = { text = "D" },
	},
}

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