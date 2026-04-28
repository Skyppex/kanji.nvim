local utils = require("kanji.utils")
local repo = require("kanji.repo")
local diff = require("kanji.diff")

local M = {}

local state = {
	winid = nil,
	bufnr = nil,
	augroup = nil,
}

function M.is_inspecting()
	return state.winid ~= nil and vim.api.nvim_win_is_valid(state.winid)
end

function M.is_inspect_win(winid)
	return winid and state.winid and winid == state.winid
end

function M.close()
	if state.winid and vim.api.nvim_win_is_valid(state.winid) then
		vim.api.nvim_win_close(state.winid, true)
	end

	state.winid = nil
	state.bufnr = nil

	if state.augroup then
		vim.api.nvim_del_augroup_by_id(state.augroup)
		state.augroup = nil
	end
end

local function get_change_id_at_cursor(bufnr, cursor_line, path, on_done)
	repo.get_blame('commit.change_id() ++ "\\n"', path, function(lines)
		if not lines or not lines[cursor_line] then
			on_done(nil)
			return
		end

		on_done(vim.trim(lines[cursor_line]))
	end)
end

local function format_markdown(revset_info, diff_lines)
	local parts = vim.split(vim.trim(revset_info), "|||", { plain = true })

	local change_id = parts[1] or ""
	local author_name = parts[2] or ""
	local author_email = parts[3] or ""
	local timestamp = parts[4] or ""
	local ago = parts[5] or ""
	local description = parts[6] or ""
	local description_lines = vim.split(description, "\n", { plain = true })
	local description_first_line = description_lines[1] or ""
	-- excluding the first line, trim the description as a single string and
	-- convert to newline separated list of lines
	local description_rest_lines = vim.split(vim.trim(table.concat(vim.list_slice(description_lines, 2), "\n")), "\n")

	local lines = {}

	table.insert(lines, "## " .. description_first_line)
	if
		description_rest_lines
		and #description_rest_lines ~= 0
		and not (#description_rest_lines == 1 and description_rest_lines[1] == "")
	then
		table.insert(lines, "")
		lines = vim.list_extend(lines, description_rest_lines)
	end

	table.insert(lines, "")
	table.insert(lines, "**Commit:** `" .. string.sub(change_id, 1, 8) .. "`")
	table.insert(lines, "**Author:** " .. author_name .. " (" .. author_email .. ")")
	table.insert(lines, "**Date:** " .. timestamp .. " (" .. ago .. ")")
	table.insert(lines, "")
	table.insert(lines, "```diff")

	if diff_lines and #diff_lines > 0 then
		for _, l in ipairs(diff_lines) do
			table.insert(lines, l)
		end
	else
		table.insert(lines, "-- No diff available --")
	end

	table.insert(lines, "```")

	return lines
end

local function open(lines)
	local config = require("kanji.config").config

	M.close()

	local width = 0
	for _, line in ipairs(lines) do
		local len = vim.fn.strdisplaywidth(line)
		if len > width then
			width = len
		end
	end

	width = math.min(width + 2, 80)

	local height = math.min(#lines, 30)

	local winopts = vim.tbl_deep_extend("force", {
		width = width,
		height = height,
		style = "minimal",
		focusable = true,
	}, config.inspect.winopts)

	local buf = vim.api.nvim_create_buf(false, true)
	state.bufnr = buf

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	state.winid = vim.api.nvim_open_win(buf, false, winopts)

	vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
	vim.api.nvim_set_option_value("readonly", true, { buf = buf })
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

	if config.hooks and config.hooks.on_inspect_show then
		config.hooks.on_inspect_show(buf, state.winid)
	end

	local group = vim.api.nvim_create_augroup("kanji_inspect", { clear = true })
	state.augroup = group

	vim.api.nvim_create_autocmd({ "BufLeave" }, {
		group = group,
		buffer = buf,
		callback = function()
			M.close()
		end,
	})

	vim.api.nvim_create_autocmd({ "CursorMoved" }, {
		group = group,
		callback = function()
			local cur_win = vim.api.nvim_get_current_win()
			if cur_win ~= state.winid and state.winid and vim.api.nvim_win_is_valid(state.winid) then
				M.close()
			end
		end,
	})
end

function M.show()
	local config = require("kanji.config").config

	-- Toggle: if float is open, move to it or close it
	if state.winid and vim.api.nvim_win_is_valid(state.winid) then
		local cur_win = vim.api.nvim_get_current_win()
		if cur_win == state.winid then
			M.close()
		else
			vim.api.nvim_set_current_win(state.winid)
			if config.hooks and config.hooks.on_inspect_focus then
				config.hooks.on_inspect_focus(state.bufnr, state.winid)
			end
		end
		return
	end

	local bufnr = vim.api.nvim_get_current_buf()
	local cursor_line = vim.fn.line(".")
	local blame = require("kanji.blame")
	local is_blame_buffer = blame.is_blame_buffer(bufnr)

	if is_blame_buffer then
		local path = blame.get_source_path()

		get_change_id_at_cursor(bufnr, cursor_line, path, function(change_id)
			if not change_id or change_id == "" then
				vim.notify("No commit found at cursor", vim.log.levels.WARN)
				return
			end

			local source_path = require("kanji.blame").state.buffer.source_path

			if not source_path or source_path == "" then
				vim.notify("No source file found", vim.log.levels.WARN)
				return
			end

			repo.get_revset_info(change_id, function(revset_info)
				if not revset_info then
					vim.notify("Failed to get revset info for " .. change_id, vim.log.levels.WARN)
					return
				end

				repo.get_commit_diff(change_id, source_path, function(diff_lines)
					local lines_to_show = diff_lines

					if diff_lines and #diff_lines > 0 then
						local hunks = diff.parse(diff_lines)
						local group = utils.find_group_at_line(hunks, cursor_line)

						if group then
							lines_to_show = diff.format_group_content(group)
						end
					end

					vim.schedule(function()
						local lines = format_markdown(revset_info[1] or "", lines_to_show)
						open(lines)
					end)
				end)
			end)
		end)

		return
	end

	local path = vim.api.nvim_buf_get_name(bufnr)

	if not path or path == "" then
		vim.notify("No file path found", vim.log.levels.WARN)
		return
	end

	local relative_path = vim.fn.fnamemodify(path, ":.")

	get_change_id_at_cursor(bufnr, cursor_line, relative_path, function(change_id)
		if not change_id then
			vim.notify("No commit found at cursor", vim.log.levels.WARN)
			return
		end

		repo.get_revset_info(change_id, function(commit_info)
			if not commit_info then
				vim.notify("Failed to get commit info for " .. change_id, vim.log.levels.WARN)
				return
			end

			repo.get_commit_diff(change_id, relative_path, function(diff_lines)
				local lines_to_show = diff_lines

				if diff_lines and #diff_lines > 0 then
					local hunks = diff.parse(diff_lines)
					local group = utils.find_group_at_line(hunks, cursor_line)

					if group then
						lines_to_show = diff.format_group_content(group)
					end
				end

				vim.schedule(function()
					local lines = format_markdown(commit_info[1] or "", lines_to_show)
					open(lines)
				end)
			end)
		end)
	end)
end

return M
