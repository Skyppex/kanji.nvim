local M = {}

local repo = require("kanji.repo")

vim.api.nvim_command("highlight link KanjiInlineBlame WarningMsg")
vim.api.nvim_command("highlight link KanjiBlameDescription @comment")

vim.api.nvim_command("highlight link KanjiBlameLine1 @constructor")
vim.api.nvim_command("highlight link KanjiBlameLine2 @namespace")
vim.api.nvim_command("highlight link KanjiBlameLine3 @variable")
vim.api.nvim_command("highlight link KanjiBlameLine4 @keyword")
vim.api.nvim_command("highlight link KanjiBlameLine5 @string")
vim.api.nvim_command("highlight link KanjiBlameLine6 @constant")
vim.api.nvim_command("highlight link KanjiBlameLine7 @property")
vim.api.nvim_command("highlight link KanjiBlameLine8 @comment")

vim.api.nvim_command("highlight link KanjiBlameGuide1 @property")
vim.api.nvim_command("highlight link KanjiBlameGuide2 @variable")
vim.api.nvim_command("highlight link KanjiBlameGuide3 @constructor")
vim.api.nvim_command("highlight link KanjiBlameGuide4 @keyword")
vim.api.nvim_command("highlight link KanjiBlameGuide5 @constant")
vim.api.nvim_command("highlight link KanjiBlameGuide6 @namespace")
vim.api.nvim_command("highlight link KanjiBlameGuide7 @string")
vim.api.nvim_command("highlight link KanjiBlameGuide8 @number")

local state = {
	enabled = false,
	inline = {
		ns = nil,
		augroup = nil,
		buffer_cache = {},
		active_bufnr = nil,
		active_extmark = nil,
	},
	buffer = {
		enabled = false,
		behavior = nil,
		ns = nil,
		augroup = nil,
		guide_ns = nil,
		blame_win = nil,
		blame_buf = nil,
		source_win = nil,
		source_path = nil,
	},
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
	state.inline.ns = vim.api.nvim_create_namespace("kanji-blame")
	state.inline.augroup = vim.api.nvim_create_augroup("kanji-blame", { clear = true })

	local bufnr = vim.api.nvim_get_current_buf()
	M.blame_buffer(bufnr)

	vim.api.nvim_create_autocmd({ "CursorMoved", "BufEnter", "BufReadPost", "BufWritePost" }, {
		group = state.inline.augroup,
		callback = function(args)
			M.blame_buffer(args.buf)
		end,
	})

	vim.api.nvim_create_autocmd("BufUnload", {
		group = state.inline.augroup,
		callback = function(args)
			state.inline.buffer_cache[args.buf] = nil
			if state.inline.active_bufnr == args.buf then
				state.inline.active_bufnr = nil
				state.inline.active_extmark = nil
			end
		end,
	})
end

function M.disable()
	if not state.enabled then
		return
	end

	state.enabled = false

	for bufnr, _ in pairs(state.inline.buffer_cache) do
		if vim.api.nvim_buf_is_valid(bufnr) and state.inline.ns then
			vim.api.nvim_buf_clear_namespace(bufnr, state.inline.ns, 0, -1)
		end
	end

	state.inline.buffer_cache = {}
	state.inline.active_bufnr = nil
	state.inline.active_extmark = nil

	if state.inline.augroup then
		pcall(vim.api.nvim_del_augroup_by_id, state.inline.augroup)
	end

	state.inline.augroup = nil
end

function M.blame_buffer(bufnr)
	local path = vim.api.nvim_buf_get_name(bufnr)
	if not path or path == "" then
		return
	end

	if state.inline.buffer_cache[bufnr] then
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
			state.inline.buffer_cache[bufnr] = lines
			M.refresh_extmark(bufnr)
		end)
	end)
end

function M.refresh_extmark(bufnr)
	if not state.enabled then
		return
	end

	local annotations = state.inline.buffer_cache[bufnr]
	if not annotations then
		return
	end

	if not vim.api.nvim_buf_is_valid(bufnr) then
		state.inline.buffer_cache[bufnr] = nil
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

	if state.inline.active_bufnr and state.inline.active_extmark then
		if vim.api.nvim_buf_is_valid(state.inline.active_bufnr) then
			vim.api.nvim_buf_del_extmark(state.inline.active_bufnr, state.inline.ns, state.inline.active_extmark)
		end
	end

	local buf_len = vim.api.nvim_buf_get_lines(bufnr, cursor_line, cursor_line + 1, true)[1]
	local col = buf_len and #buf_len or 0

	local config = require("kanji.config").config
	local separator = config.blame.inline_separator or "   "
	blame_text = separator .. blame_text

	state.inline.active_bufnr = bufnr
	state.inline.active_extmark = vim.api.nvim_buf_set_extmark(bufnr, state.inline.ns, cursor_line, col, {
		virt_text = { { blame_text, "KanjiInlineBlame" } },
		virt_text_pos = "eol",
	})
end

function M.buffer_toggle()
	local source_bufnr = vim.api.nvim_get_current_buf()
	local path = vim.api.nvim_buf_get_name(source_bufnr)

	if not path or path == "" then
		return
	end

	if state.buffer.blame_win and vim.api.nvim_win_is_valid(state.buffer.blame_win) then
		vim.api.nvim_win_close(state.buffer.blame_win, true)
		state.buffer.blame_win = nil
		state.buffer.blame_buf = nil
		state.buffer.enabled = false
		return
	end

	if not state.buffer.enabled then
		state.buffer.enabled = true
		state.buffer.behavior = require("kanji.config").config.blame.buffer_behavior
		state.buffer.augroup = vim.api.nvim_create_augroup("kanji-buffer-blame", { clear = true })

		vim.api.nvim_create_autocmd("WinEnter", {
			group = state.buffer.augroup,
			callback = function(args)
				if not state.buffer.enabled then
					return
				end

				local current_win = vim.api.nvim_get_current_win()

				if current_win == state.buffer.blame_win or current_win == state.buffer.source_win then
					return
				end

				if state.buffer.blame_win and vim.api.nvim_win_is_valid(state.buffer.blame_win) then
					vim.api.nvim_win_close(state.buffer.blame_win, true)
				end

				state.buffer.blame_win = nil
				state.buffer.blame_buf = nil
				state.buffer.source_win = nil
				state.buffer.source_path = nil

				if state.buffer.behavior == "transient" then
					state.buffer.enabled = false
				end
				local buf_name = vim.api.nvim_buf_get_name(args.buf)

				if buf_name:match("kanji%-blame$") then
					return
				end

				local path = buf_name

				if not path or path == "" then
					return
				end

				state.buffer.source_path = path
				M.open_new_buffer_blame(path)
			end,
		})

		vim.api.nvim_create_autocmd("WinClosed", {
			group = state.buffer.augroup,
			callback = function(args)
				if not state.buffer.enabled then
					return
				end

				if tonumber(args.match) == state.buffer.blame_win then
					state.buffer.blame_win = nil
					state.buffer.blame_buf = nil
					state.buffer.source_win = nil
					state.buffer.source_path = nil
					state.buffer.enabled = false
					return
				end

				if tonumber(args.match) ~= state.buffer.source_win then
					return
				end

				if state.buffer.blame_win and vim.api.nvim_win_is_valid(state.buffer.blame_win) then
					vim.api.nvim_win_close(state.buffer.blame_win, true)
				end

				state.buffer.blame_win = nil
				state.buffer.blame_buf = nil
				state.buffer.source_win = nil
				state.buffer.source_path = nil

				if state.buffer.behavior == "transient" then
					state.buffer.enabled = false
				end
			end,
		})

		vim.api.nvim_create_autocmd("BufEnter", {
			group = state.buffer.augroup,
			callback = function(args)
				if not state.buffer.enabled then
					return
				end

				local buf_name = vim.api.nvim_buf_get_name(args.buf)
				if buf_name:match("kanji%-blame$") then
					return
				end

				local path = buf_name
				if not path or path == "" then
					return
				end

				if state.buffer.source_path == path then
					return
				end

				state.buffer.source_path = path

				if state.buffer.blame_win and vim.api.nvim_win_is_valid(state.buffer.blame_win) then
					M.update_buffer_blame(path)
				end
			end,
		})
	end

	local source_bufnr = vim.api.nvim_get_current_buf()
	local path = vim.api.nvim_buf_get_name(source_bufnr)
	state.buffer.source_path = path
	M.open_new_buffer_blame(path)
end

function M.open_new_buffer_blame(path)
	if not path or path == "" then
		return
	end

	state.buffer.source_path = path
	local source_winid = vim.api.nvim_get_current_win()
	state.buffer.ns = vim.api.nvim_create_namespace("kanji-blame-buffer")
	local relative_path = vim.fn.fnamemodify(path, ":.")
	local config = require("kanji.config").config
	local template = config.blame.buffer_template

	local line_template = 'join("##", line_number, first_line_in_hunk, commit.description().first_line()) ++ "\\n"'

	repo.get_blame(template, relative_path, function(blame_lines)
		if not blame_lines then
			return
		end
		repo.get_blame(line_template, relative_path, function(line_info)
			if not line_info then
				return
			end
			vim.schedule(function()
				M.open_buffer_blame(source_winid, blame_lines, line_info)
			end)
		end)
	end)
end

function M.update_buffer_blame(path)
	local relative_path = vim.fn.fnamemodify(path, ":.")
	local config = require("kanji.config").config
	local template = config.blame.buffer_template

	local line_template = 'join("##", line_number, first_line_in_hunk, commit.description().first_line()) ++ "\\n"'

	repo.get_blame(template, relative_path, function(blame_lines)
		if not blame_lines then
			return
		end
		repo.get_blame(line_template, relative_path, function(line_info)
			if not line_info then
				return
			end
			vim.schedule(function()
				M._update_buffer_blame_content(blame_lines, line_info)
			end)
		end)
	end)
end

function M._update_buffer_blame_content(blame_lines, line_info)
	if not state.buffer.blame_win or not vim.api.nvim_win_is_valid(state.buffer.blame_win) then
		return
	end

	local blame_bufnr = vim.api.nvim_win_get_buf(state.buffer.blame_win)
	if not blame_bufnr or not vim.api.nvim_buf_is_valid(blame_bufnr) then
		return
	end

	M.write_blame_buffer_content(blame_bufnr, blame_lines, line_info)

	vim.cmd.redraw()
end

function M.write_blame_buffer_content(blame_bufnr, blame_lines, line_info)
	vim.api.nvim_set_option_value("modifiable", true, { buf = blame_bufnr })

	state.buffer.ns = vim.api.nvim_create_namespace("kanji-blame-buffer")
	state.buffer.guide_ns = vim.api.nvim_create_namespace("kanji-blame-guide")

	local change_id_map = {}
	local color_index = 1

	for i, line in ipairs(line_info) do
		local parts = vim.split(vim.trim(line), "##", { plain = true })
		local line_num = tonumber(parts[1])
		local is_first = parts[2] == "true"

		if is_first and line_num and blame_lines[line_num] then
			local content_parts = vim.split(vim.trim(blame_lines[line_num]), "##", { plain = true })
			local change_id = content_parts[1]
			if change_id and not change_id_map[change_id] then
				change_id_map[change_id] = color_index
				color_index = color_index + 1
			end
		end
	end

	vim.api.nvim_buf_set_lines(blame_bufnr, 0, -1, false, {})

	local current_change_id = nil

	for i, line in ipairs(line_info) do
		local parts = vim.split(vim.trim(line), "##", { plain = true })
		local line_num = tonumber(parts[1])
		local is_first = parts[2] == "true"
		local description = parts[3]

		local next_parts = vim.split(vim.trim(line_info[i + 1] or ""), "##", { plain = true })
		local next_is_first = next_parts[2] == nil or next_parts[2] == "true"

		local prev_parts = vim.split(vim.trim(line_info[i - 1] or ""), "##", { plain = true })
		local prev_is_first = prev_parts[2] == "true"

		local guide = "│"
		if is_first and next_is_first then
			guide = "╺"
		elseif is_first and not next_is_first then
			guide = "┍"
		elseif not is_first and next_is_first then
			guide = "┕"
		end

		local content_parts = vim.split(vim.trim(blame_lines[line_num]), "##", { plain = true })
		local content = ""
		local guide_hl = "KanjiBlameGuide1"

		if is_first and line_num and blame_lines[line_num] then
			current_change_id = content_parts[1]
			content = guide .. " " .. table.concat(content_parts, " ")
			vim.api.nvim_buf_set_lines(blame_bufnr, i - 1, -1, false, { content })
			guide_hl = "KanjiBlameGuide" .. tostring(change_id_map[current_change_id] % 8 or 1)

			local current_col = #guide + 1

			for j, part in ipairs(content_parts) do
				local hl_group
				if j == 1 then
					hl_group = guide_hl
				else
					hl_group = "KanjiBlameLine" .. tostring(((j - 2) % 8) + 1)
				end
				vim.api.nvim_buf_set_extmark(blame_bufnr, state.buffer.ns, i - 1, current_col, {
					end_line = i - 1,
					end_col = math.min(current_col + #part, #content),
					hl_group = hl_group,
				})

				current_col = current_col + #part + 1
			end
		else
			content = guide

			if prev_is_first then
				content = content .. " " .. description
			end

			vim.api.nvim_buf_set_lines(blame_bufnr, i - 1, -1, false, { content })

			if current_change_id then
				guide_hl = "KanjiBlameGuide" .. tostring(change_id_map[current_change_id] % 8 or 1)
			end

			if prev_is_first then
				vim.api.nvim_buf_set_extmark(blame_bufnr, state.buffer.ns, i - 1, 2, {
					hl_group = "KanjiBlameDescription",
					end_col = #description + 4,
				})
			end
		end

		vim.api.nvim_buf_set_extmark(blame_bufnr, state.buffer.guide_ns, i - 1, 0, {
			end_col = #guide,
			hl_group = guide_hl,
		})
	end

	vim.api.nvim_set_option_value("modifiable", false, { buf = blame_bufnr })
end

function M.open_buffer_blame(source_winid, blame_lines, line_info)
	local blame_bufnr = vim.api.nvim_create_buf(false, true)

	M.write_blame_buffer_content(blame_bufnr, blame_lines, line_info)

	vim.api.nvim_set_option_value("readonly", true, { buf = blame_bufnr })
	vim.api.nvim_set_option_value("modifiable", false, { buf = blame_bufnr })
	vim.api.nvim_set_option_value("filetype", "kanji-blame", { buf = blame_bufnr })

	local config = require("kanji.config").config
	local winopts = vim.tbl_deep_extend("force", {
		win = 0,
		split = "left",
	}, config.blame.buffer_winopts)

	local blame_winid = vim.api.nvim_open_win(blame_bufnr, false, winopts)
	vim.api.nvim_set_option_value("wrap", false, { win = blame_winid })
	vim.api.nvim_set_option_value("winfixwidth", true, { win = blame_winid })
	vim.api.nvim_set_option_value("number", false, { win = blame_winid })
	vim.api.nvim_set_option_value("relativenumber", false, { win = blame_winid })
	vim.api.nvim_set_option_value("signcolumn", "no", { win = blame_winid })
	vim.api.nvim_set_option_value("scrollbind", true, { win = blame_winid })
	vim.api.nvim_set_option_value("scrollbind", true, { win = source_winid })

	state.buffer.blame_win = blame_winid
	state.buffer.blame_buf = blame_bufnr
	state.buffer.source_win = source_winid

	vim.cmd.redraw()
	vim.cmd.syncbind()
end

return M
