--- @class KanjiApi
--- @field setup fun(opts: KanjiOpts)
--- @field next_hunk fun()
--- @field prev_hunk fun()
--- @field preview_hunk fun()
--- @field close_preview fun()
--- @field restore_hunk fun()
--- @field restore_file fun()
--- @field blame_toggle fun()
--- @field blame_buffer_toggle fun()

--- @type KanjiApi
local M = {}

local attach = require("kanji.attach")
local preview = require("kanji.preview")
local blame = require("kanji.blame")
local utils = require("kanji.utils")
local repo = require("kanji.repo")
local signs = require("kanji.signs")

--- @param opts KanjiOpts
function M.setup(opts)
	require("kanji.config").configure(opts)
	attach.init()

	local config = require("kanji.config").config
	if config.blame and config.blame.enabled then
		blame.enable()
	end
end

function M.next_hunk()
	local previewing = preview.is_previewing()
	preview.close()

	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.fn.line(".")
	local path = vim.api.nvim_buf_get_name(bufnr)
	if not path or path == "" then
		return
	end

	local relative_path = vim.fn.fnamemodify(path, ":.")

	repo.get_diff(relative_path, function(diff_output)
		local sign_data = signs.get_signs(diff_output)
		if #sign_data == 0 then
			return
		end

		-- Get first line of each group
		local group_starts = {}
		local prev_line = nil
		for _, s in ipairs(sign_data) do
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

					if previewing then
						preview.toggle()
					end

					return
				end
			end
			-- No hunk after cursor, try last hunk clamped to max line
			if #group_starts > 0 then
				local lnum = math.min(group_starts[#group_starts], max_line)
				if lnum >= 1 then
					vim.api.nvim_win_set_cursor(0, { lnum, 0 })

					if previewing then
						preview.toggle()
					end
				end
			end
		end)
	end)
end

function M.prev_hunk()
	local previewing = preview.is_previewing()
	preview.close()

	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.fn.line(".")
	local path = vim.api.nvim_buf_get_name(bufnr)
	if not path or path == "" then
		return
	end

	local relative_path = vim.fn.fnamemodify(path, ":.")

	repo.get_diff(relative_path, function(diff_output)
		local sign_data = signs.get_signs(diff_output)
		if #sign_data == 0 then
			return
		end

		-- Get first line of each group
		local group_starts = {}
		local prev_line = nil
		for _, s in ipairs(sign_data) do
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

					if previewing then
						preview.toggle()
					end

					return
				end
			end
			-- No hunk before cursor, try first hunk clamped to valid range
			if #group_starts > 0 then
				local lnum = math.min(group_starts[1], max_line)
				if lnum >= 1 then
					vim.api.nvim_win_set_cursor(0, { lnum, 0 })

					if previewing then
						preview.toggle()
					end
				end
			end
		end)
	end)
end

function M.preview_hunk()
	preview.toggle()
end

function M.close_preview()
	preview.close()
end

function M.restore_hunk()
	local bufnr = vim.api.nvim_get_current_buf()
	local path = vim.api.nvim_buf_get_name(bufnr)

	if not path or path == "" then
		return
	end

	local relative_path = vim.fn.fnamemodify(path, ":.")
	local repo = require("kanji.repo")
	local diff = require("kanji.diff")

	repo.get_diff(relative_path, function(diff_output)
		if not diff_output or #diff_output == 0 then
			return
		end

		local hunks = diff.parse(diff_output)
		if #hunks == 0 then
			return
		end

		vim.schedule(function()
			local current_bufnr = vim.api.nvim_get_current_buf()
			local current_cursor = vim.fn.line(".")

			local target_group = utils.find_group_at_line(hunks, current_cursor)

			if not target_group then
				return
			end

			--- @type KanjiLine[]
			local lines_to_delete = {}

			--- @type KanjiLine[]
			local lines_to_restore = {}

			for _, l in ipairs(target_group.lines) do
				if l.type == "add" then
					table.insert(lines_to_delete, l)
				elseif l.type == "delete" then
					table.insert(lines_to_restore, l)
				end
			end

			lines_to_delete = vim.fn.reverse(lines_to_delete)

			for _, line in ipairs(lines_to_delete) do
				local adjusted = line.line - 1
				if adjusted >= 0 and adjusted < vim.api.nvim_buf_line_count(current_bufnr) then
					vim.api.nvim_buf_set_lines(current_bufnr, adjusted, adjusted + 1, true, {})
				end
			end

			lines_to_restore = vim.fn.reverse(lines_to_restore)

			if #lines_to_restore > 0 then
				local new_lines = {}
				local first_line = 0

				for i = #lines_to_restore, 1, -1 do
					if i == 1 then
						first_line = lines_to_restore[1].line - 1
					end

					table.insert(new_lines, lines_to_restore[i].text)
				end

				vim.api.nvim_buf_set_lines(current_bufnr, first_line, first_line, true, new_lines)
			end

			vim.cmd("noautocmd write!")
			attach.refresh(current_bufnr)
		end)
	end)
end

function M.restore_file()
	local bufnr = vim.api.nvim_get_current_buf()
	local path = vim.api.nvim_buf_get_name(bufnr)
	repo.restore_file(path, function(job)
		if not job then
			return
		end

		vim.schedule(function()
			vim.cmd("checktime")
		end)
	end)
end

function M.blame_toggle()
	blame.toggle()
end

function M.blame_buffer_toggle()
	blame.buffer_toggle()
end

return M
