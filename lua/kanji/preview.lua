local M = {}

local state = {
	winid = nil,
	bufnr = nil,
	augroup = nil,
}

function M.is_previewing()
	return state.winid ~= nil and vim.api.nvim_win_is_valid(state.winid)
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

local function find_group_at_line(hunks, cursor_line)
	for _, hunk in ipairs(hunks) do
		for _, group in ipairs(hunk.groups) do
			local first_line = group.lines[1] and group.lines[1].line
			local last_line = group.lines[#group.lines] and group.lines[#group.lines].line
			if first_line and last_line then
				if cursor_line >= first_line and cursor_line <= last_line then
					return group
				end
			end
		end
	end
	return nil
end

local function format_group_content(group)
	local lines = {}
	for _, l in ipairs(group.lines) do
		local prefix = ""
		if l.type == "add" then
			prefix = "+"
		elseif l.type == "delete" then
			prefix = "-"
		end
		table.insert(lines, prefix .. l.text)
	end
	return lines
end

local function open(lines, focus)
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

	local height = math.min(#lines, 15)

	local winopts = vim.tbl_deep_extend("force", {
		width = width,
		height = height,
		style = "minimal",
		focusable = true,
	}, config.preview.winopts)

	local buf = vim.api.nvim_create_buf(false, true)
	state.bufnr = buf

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	vim.api.nvim_set_option_value("filetype", "diff", { buf = buf })
	vim.api.nvim_set_option_value("readonly", true, { buf = buf })
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

	state.winid = vim.api.nvim_open_win(buf, focus, winopts)

	if config.hooks and config.hooks.on_preview_show then
		config.hooks.on_preview_show(buf)
	end

	local group = vim.api.nvim_create_augroup("kanji_preview", { clear = true })
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

	return state.winid
end

function M.toggle()
	local config = require("kanji.config").config

	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.fn.line(".")
	local path = vim.api.nvim_buf_get_name(bufnr)

	if not path or path == "" then
		M.close()
		return
	end

	local relative_path = vim.fn.fnamemodify(path, ":.")
	local repo = require("kanji.repo")
	local diff = require("kanji.diff")

	if state.winid and vim.api.nvim_win_is_valid(state.winid) then
		local cur_win = vim.api.nvim_get_current_win()
		if cur_win == state.winid then
			M.close()
		else
			vim.api.nvim_set_current_win(state.winid)
			if config.hooks and config.hooks.on_preview_focus then
				config.hooks.on_preview_focus(state.bufnr)
			end
		end
	else
		repo.get_diff(relative_path, function(diff_output)
			local hunks = diff.parse(diff_output)
			if #hunks == 0 then
				M.close()
				return
			end

			local group = find_group_at_line(hunks, cursor)
			if not group then
				M.close()
				return
			end

			local lines = format_group_content(group)

			vim.schedule(function()
				open(lines, false)
			end)
		end)
	end
end

return M
