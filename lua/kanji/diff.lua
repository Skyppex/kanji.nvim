local M = {}

local function calc_group_type(group)
	local has_add = false
	local has_delete = false
	for _, l in ipairs(group) do
		if l.type == "add" then
			has_add = true
		elseif l.type == "delete" then
			has_delete = true
		end
	end
	if has_add and has_delete then
		return "change"
	end
	if has_add then
		return "add"
	end
	return "delete"
end

--- @class KanjiHunk
--- @field old_start number
--- @field new_start number
--- @field groups KanjiGroup[]
--- @field current_group KanjiGroup
---
--- @class KanjiGroup
--- @field lines KanjiLine[]
--- @field type "add"|"change"|"delete"
---
--- @class KanjiLine
--- @field line number
--- @field text string
--- @field type "add"|"change"|"delete"
---
--- @return KanjiHunk[]
function M.parse(diff_output)
	if not diff_output or #diff_output == 0 then
		return {}
	end

	--- @type KanjiHunk[]
	local hunks = {}
	local line_in_file = 1

	for _, line in ipairs(diff_output) do
		local old_start, new_start = line:match("^@@ %-(%d+),?%d* %+(%d+),?%d* @@$")
		if old_start then
			table.insert(hunks, {
				old_start = tonumber(old_start),
				new_start = tonumber(new_start),
				groups = {},
				current_group = {},
			})
			line_in_file = tonumber(new_start, 10)
		elseif hunks[#hunks] then
			local first = line:sub(1, 1)

			local hunk = hunks[#hunks]

			if first == "+" then
				table.insert(hunk.current_group, {
					type = "add",
					text = line:sub(2),
					line = line_in_file,
				})
				line_in_file = line_in_file + 1
			elseif first == "-" then
				table.insert(hunk.current_group, {
					type = "delete",
					text = line:sub(2),
					line = line_in_file,
				})
			elseif first == " " then
				if #hunk.current_group > 0 then
					local group_type = calc_group_type(hunk.current_group)
					local group_lines = {}
					for _, l in ipairs(hunk.current_group) do
						table.insert(group_lines, {
							line = l.line,
							text = l.text,
							type = l.type,
						})
					end
					table.insert(hunk.groups, {
						type = group_type,
						lines = group_lines,
					})
					hunk.current_group = {}
				end
				line_in_file = line_in_file + 1
			end
		end
	end

	-- save final group in each hunk
	for _, hunk in ipairs(hunks) do
		if #hunk.current_group > 0 then
			local group_type = calc_group_type(hunk.current_group)
			local group_lines = {}
			for _, l in ipairs(hunk.current_group) do
				table.insert(group_lines, {
					line = l.line,
					text = l.text,
					type = l.type,
				})
			end
			table.insert(hunk.groups, {
				type = group_type,
				lines = group_lines,
			})
		end
		hunk.current_group = nil
	end

	return hunks
end

--- @param group KanjiGroup
--- @return string[]
function M.format_group_content(group)
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

return M
