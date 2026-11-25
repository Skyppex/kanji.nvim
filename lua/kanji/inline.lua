-- Renders hunk diffs inline in the buffer: added lines highlighted in place,
-- removed (original) lines shown as red, syntax-highlighted virtual lines
-- above the change. This mirrors tandem.nvim's review-mode inline diff.
--
-- The buffer on disk is already the "new" version of the file (the `@` side of
-- the jj diff), so added lines are real buffer text and only need a highlight,
-- while removed lines don't exist in the buffer and are drawn as virtual lines.

local M = {}

M.ns = vim.api.nvim_create_namespace("kanji.inline")

--- Whether inline hunks are turned on (globally, for every buffer).
--- @type boolean
local enabled = false

--- Defaults link to the diff groups; users override by defining the groups
--- themselves.
local function set_default_highlights()
	-- Added lines: green, like a diff's added side.
	vim.api.nvim_set_hl(0, "KanjiInlineAdd", { default = true, link = "DiffAdd" })
	vim.api.nvim_set_hl(0, "KanjiInlineRemoved", { default = true, link = "DiffDelete" })
	-- Background only, so a syntax highlight layered under it keeps its
	-- foreground (the removed lines are syntax-highlighted code). Derived from
	-- DiffDelete's bg; a plain link could drag a foreground along.
	local del = vim.api.nvim_get_hl(0, { name = "DiffDelete", link = false })
	if del.bg then
		vim.api.nvim_set_hl(0, "KanjiInlineRemovedBg", { default = true, bg = del.bg })
	else
		vim.api.nvim_set_hl(0, "KanjiInlineRemovedBg", { default = true, link = "DiffDelete" })
	end
end

set_default_highlights()
vim.api.nvim_create_autocmd("ColorScheme", {
	group = vim.api.nvim_create_augroup("kanji.inline", { clear = true }),
	callback = set_default_highlights,
})

--- Where to anchor virtual lines for a hunk at 0-based `row`: on the row
--- itself (above it) normally, or on the last line (below it) when the hunk
--- sits past the end of the buffer.
--- @param buf integer
--- @param row integer
--- @return integer row, boolean above
local function anchor(buf, row)
	local count = vim.api.nvim_buf_line_count(buf)
	if row >= count then
		return count - 1, false
	end
	return row, true
end

--- Display width of the nearest non-empty line above and below `row`,
--- whichever is wider.
--- @param buf integer
--- @param row integer
--- @return integer
local function neighbour_width(buf, row)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local width = 0
	for _, dir in ipairs({ -1, 1 }) do
		local i = row + 1 + dir
		while lines[i] and lines[i] == "" do
			i = i + dir
		end
		if lines[i] then
			width = math.max(
				width,
				vim.api.nvim_buf_call(buf, function()
					return vim.fn.strdisplaywidth(lines[i])
				end)
			)
		end
	end
	return width
end

--- Highlight an added line's text only; an empty line gets a pad as wide as
--- the code around it, so it's visible without spanning the window.
--- @param buf integer
--- @param row integer 0-based
local function highlight_line(buf, row)
	local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
	if line == nil then
		return
	end
	if line ~= "" then
		vim.api.nvim_buf_set_extmark(buf, M.ns, row, 0, {
			end_col = #line,
			hl_group = "KanjiInlineAdd",
			priority = 50,
		})
	else
		vim.api.nvim_buf_set_extmark(buf, M.ns, row, 0, {
			virt_text = { { string.rep(" ", math.max(neighbour_width(buf, row), 1)), "KanjiInlineAdd" } },
			virt_text_pos = "overlay",
			priority = 50,
		})
	end
end

--- Virtual lines that scroll horizontally with the text where supported.
--- @param buf integer
--- @param row integer 0-based
--- @param virt table[]
--- @param above boolean
local function virt_lines(buf, row, virt, above)
	local opts = { virt_lines = virt, virt_lines_above = above, virt_lines_overflow = "scroll" }
	if not pcall(vim.api.nvim_buf_set_extmark, buf, M.ns, row, 0, opts) then
		opts.virt_lines_overflow = nil
		vim.api.nvim_buf_set_extmark(buf, M.ns, row, 0, opts)
	end
end

--- Treesitter highlight group names per byte for `lines`. Returns
--- `marks[row0][bytecol0] = capture_name` and the language, or nil when there's
--- no parser for the filetype. `lines` is the whole file, so a removed line is
--- highlighted with its real surroundings (a table field reads as a field, not
--- a top-level statement).
--- @param buf integer The source file buffer (for its filetype).
--- @param lines string[]
--- @return table<integer, table<integer, string>>? marks, string? lang
local function syntax_marks(buf, lines)
	local ft = vim.bo[buf].filetype
	if ft == "" then
		return nil
	end
	local ok, lang = pcall(vim.treesitter.language.get_lang, ft)
	lang = ok and lang or nil
	if not lang or not pcall(vim.treesitter.language.add, lang) then
		return nil
	end
	local src = table.concat(lines, "\n")
	local parser
	ok, parser = pcall(vim.treesitter.get_string_parser, src, lang)
	if not ok or not parser then
		return nil
	end
	local trees = parser:parse()
	local query = vim.treesitter.query.get(lang, "highlights")
	if not trees or not trees[1] or not query then
		return nil
	end
	local marks = {}
	for id, node in query:iter_captures(trees[1]:root(), src, 0, #lines) do
		local name = query.captures[id]
		-- `_`-prefixed captures are internal and not meant to be highlighted.
		if not name:find("^_") then
			local srow, scol, erow, ecol = node:range()
			for r = srow, erow do
				local line = lines[r + 1] or ""
				local cs = r == srow and scol or 0
				local ce = r == erow and ecol or #line
				local m = marks[r]
				if not m then
					m = {}
					marks[r] = m
				end
				for c = cs, ce - 1 do
					m[c] = name
				end
			end
		end
	end
	return marks, lang
end

--- `syntax_marks` for the reconstructed original, cached per buffer so renders
--- that don't change the original (cursor moves, etc.) don't reparse.
--- @type table<integer, { key: string, marks: table?, lang: string? }>
local marks_cache = {}

--- @param buf integer
--- @param lines string[] The reconstructed original.
--- @return table? marks, string? lang
local function original_marks(buf, lines)
	local key = table.concat(lines, "\n")
	local c = marks_cache[buf]
	if c and c.key == key then
		return c.marks, c.lang
	end
	local marks, lang = syntax_marks(buf, lines)
	marks_cache[buf] = { key = key, marks = marks, lang = lang }
	return marks, lang
end

--- The buffer's text with every change reverted to its original (`old`) lines:
--- the file as it was before the edits, so the removed lines sit in their real
--- context for highlighting. Also returns the 0-based row where each group's
--- original lines begin in it, keyed by the group table.
--- @param buf integer
--- @param groups table[]
--- @return string[] lines, table<table, integer> starts
local function original_lines(buf, groups)
	local cur = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local ordered = {}
	for _, g in ipairs(groups) do
		ordered[#ordered + 1] = g
	end
	table.sort(ordered, function(a, b)
		return a.start_row0 < b.start_row0
	end)
	local out, starts, pos = {}, {}, 0
	for _, g in ipairs(ordered) do
		for r = pos, g.start_row0 - 1 do
			out[#out + 1] = cur[r + 1]
		end
		starts[g] = #out
		for _, line in ipairs(g.old) do
			out[#out + 1] = line
		end
		pos = math.max(pos, g.start_row0 + g.new_count)
	end
	for r = pos, #cur - 1 do
		out[#out + 1] = cur[r + 1]
	end
	return out, starts
end

--- Removed (original) `lines` as red virtual lines: the code syntax-highlighted
--- as it would be in `buf`, over a red background (`KanjiInlineRemovedBg`), the
--- red reaching only to the text width like the green of the added lines.
--- `marks`/`lang` come from parsing the whole original; `start_row` is where
--- these lines begin in it. Falls back to red-only when there's no parser
--- (`marks` nil).
--- @param buf integer
--- @param lines string[]
--- @param marks table?
--- @param lang string?
--- @param start_row integer
--- @return table[] virt_lines
local function removed_block(buf, lines, marks, lang, start_row)
	local ts = vim.bo[buf].tabstop
	local out = {}
	for i, line in ipairs(lines) do
		local m = marks and marks[start_row + i - 1]
		local chunks, col = {}, 0
		local function emit(text, name)
			local expanded = {}
			for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
				if ch == "\t" then
					local n = ts - col % ts
					table.insert(expanded, string.rep(" ", n))
					col = col + n
				else
					table.insert(expanded, ch)
					col = col + vim.fn.strdisplaywidth(ch)
				end
			end
			local hl = name and { "@" .. name, "@" .. name .. "." .. lang, "KanjiInlineRemovedBg" }
				or { "KanjiInlineRemovedBg" }
			table.insert(chunks, { table.concat(expanded), hl })
		end
		if #line == 0 then
			-- An empty removed line still needs a sliver of red to be visible.
			chunks = { { " ", { "KanjiInlineRemovedBg" } } }
		else
			local b, n = 0, #line
			while b < n do
				local name = m and m[b]
				local e = b + 1
				while e < n and (m and m[e]) == name do
					e = e + 1
				end
				emit(line:sub(b + 1, e), name)
				b = e
			end
		end
		out[i] = chunks
	end
	return out
end

--- Flatten the parsed hunks into render groups. Each group carries its added
--- line rows, its removed (`old`) text, and where its new content begins in the
--- buffer so the original can be reconstructed.
--- @param hunks KanjiHunk[]
--- @return table[]
local function build_groups(hunks)
	local groups = {}
	for _, hunk in ipairs(hunks) do
		for _, group in ipairs(hunk.groups) do
			--- @type integer[]
			local adds = {}
			--- @type string[]
			local old = {}
			local anchor_line
			for _, l in ipairs(group.lines) do
				if l.type == "add" then
					adds[#adds + 1] = l.line - 1
				elseif l.type == "delete" then
					old[#old + 1] = l.text
					anchor_line = anchor_line or l.line
				end
			end

			local start_row0, new_count
			if #adds > 0 then
				start_row0 = adds[1]
				new_count = #adds
			else
				-- Pure deletion: anchor above the line that now sits where the
				-- removed lines used to be.
				start_row0 = (anchor_line or 1) - 1
				new_count = 0
			end

			groups[#groups + 1] = {
				adds = adds,
				old = old,
				start_row0 = start_row0,
				new_count = new_count,
			}
		end
	end
	return groups
end

--- Draw the inline diff for `buf` from a raw git-format diff. No-op unless
--- inline hunks are enabled for the buffer.
--- @param buf integer
--- @param diff_output string[]|nil
function M.render(buf, diff_output)
	if not enabled then
		return
	end
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)

	local hunks = require("kanji.diff").parse(diff_output)
	if #hunks == 0 then
		return
	end

	local groups = build_groups(hunks)

	-- Parse the file as it was before the edits once, so each removed block is
	-- highlighted in its real context.
	local original, starts = original_lines(buf, groups)
	local marks, lang = original_marks(buf, original)

	for _, g in ipairs(groups) do
		for _, row in ipairs(g.adds) do
			highlight_line(buf, row)
		end
		if #g.old > 0 then
			local row, above = anchor(buf, g.start_row0)
			virt_lines(buf, row, removed_block(buf, g.old, marks, lang, starts[g]), above)
		end
	end
end

--- @return boolean
function M.is_enabled()
	return enabled
end

--- Turn inline hunks off everywhere and clear what's drawn.
function M.disable()
	enabled = false
	marks_cache = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
		end
	end
end

--- Turn inline hunks on everywhere and draw them immediately.
function M.enable()
	enabled = true
	-- attach.refresh fetches the diff and renders signs + inline hunks.
	local attach = require("kanji.attach")

	local seen = {}
	-- Draw the buffers the user is actually looking at right now, attaching
	-- any that startup opened before kanji.setup() ran (those never got the
	-- BufReadPost that adds them to attached_buffers).
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		if not seen[buf] then
			seen[buf] = true
			attach.attach(buf)
			attach.refresh(buf)
		end
	end
	-- Plus anything else already tracked (open but not in a window).
	for buf, _ in pairs(attach.attached_buffers) do
		if not seen[buf] then
			attach.refresh(buf)
		end
	end
end

--- Toggle inline hunks globally.
function M.toggle()
	if enabled then
		M.disable()
	else
		M.enable()
	end
end

return M
