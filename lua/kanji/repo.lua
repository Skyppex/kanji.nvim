local Job = require("plenary.job")

local M = {}

--- Resolve the configured jj timeout in milliseconds, falling back to the
--- default if config hasn't been set up yet.
--- @return number
local function get_timeout()
	local config = require("kanji.config").config
	return config.timeout or require("kanji.config").defaults.timeout
end

--- Run a jj command asynchronously with a timeout. If the command does not
--- finish within the configured timeout it is killed and `on_done(nil)` is
--- called. On success `on_done(result)` is called, on failure `on_done(nil)`.
--- @param args string[]
--- @param on_done fun(result: string[]|nil)?
local function run_async(args, on_done)
	local finished = false

	local function finish(result)
		if finished then
			return
		end
		finished = true
		if on_done then
			on_done(result)
		end
	end

	local job = Job:new({
		command = "jj",
		args = args,
		on_exit = function(j, exit_code, _)
			if exit_code ~= 0 then
				finish(nil)
				return
			end
			finish(j:result())
		end,
	})

	job:start()

	vim.defer_fn(function()
		if finished then
			return
		end
		job:shutdown()
		finish(nil)
	end, get_timeout())
end

function M.is_repo()
	local job = Job:new({
		command = "jj",
		args = { "root" },
	})
	job:sync(get_timeout())
	return job.code == 0
end

function M.get_diff(path, on_done)
	if not path then
		return
	end

	run_async({
		"diff",
		"--from",
		"@-",
		"--to",
		"@",
		"--git",
		"--",
		path,
	}, on_done)
end

function M.get_inverse_diff(path, on_done)
	if not path then
		return
	end

	run_async({
		"diff",
		"--from",
		"@",
		"--to",
		"@-",
		"--git",
		"--",
		path,
	}, on_done)
end

function M.get_blame(template, path, on_done)
	if not template or not path then
		return
	end

	run_async({
		"file",
		"annotate",
		"--template",
		template,
		path,
	}, on_done)
end

function M.restore_file(path, on_done)
	if not path then
		return
	end

	run_async({
		"restore",
		path,
	}, on_done)
end

function M.get_revset_info(change_id, on_done)
	if not change_id then
		return
	end

	local template =
		'self.change_id() ++ "|||" ++ self.author().name() ++ "|||" ++ self.author().email() ++ "|||" ++ self.author().timestamp().local().format("%Y-%m-%d %H:%M:%S") ++ "|||" ++ self.author().timestamp().ago() ++ "|||" ++ self.description()'

	run_async({
		"log",
		"--revisions",
		change_id,
		"--template",
		template,
		"--no-graph",
		"--ignore-working-copy",
	}, on_done)
end

function M.get_commit_diff(change_id, path, on_done)
	if not change_id or not path then
		return
	end

	run_async({
		"diff",
		"--from",
		change_id .. "-",
		"--to",
		change_id,
		"--git",
		"--",
		path,
	}, on_done)
end

function M.resolve_list(on_done)
	run_async({
		"resolve",
		"--list",
	}, on_done)
end

return M
