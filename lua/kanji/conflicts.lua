local repo = require("kanji.repo")
local Path = require("plenary.path")

local M = {}

--- @class KanjiConflict
--- @field path string
--- @field index integer
--- @field total integer
--- @field start_line integer
--- @field end_line integer
--- @field snapshot KanjiConflictSnapshot
--- @field patches KanjiConflictPatch[]
---
--- @class KanjiConflictSnapshot
--- @field start_line integer
--- @field end_line integer
--- @field change_id string
--- @field commit_id string
--- @field content_lines string[]
---
--- @class KanjiConflictPatch
--- @field start_line integer
--- @field end_line integer
--- @field change_id_from string
--- @field commit_id_from string
--- @field change_id_to string
--- @field commit_id_to string
--- @field content_lines string[]

--- @param conflict_lines string[]
--- @param offset integer
--- @param marker_length integer
--- @return KanjiConflictSnapshot, KanjiConflictPatch[]
local function parse_conflict(conflict_lines, offset, marker_length)
	--- @type KanjiConflictSnapshot
	local snapshot = {}

	--- @type KanjiConflictPatch[]
	local patches = {}

	local i = 1
	while i < #conflict_lines do
		local line = conflict_lines[i]

		local from_marker, change_id_from, commit_id_from = line:match("^(%%%%%%%%%%%%%%+) diff from: (%w+) (%w+)")
		local snapshot_marker, change_id_snapshot, commit_id_snapshot = line:match("^(%+%+%+%+%+%+%++) (%w+) (%w+)")

		if from_marker and #from_marker == marker_length then
			--- @type KanjiConflictPatch
			local patch = {
				change_id_from = change_id_from,
				commit_id_from = commit_id_from,
				start_line = i + offset,
			}

			i = i + 1
			line = conflict_lines[i]

			local to_marker, change_id_to, commit_id_to = line:match("^(\\\\\\\\\\\\\\+)        to: (%w+) (%w+)")

			if to_marker and #to_marker == marker_length then
				patch.change_id_to = change_id_to
				patch.commit_id_to = commit_id_to
			end

			i = i + 1

			local patch_lines = {}
			while true do
				if i > #conflict_lines then
					break
				end

				line = conflict_lines[i]
				local is_patch_start = line:match("^%%%%%%%%%%%%%%+ %w+ %w+")
				local is_snapshot_start = line:match("^%+%+%+%+%+%+%++ %w+ %w+")
				local is_end = line:match("^>>>>>>>+ conflict %d+ of %d+ ends")

				if is_patch_start or is_snapshot_start or is_end then
					break
				end

				table.insert(patch_lines, line)
				i = i + 1
			end

			patch.end_line = i + offset
			patch.content_lines = patch_lines
			table.insert(patches, patch)
		elseif snapshot_marker and #snapshot_marker == marker_length then
			snapshot.start_line = i + offset
			snapshot.change_id = change_id_snapshot
			snapshot.commit_id = commit_id_snapshot

			i = i + 1

			local snapshot_lines = {}

			while true do
				if i > #conflict_lines then
					break
				end

				line = conflict_lines[i]
				local patch_marker = line:match("^(%%%%%%%%%%%%%%+) %w+ %w+")
				local snapshot_marker = line:match("^(%+%+%+%+%+%+%++) %w+ %w+")
				local end_marker = line:match("^(>>>>>>>+) conflict %d+ of %d+ ends")

				if
					(patch_marker and #patch_marker == marker_length)
					or (snapshot_marker and #snapshot_marker == marker_length)
					or (end_marker and #end_marker == marker_length)
				then
					break
				end

				table.insert(snapshot_lines, line)
				i = i + 1
			end

			snapshot.end_line = i + offset
			snapshot.content_lines = snapshot_lines
		end
	end

	return snapshot, patches
end

--- @return KanjiConflict[]
local function parse_file_conflicts(path)
	local p = Path:new(path)

	if not p:exists() then
		return {}
	end

	--- @type string[]
	local lines = p:readlines()

	--- @type KanjiConflict[]
	local conflicts = {}

	local i = 1

	while i <= #lines do
		local line = lines[i]

		local start_marker, current, total = line:match("^(<<<<<<<+) conflict (%d+) of (%d+)")

		if start_marker then
			--- @type string[]
			local conflict_lines = {}
			local marker_length = #start_marker
			local start_line = i
			i = i + 1

			local current_line = lines[i]

			local end_marker, _end = current_line:match("^(>>>>>>>+) conflict (%d+) of %d+ ends")

			while not end_marker or #end_marker ~= marker_length do
				table.insert(conflict_lines, current_line)
				i = i + 1
				current_line = lines[i]
				end_marker, _end = current_line:match("^(>>>>>>>+) conflict (%d+) of %d+ ends")
			end

			if current ~= _end then
				vim.notify("conflict start index doesn't match end index", vim.log.levels.ERROR)
				return {}
			end

			local snapshot, patches = parse_conflict(conflict_lines, start_line, marker_length)

			--- @type KanjiConflict
			local conflict = {
				path = path,
				total = total,
				index = current,
				start_line = start_line,
				end_line = i,
				snapshot = snapshot,
				patches = patches,
			}

			table.insert(conflicts, conflict)
		end

		i = i + 1
	end

	return conflicts
end

--- @param on_done fun(conflicts: KanjiConflict[])
local function get_all_conflicts(on_done)
	repo.resolve_list(function(result)
		if not result or #result == 0 then
			if on_done then
				on_done({})
			end

			return
		end

		local files = {}
		for _, line in ipairs(result) do
			local path = line:match("^(.-)%s%s%s%s")
			if path then
				table.insert(files, path)
			end
		end

		--- @type KanjiConflict[]
		local all_conflicts = {}
		for _, file_path in ipairs(files) do
			local conflicts = parse_file_conflicts(file_path)

			for _, c in ipairs(conflicts) do
				c.path = file_path
				table.insert(all_conflicts, c)
			end
		end

		if on_done then
			on_done(all_conflicts)
		end
	end)
end

function M.conflicts(on_done)
	get_all_conflicts(on_done)
end

function M.conflicts_to_qf()
	get_all_conflicts(function(conflicts)
		local qf_items = {}
		for _, c in ipairs(conflicts) do
			table.insert(qf_items, {
				filename = c.path,
				lnum = c.start_line,
				end_lnum = c.end_line,
				col = 1,
				text = string.format("Conflict in %s (%d lines)", c.path, c.end_line - c.start_line + 1),
			})
		end

		if #qf_items > 0 then
			vim.schedule(function()
				vim.notify(vim.inspect(qf_items))
				vim.fn.setqflist(qf_items, "r")
				vim.cmd("copen")
			end)
		end
	end)
end

return M
