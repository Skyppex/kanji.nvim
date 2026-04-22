local Job = require("plenary.job")

local M = {}

function M.is_repo()
	local job = Job:new({
		command = "jj",
		args = { "root" },
	})
	job:sync()
	return job.code == 0
end

function M.get_diff(path, on_done)
	if not path then
		return
	end

	Job:new({
		command = "jj",
		args = { "diff", "--git", "--", path },
		on_exit = function(j, exit_code, _)
			if exit_code ~= 0 then
				return
			end
			on_done(j:result())
		end,
	}):start()
end

return M
