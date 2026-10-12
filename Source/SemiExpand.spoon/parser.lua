-- The expansions file format (pure Lua, no hs.* calls):
--   name [name…] "text"   names share the text; written without the prefix, which the
--                         caller passes in (e.g. ";" → pi becomes ;pi)
--   # Section             starts a section (its name is cut at "(" or ":")
--   // comment            ignored, as are blank lines and anything else
-- In the text, \n is a newline, \t a tab, \" a quote and \\ a backslash.
local M = {}

local UNESCAPE = { n = "\n", t = "\t", ['"'] = '"', ["\\"] = "\\" }

-- Parse lines (an iterator of strings) into abbr → text and abbr → section
function M.parseLines(lines, prefix)
	local expansions, sections = {}, {}
	local section = ""
	for line in lines do
		if line:match("^%s*#") then
			section = (line:gsub("^%s*#+%s*", ""):gsub("%s*[(:].*$", ""))
		elseif not line:match("^%s*//") then
			local names, text = line:match('^%s*([^"]-)%s+"(.*)"%s*$')
			if names and names ~= "" then
				text = text:gsub("\\(.)", UNESCAPE)
				for name in names:gmatch("%S+") do
					expansions[prefix .. name] = text
					sections[prefix .. name] = section
				end
			end
		end
	end
	return expansions, sections
end

-- Parse a file; nil if it can't be read
function M.parseFile(path, prefix)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local expansions, sections = M.parseLines(f:lines(), prefix)
	f:close()
	return expansions, sections
end

return M
