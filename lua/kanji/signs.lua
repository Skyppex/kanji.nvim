local M = {}

local SIGNS = {
	add = { text = "A", name = "kanji_add", hl = "KanjiAdd" },
	change = { text = "M", name = "kanji_change", hl = "KanjiChange" },
	delete = { text = "D", name = "kanji_delete", hl = "KanjiDelete" },
}

function M.define()
	for _, sig in pairs(SIGNS) do
		vim.fn.sign_define(sig.name, {
			text = sig.text,
			texthl = sig.hl,
		})
	end
end

function M.place(bufnr, signs)
	for _, sign in ipairs(signs) do
		local sig = SIGNS[sign.type]
		if sig then
			vim.fn.sign_place(0, "kanji", sig.name, bufnr, {
				lnum = sign.line,
				id = sign.line,
			})
		end
	end
end

function M.clear(bufnr)
	vim.fn.sign_unplace("kanji", { buffer = bufnr, group = "kanji" })
end

return M
