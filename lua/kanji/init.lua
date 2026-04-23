local M = {}

local attach = require("kanji.attach")

--- @param opts KanjiOpts
function M.setup(opts)
	local config = require("kanji.config").merge(opts)
	attach.init(config)
end

function M.next_hunk()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.fn.line(".")
	local path = vim.api.nvim_buf_get_name(bufnr)
	if not path or path == "" then
		return
	end

	local relative_path = vim.fn.fnamemodify(path, ":.")
	local repo = require("kanji.repo")
	local diff = require("kanji.diff")

	repo.get_diff(relative_path, function(diff_output)
		local signs = diff.get_signs(diff_output)
		if #signs == 0 then
			return
		end

		-- Get first line of each group
		local group_starts = {}
		local prev_line = nil
		for _, s in ipairs(signs) do
			if prev_line == nil or s.line > prev_line + 1 then
				table.insert(group_starts, s.line)
			end
			prev_line = s.line
		end
		table.sort(group_starts)

		vim.schedule(function()
			local bufnr = vim.api.nvim_get_current_buf()
			local max_line = vim.api.nvim_buf_line_count(bufnr)
			if max_line < 1 then
				return
			end
			for _, lnum in ipairs(group_starts) do
				if lnum > cursor and lnum >= 1 and lnum <= max_line then
					vim.api.nvim_win_set_cursor(0, { lnum, 0 })
					return
				end
			end
			-- No hunk after cursor, try last hunk clamped to max line
			if #group_starts > 0 then
				local lnum = math.min(group_starts[#group_starts], max_line)
				if lnum >= 1 then
					vim.api.nvim_win_set_cursor(0, { lnum, 0 })
				end
			end
		end)
	end)
end

function M.prev_hunk()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.fn.line(".")
	local path = vim.api.nvim_buf_get_name(bufnr)
	if not path or path == "" then
		return
	end

	local relative_path = vim.fn.fnamemodify(path, ":.")
	local repo = require("kanji.repo")
	local diff = require("kanji.diff")

	repo.get_diff(relative_path, function(diff_output)
		local signs = diff.get_signs(diff_output)
		if #signs == 0 then
			return
		end

		-- Get first line of each group
		local group_starts = {}
		local prev_line = nil
		for _, s in ipairs(signs) do
			if prev_line == nil or s.line > prev_line + 1 then
				table.insert(group_starts, s.line)
			end
			prev_line = s.line
		end
		table.sort(group_starts)

		vim.schedule(function()
			local bufnr = vim.api.nvim_get_current_buf()
			local max_line = vim.api.nvim_buf_line_count(bufnr)
			if max_line < 1 then
				return
			end
			for i = #group_starts, 1, -1 do
				local lnum = group_starts[i]
				if lnum < cursor and lnum >= 1 and lnum <= max_line then
					vim.api.nvim_win_set_cursor(0, { lnum, 0 })
					return
				end
			end
			-- No hunk before cursor, try first hunk clamped to valid range
			if #group_starts > 0 then
				local lnum = math.min(group_starts[1], max_line)
				if lnum >= 1 then
					vim.api.nvim_win_set_cursor(0, { lnum, 0 })
				end
			end
		end)
	end)
end

return M