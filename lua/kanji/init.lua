local M = {}

M.attach = require("kanji.attach")

function M.setup(opts)
	local config = require("kanji.config").merge(opts)
	M.attach.init(config)
end

return M