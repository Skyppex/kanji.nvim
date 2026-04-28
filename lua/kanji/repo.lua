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
		args = {
			"diff",
			"--from",
			"@-",
			"--to",
			"@",
			"--git",
			"--",
			path,
		},
		on_exit = function(j, exit_code, _)
			if exit_code ~= 0 then
				return
			end
			on_done(j:result())
		end,
	}):start()
end

function M.get_inverse_diff(path, on_done)
	if not path then
		return
	end

	Job:new({
		command = "jj",
		args = {
			"diff",
			"--from",
			"@",
			"--to",
			"@-",
			"--git",
			"--",
			path,
		},
		on_exit = function(j, exit_code, _)
			if exit_code ~= 0 then
				return
			end
			on_done(j:result())
		end,
	}):start()
end

function M.get_blame(template, path, on_done)
	if not template or not path then
		return
	end

	Job:new({
		command = "jj",
		args = {
			"file",
			"annotate",
			"--template",
			template,
			path,
		},
		on_exit = function(j, exit_code, _)
			if exit_code ~= 0 then
				on_done(nil)
				return
			end
			on_done(j:result())
		end,
	}):start()
end

function M.restore_file(path, on_done)
	if not path then
		return
	end

	Job:new({
		command = "jj",
		args = {
			"restore",
			path,
		},
		on_exit = function(j, exit_code, _)
			if exit_code ~= 0 then
				on_done(nil)
				return
			end
			on_done(j:result())
		end,
	}):start()
end

function M.get_revset_info(change_id, on_done)
	if not change_id then
		return
	end

	local template =
		'self.change_id() ++ "|||" ++ self.author().name() ++ "|||" ++ self.author().email() ++ "|||" ++ self.author().timestamp().local().format("%Y-%m-%d %H:%M:%S") ++ "|||" ++ self.author().timestamp().ago() ++ "|||" ++ self.description()'

	Job:new({
		command = "jj",
		args = {
			"log",
			"--revisions",
			change_id,
			"--template",
			template,
			"--no-graph",
			"--ignore-working-copy",
		},
		on_exit = function(j, exit_code, _)
			if exit_code ~= 0 then
				on_done(nil)
				return
			end
			on_done(j:result())
		end,
	}):start()
end

function M.get_commit_diff(change_id, path, on_done)
	if not change_id or not path then
		return
	end

	Job:new({
		command = "jj",
		args = {
			"diff",
			"--from",
			change_id .. "-",
			"--to",
			change_id,
			"--git",
			"--",
			path,
		},
		on_exit = function(j, exit_code, _)
			if exit_code ~= 0 then
				on_done(nil)
				return
			end
			on_done(j:result())
		end,
	}):start()
end

return M
