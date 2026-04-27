local M = {}

local diff = require("kanji.diff")

vim.api.nvim_command("highlight link KanjiDiffAdd DiffAdd")
vim.api.nvim_command("highlight link KanjiDiffChange DiffChange")
vim.api.nvim_command("highlight link KanjiDiffDelete DiffDelete")

local HL_MAP = {
	add = "KanjiDiffAdd",
	change = "KanjiDiffChange",
	delete = "KanjiDiffDelete",
}

function M.setup()
	local config = require("kanji.config").config

	for sig_type, sig_opts in pairs(config.signs) do
		local name = "kanji_" .. sig_type
		local hl = HL_MAP[sig_type]

		vim.fn.sign_define(name, {
			text = sig_opts.text,
			texthl = hl,
		})
	end
end

function M.get_signs(diff_output)
	local hunks = diff.parse(diff_output)
	local signs = {}

	for _, hunk in ipairs(hunks) do
		for _, group in ipairs(hunk.groups) do
			for _, l in ipairs(group.lines) do
				table.insert(signs, {
					line = l.line,
					type = group.type,
				})
			end
		end
	end

	return signs
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
