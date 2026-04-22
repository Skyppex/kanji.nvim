local M = {}

function M.parse(diff_output)
	if not diff_output or #diff_output == 0 then
		return {}
	end

	local hunks = {}
	local line_in_file = 1

	for _, line in ipairs(diff_output) do
		local old_start, new_start = line:match("^@@ %-(%d+),?%d* %+(%d+),?%d* @@$")
		if old_start then
			table.insert(hunks, {
				new_start = tonumber(new_start),
				lines = {},
			})
			line_in_file = tonumber(new_start, 10)
		elseif hunks[#hunks] then
			local first = line:sub(1, 1)
			if first == "+" then
				table.insert(hunks[#hunks].lines, {
					type = "add",
					text = line:sub(2),
					line = line_in_file,
				})
				line_in_file = line_in_file + 1
			elseif first == "-" then
				table.insert(hunks[#hunks].lines, {
					type = "delete",
					text = line:sub(2),
					line = line_in_file,
				})
			elseif first == " " then
				table.insert(hunks[#hunks].lines, {
					type = "context",
					text = line:sub(2),
					line = line_in_file,
				})
				line_in_file = line_in_file + 1
			end
		end
	end

	return hunks
end

function M.get_signs(diff_output)
	local hunks = M.parse(diff_output)
	local signs = {}

	for _, hunk in ipairs(hunks) do
		local seen = {}
		for _, line in ipairs(hunk.lines) do
			if line.type == "add" or line.type == "delete" then
				if seen[line.line] then
					seen[line.line].type = "change"
				else
					seen[line.line] = {
						line = line.line,
						type = line.type,
					}
					table.insert(signs, seen[line.line])
				end
			end
		end
	end

	return signs
end

return M
