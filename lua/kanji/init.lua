local M = {}

M.attach = require("kanji.attach")

--- @param opts KanjiOpts
function M.setup(opts)
	local config = require("kanji.config").merge(opts)
	M.attach.init(config)
end

return M
