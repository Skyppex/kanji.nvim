local M = {}

local HL_MAP = {
	add = "DiffAdd",
	change = "DiffChange",
	delete = "DiffDelete",
}

--- @param config KanjiOpts
function M.setup(config)
	for sig_type, sig_opts in pairs(config.signs) do
		local name = "kanji_" .. sig_type
		local hl = HL_MAP[sig_type]

		vim.fn.sign_define(name, {
			text = sig_opts.text,
			texthl = hl,
		})
	end
end

function M.place(bufnr, signs)
	for _, sign in ipairs(signs) do
		local name = "kanji_" .. sign.type
		vim.fn.sign_place(0, "kanji", name, bufnr, {
			lnum = sign.line,
			id = sign.line,
		})
	end
end

function M.clear(bufnr)
	vim.fn.sign_unplace("kanji", { buffer = bufnr, group = "kanji" })
end

return M

