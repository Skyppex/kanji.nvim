# test.md

```diff
-return {}
+local utils = require("kanji.utils")
+local repo = require("kanji.repo")
+local diff = require("kanji.diff")
+
+local M = {}
+
+local state = {
+	winid = nil,
+	bufnr = nil,
+	augroup = nil,
+}
+
+function M.is_inspecting()
+	return state.winid ~= nil and vim.api.nvim_win_is_valid(state.winid)
+end
+
+function M.close()
+	if state.winid and vim.api.nvim_win_is_valid(state.winid) then
+		vim.api.nvim_win_close(state.winid, true)
+	end
+
+	state.winid = nil
+	state.bufnr = nil
+
+	if state.augroup then
+		vim.api.nvim_del_augroup_by_id(state.augroup)
+		state.augroup = nil
+	end
+end
+
+local function get_change_id_from_blame_buffer()
+	local line = vim.api.nvim_get_current_line()
+	local parts = vim.split(vim.trim(line), "##", { plain = true })
+	return parts[1]
+end
+
+local function get_change_id_from_source(bufnr, cursor_line, path, on_done)
+	repo.get_blame("commit.change_id()", path, function(lines)
+		if not lines or not lines[cursor_line] then
+			on_done(nil)
+			return
+		end
+
+		on_done(vim.trim(lines[cursor_line]))
+	end)
+end
+
+local function format_markdown(commit_info, diff_lines)
+	local parts = vim.split(vim.trim(commit_info), "##", { plain = true })
+
+	local change_id = parts[1] or ""
+	local author = parts[2] or ""
+	local timestamp = parts[3] or ""
+	local description = ""
+	for i = 4, #parts do
+		description = description .. parts[i]
+		if i < #parts then
+			description = description .. "##"
+		end
+	end
+
+	local lines = {}
+
+	table.insert(lines, "## Commit: `" .. change_id .. "`")
+	table.insert(lines, "")
+	table.insert(lines, "**Author:** " .. author)
+	table.insert(lines, "")
+	table.insert(lines, "**Date:** " .. timestamp)
+	table.insert(lines, "")
+	table.insert(lines, "### Description")
+	table.insert(lines, "")
+	table.insert(lines, description)
+	table.insert(lines, "")
+	table.insert(lines, "### Diff")
+	table.insert(lines, "")
+	table.insert(lines, "```diff")
+
+	if diff_lines and #diff_lines > 0 then
+		for _, l in ipairs(diff_lines) do
+			table.insert(lines, l)
+		end
+	else
+		table.insert(lines, "-- No diff available --")
+	end
+
+	table.insert(lines, "```")
+
+	return lines
+end
+
+local function open(lines)
+	local config = require("kanji.config").config
+
+	M.close()
+
+	local width = 0
+	for _, line in ipairs(lines) do
+		local len = vim.fn.strdisplaywidth(line)
+		if len > width then
+			width = len
+		end
+	end
+
+	width = math.min(width + 2, 80)
+
+	local height = math.min(#lines, 30)
+
+	local winopts = vim.tbl_deep_extend("force", {
+		width = width,
+		height = height,
+		style = "minimal",
+		focusable = true,
+	}, config.inspect.winopts)
+
+	local buf = vim.api.nvim_create_buf(false, true)
+	state.bufnr = buf
+
+	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
+
+	vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
+	vim.api.nvim_set_option_value("readonly", true, { buf = buf })
+	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
+
+	state.winid = vim.api.nvim_open_win(buf, false, winopts)
+
+	local group = vim.api.nvim_create_augroup("kanji_inspect", { clear = true })
+	state.augroup = group
+
+	vim.api.nvim_create_autocmd({ "BufLeave" }, {
+		group = group,
+		buffer = buf,
+		callback = function()
+			M.close()
+		end,
+	})
+
+	vim.api.nvim_create_autocmd({ "CursorMoved" }, {
+		group = group,
+		callback = function()
+			local cur_win = vim.api.nvim_get_current_win()
+			if cur_win ~= state.winid and state.winid and vim.api.nvim_win_is_valid(state.winid) then
+				M.close()
+			end
+		end,
+	})
+end
+
+function M.show()
+	local bufnr = vim.api.nvim_get_current_buf()
+	local cursor_line = vim.fn.line(".")
+	local path = vim.api.nvim_buf_get_name(bufnr)
+	local is_blame_buffer = vim.api.nvim_get_option_value("filetype", { buf = bufnr }) == "kanji-blame"
+
+	if is_blame_buffer then
+		local change_id = get_change_id_from_blame_buffer()
+		if not change_id or change_id == "" then
+			vim.notify("No commit found at cursor", vim.log.levels.WARN)
+			return
+		end
+
+		local source_path = require("kanji.blame").state.buffer.source_path
+		if not source_path or source_path == "" then
+			vim.notify("No source file found", vim.log.levels.WARN)
+			return
+		end
+
+		repo.get_commit_info(change_id, function(commit_info)
+			if not commit_info then
+				vim.notify("Failed to get commit info for " .. change_id, vim.log.levels.WARN)
+				return
+			end
+
+			repo.get_commit_diff(change_id, source_path, function(diff_lines)
+				vim.schedule(function()
+					local lines = format_markdown(commit_info[1] or "", diff_lines)
+					open(lines)
+				end)
+			end)
+		end)
+
+		return
+	end
+
+	if not path or path == "" then
+		vim.notify("No file path found", vim.log.levels.WARN)
+		return
+	end
+
+	local relative_path = vim.fn.fnamemodify(path, ":.")
+
+	get_change_id_from_source(bufnr, cursor_line, relative_path, function(change_id)
+		if not change_id then
+			vim.notify("No commit found at cursor", vim.log.levels.WARN)
+			return
+		end
+
+		repo.get_commit_info(change_id, function(commit_info)
+			if not commit_info then
+				vim.notify("Failed to get commit info for " .. change_id, vim.log.levels.WARN)
+				return
+			end
+
+			repo.get_commit_diff(change_id, relative_path, function(diff_lines)
+				vim.schedule(function()
+					local lines = format_markdown(commit_info[1] or "", diff_lines)
+					open(lines)
+				end)
+			end)
+		end)
+	end)
+end
+
+return M
```
