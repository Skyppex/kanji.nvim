local M = {}

--- @param hunks KanjiHunk[]
--- @param cursor_line number
--- @return KanjiGroup|nil
function M.find_group_at_line(hunks, cursor_line)
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

return M
