local M = {}

local repo = require("kanji.repo")
local diff = require("kanji.diff")
local signs = require("kanji.signs")

M.attached_buffers = {}

function M.refresh(bufnr)
	local path = vim.api.nvim_buf_get_name(bufnr)
	if not path or path == "" then
		return
	end

	local relative_path = vim.fn.fnamemodify(path, ":.")
	repo.get_diff(relative_path, function(diff_output)
		local sign_list = diff.get_signs(diff_output)
		vim.schedule(function()
			signs.clear(bufnr)
			if #sign_list > 0 then
				signs.place(bufnr, sign_list)
			end
		end)
	end)
end

local function debounce(fn, delay)
	local timer = vim.uv.new_timer()
	return function(...)
		local argv = { ... }
		timer:start(delay, 0, function()
			timer:close()
			vim.schedule_wrap(fn)(unpack(argv))
		end)
	end
end

local debounced_refresh = debounce(function(bufnr)
	M.refresh(bufnr)
end, 100)

function M.attach(bufnr)
	if M.attached_buffers[bufnr] then
		return
	end

	local path = vim.api.nvim_buf_get_name(bufnr)
	if not path or path == "" then
		return
	end

	if not repo.is_repo() then
		return
	end

	M.attached_buffers[bufnr] = true
	M.refresh(bufnr)

	vim.api.nvim_buf_attach(bufnr, false, {
		on_lines = function()
			debounced_refresh(bufnr)
		end,
		on_reload = function()
			M.refresh(bufnr)
		end,
	})
end

--- @param config KanjiOpts
function M.init(config)
	signs.setup(config)

	vim.api.nvim_create_autocmd("BufReadPost", {
		pattern = "*",
		callback = function(args)
			M.attach(args.buf)
		end,
	})

	vim.api.nvim_create_autocmd("BufWritePost", {
		pattern = "*",
		callback = function(args)
			M.refresh(args.buf)
		end,
	})

	vim.api.nvim_create_autocmd("FocusGained", {
		pattern = "*",
		callback = function()
			for bufnr, _ in pairs(M.attached_buffers) do
				M.refresh(bufnr)
			end
		end,
	})
end

return M

