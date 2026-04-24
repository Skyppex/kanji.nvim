local M = {}

local repo = require("kanji.repo")

vim.api.nvim_command("highlight link KanjiInlineBlame WarningMsg")
vim.api.nvim_command("highlight link KanjiBlameLine1 @variable")
vim.api.nvim_command("highlight link KanjiBlameLine2 @constructor")
vim.api.nvim_command("highlight link KanjiBlameLine3 @keyword")
vim.api.nvim_command("highlight link KanjiBlameLine4 @constant")
vim.api.nvim_command("highlight link KanjiBlameLine5 @namespace")
vim.api.nvim_command("highlight link KanjiBlameLine6 @string")
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
	ns = nil,
	buffer_ns = nil,
	augroup = nil,
	buffer_cache = {},
	guide_ns = nil,
	active_bufnr = nil,
	active_extmark = nil,
}

local buffer_state = {
	--- @type table<number, number>
	blame_wins = {},
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

function M.buffer_toggle()
	local source_bufnr = vim.api.nvim_get_current_buf()
	local source_winid = vim.api.nvim_get_current_win()
	local path = vim.api.nvim_buf_get_name(source_bufnr)

	if not path or path == "" then
		return
	end

	if buffer_state.blame_wins[source_winid] and vim.api.nvim_win_is_valid(buffer_state.blame_wins[source_winid]) then
		vim.api.nvim_win_close(buffer_state.blame_wins[source_winid], true)
		buffer_state.blame_wins[source_winid] = nil
		return
	end

	state.buffer_ns = vim.api.nvim_create_namespace("kanji-blame-buffer")
	local relative_path = vim.fn.fnamemodify(path, ":.")
	local config = require("kanji.config").config
	local template = config.blame.buffer_template

	local line_template = 'join(" ", line_number, first_line_in_hunk, commit.description(), "\\n")'

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

function M.open_buffer_blame(source_winid, blame_lines, line_info)
	local blame_bufnr = vim.api.nvim_create_buf(false, true)
	local change_id_map = {}
	local color_index = 1

	for i, line in ipairs(line_info) do
		local parts = vim.split(vim.trim(line), " ", { plain = true })
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

	state.guide_ns = vim.api.nvim_create_namespace("kanji-blame-guide")

	local current_change_id = nil

	for i, line in ipairs(line_info) do
		local parts = vim.split(vim.trim(line), " ", { plain = true })
		local line_num = tonumber(parts[1])
		local is_first = parts[2] == "true"

		local next_parts = vim.split(vim.trim(line_info[i + 1] or ""), " ", { plain = true })
		local next_is_first = next_parts[2] == "true"

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
			guide_hl = "KanjiBlameGuide" .. tostring(change_id_map[current_change_id] or 1)

			local current_col = #guide + 1

			for j, part in ipairs(content_parts) do
				local hl_group
				if j == 1 then
					hl_group = guide_hl
				else
					hl_group = "KanjiBlameLine" .. tostring(((j - 2) % 8) + 1)
				end
				vim.api.nvim_buf_set_extmark(blame_bufnr, state.buffer_ns, i - 1, current_col, {
					end_line = i - 1,
					end_col = math.min(current_col + #part, #content),
					hl_group = hl_group,
				})

				current_col = current_col + #part + 1
			end
		else
			content = guide
			vim.api.nvim_buf_set_lines(blame_bufnr, i - 1, -1, false, { content })
			if current_change_id then
				guide_hl = "KanjiBlameGuide" .. tostring(change_id_map[current_change_id] or 1)
			end
		end

		vim.api.nvim_buf_set_extmark(blame_bufnr, state.guide_ns, i - 1, 0, {
			end_col = #guide,
			hl_group = guide_hl,
		})
	end

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

	buffer_state.blame_wins[source_winid] = blame_winid

	local augroup = vim.api.nvim_create_augroup("kanji_buffer_blame", { clear = true })

	vim.api.nvim_create_autocmd("WinClosed", {
		group = augroup,
		pattern = tostring(blame_winid),
		callback = function()
			buffer_state.blame_wins[source_winid] = nil
			vim.api.nvim_set_option_value("scrollbind", false, { win = source_winid })
			vim.api.nvim_del_augroup_by_id(augroup)
		end,
	})

	vim.api.nvim_create_autocmd("WinClosed", {
		group = augroup,
		pattern = tostring(source_winid),
		callback = function()
			local blame_win = buffer_state.blame_wins[source_winid]
			if blame_win and vim.api.nvim_win_is_valid(blame_win) then
				vim.api.nvim_win_close(blame_win, true)
			end
			buffer_state.blame_wins[source_winid] = nil
			vim.api.nvim_del_augroup_by_id(augroup)
		end,
	})

	vim.cmd.redraw()
	vim.cmd.syncbind()
end

return M
