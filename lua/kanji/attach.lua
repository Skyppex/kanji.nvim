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
			M.refresh(bufnr)
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
			local buffers = vim.api.nvim_list_bufs()

			for attached_bufnr, _ in pairs(M.attached_buffers) do
				for _, bufnr in ipairs(buffers) do
					if attached_bufnr == bufnr then
						goto continue
					end
				end

				M.attached_buffers[attached_bufnr] = nil

				::continue::
			end

			for bufnr, _ in pairs(M.attached_buffers) do
				M.refresh(bufnr)
			end
		end,
	})
end

return M
