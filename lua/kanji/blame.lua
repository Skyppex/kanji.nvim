local M = {}

local repo = require("kanji.repo")

vim.api.nvim_command("highlight link KanjiInlineBlame WarningMsg")

local state = {
	enabled = false,
	ns = nil,
	augroup = nil,
	buffer_cache = {},
	active_bufnr = nil,
	active_extmark = nil,
}

function M.is_enabled()
	return state.enabled
end

function M.toggle()
	if state.enabled then
		M.disable()
	else
		M.enable()
	end
end

function M.enable()
	if state.enabled then
		return
	end

	state.enabled = true
	state.ns = vim.api.nvim_create_namespace("kanji-blame")
	state.augroup = vim.api.nvim_create_augroup("kanji-blame", { clear = true })

	local bufnr = vim.api.nvim_get_current_buf()
	M.blame_buffer(bufnr)

	vim.api.nvim_create_autocmd({ "CursorMoved", "BufEnter", "BufReadPost", "BufWritePost" }, {
		group = state.augroup,
		callback = function(args)
			M.blame_buffer(args.buf)
		end,
	})

	vim.api.nvim_create_autocmd("BufUnload", {
		group = state.augroup,
		callback = function(args)
			state.buffer_cache[args.buf] = nil
			if state.active_bufnr == args.buf then
				state.active_bufnr = nil
				state.active_extmark = nil
			end
		end,
	})
end

function M.disable()
	if not state.enabled then
		return
	end

	state.enabled = false

	for bufnr, _ in pairs(state.buffer_cache) do
		if vim.api.nvim_buf_is_valid(bufnr) and state.ns then
			vim.api.nvim_buf_clear_namespace(bufnr, state.ns, 0, -1)
		end
	end

	state.buffer_cache = {}
	state.active_bufnr = nil
	state.active_extmark = nil

	if state.augroup then
		pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
	end

	state.augroup = nil
end

function M.blame_buffer(bufnr)
	local path = vim.api.nvim_buf_get_name(bufnr)
	if not path or path == "" then
		return
	end

	if state.buffer_cache[bufnr] then
		M.refresh_extmark(bufnr)
		return
	end

	local relative_path = vim.fn.fnamemodify(path, ":.")
	local config = require("kanji.config").config
	local template = config.blame.inline_template

	repo.get_blame(template, relative_path, function(lines)
		if not lines then
			return
		end
		vim.schedule(function()
			state.buffer_cache[bufnr] = lines
			M.refresh_extmark(bufnr)
		end)
	end)
end

function M.refresh_extmark(bufnr)
	if not state.enabled then
		return
	end

	local annotations = state.buffer_cache[bufnr]
	if not annotations then
		return
	end

	if not vim.api.nvim_buf_is_valid(bufnr) then
		state.buffer_cache[bufnr] = nil
		return
	end

	local cursor_line = vim.fn.line(".") - 1

	if cursor_line < 0 or cursor_line >= #annotations then
		return
	end

	local blame_text = annotations[cursor_line + 1]
	if not blame_text or blame_text == "" then
		return
	end

	if state.active_bufnr and state.active_extmark then
		if vim.api.nvim_buf_is_valid(state.active_bufnr) then
			vim.api.nvim_buf_del_extmark(state.active_bufnr, state.ns, state.active_extmark)
		end
	end

	local buf_len = vim.api.nvim_buf_get_lines(bufnr, cursor_line, cursor_line + 1, true)[1]
	local col = buf_len and #buf_len or 0

	local config = require("kanji.config").config
	local separator = config.blame.inline_separator or "   "
	blame_text = separator .. blame_text

	state.active_bufnr = bufnr
	state.active_extmark = vim.api.nvim_buf_set_extmark(bufnr, state.ns, cursor_line, col, {
		virt_text = { { blame_text, "KanjiInlineBlame" } },
		virt_text_pos = "eol",
	})
end

return M
