-- Unit tests for the pure-Lua parts of the Spoon (parser.lua, matcher.lua).
-- Run from anywhere with plain Lua 5.4+, no Hammerspoon needed:
--   lua SemiExpand.spoon/tests/run.lua
local here = (arg and arg[0] or ""):match("^(.*)/[^/]*$") or "."
local spoonDir = here .. "/.."

local parser = dofile(spoonDir .. "/parser.lua")
local matcher = dofile(spoonDir .. "/matcher.lua")

------------------------------------------------------------------------------------------
-- A minimal test runner

local passed, failed = 0, {}

local function show(v)
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end

local function eq(actual, expected, what)
	if actual ~= expected then
		error(string.format("%s: expected %s, got %s", what or "value", show(expected), show(actual)), 2)
	end
end

-- Same keys and values (one level deep)
local function sameTable(actual, expected, what)
	for k, v in pairs(expected) do
		if actual[k] ~= v then
			error(string.format("%s[%s]: expected %s, got %s", what or "table", show(k), show(v), show(actual[k])), 2)
		end
	end
	for k, v in pairs(actual) do
		if expected[k] == nil then
			error(string.format("%s[%s]: unexpected %s", what or "table", show(k), show(v)), 2)
		end
	end
end

local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed = passed + 1
	else
		failed[#failed + 1] = name .. "\n    " .. tostring(err)
	end
end

-- An iterator over lines, like file:lines()
local function lines(...)
	local list, i = { ... }, 0
	return function()
		i = i + 1
		return list[i]
	end
end

------------------------------------------------------------------------------------------
-- parser

test("parser: an entry gets the prefix", function()
	local e = parser.parseLines(lines('done "✅"'), ";")
	sameTable(e, { [";done"] = "✅" }, "expansions")
end)

test("parser: several names share the text", function()
	local e = parser.parseLines(lines('pi pii p8 "π"'), ";")
	sameTable(e, { [";pi"] = "π", [";pii"] = "π", [";p8"] = "π" }, "expansions")
end)

test("parser: a longer prefix", function()
	local e = parser.parseLines(lines('m1 "me@example.com"'), ";;")
	sameTable(e, { [";;m1"] = "me@example.com" }, "expansions")
end)

test("parser: names may contain symbols", function()
	local e = parser.parseLines(lines('-> "→"', '-- "—"', 'a* "α"', 'o: "ö"', "o' \"ó\"", '... "…"'), ";")
	sameTable(e, {
		[";->"] = "→",
		[";--"] = "—",
		[";a*"] = "α",
		[";o:"] = "ö",
		[";o'"] = "ó",
		[";..."] = "…",
	}, "expansions")
end)

test("parser: extra spaces and indentation are fine", function()
	local e = parser.parseLines(lines('   up    arrow   "⬆️"   '), ";")
	sameTable(e, { [";up"] = "⬆️", [";arrow"] = "⬆️" }, "expansions")
end)

test("parser: escapes in the text", function()
	local e = parser.parseLines(lines([[sig "Best,\nMe"]], [[tab "a\tb"]], [[q "say \"hi\""]], [[bs "a\\b"]]), ";")
	eq(e[";sig"], "Best,\nMe", ";sig")
	eq(e[";tab"], "a\tb", ";tab")
	eq(e[";q"], 'say "hi"', ";q")
	eq(e[";bs"], "a\\b", ";bs")
end)

test("parser: an empty text is allowed", function()
	local e = parser.parseLines(lines('nothing ""'), ";")
	eq(e[";nothing"], "", ";nothing")
end)

test("parser: sections, cut at ( or :", function()
	local _, s = parser.parseLines(lines(
		'before "0"',
		"# Faces",
		'smile "😊"',
		"## Accented letters: ;<letter><mark>",
		'o: "ö"',
		"# Greek letters (Vim digraphs)",
		'a* "α"'
	), ";")
	eq(s[";before"], "", "no section yet")
	eq(s[";smile"], "Faces", ";smile")
	eq(s[";o:"], "Accented letters", ";o:")
	eq(s[";a*"], "Greek letters", ";a*")
end)

test("parser: comments, blank and malformed lines are skipped", function()
	local e = parser.parseLines(lines(
		"// a comment",
		'  // done "✅"',
		"",
		"   ",
		"noquotes text",
		'"only text"',
		'ok "fine"'
	), ";")
	sameTable(e, { [";ok"] = "fine" }, "expansions")
end)

test("parser: a later entry replaces an earlier one", function()
	local e = parser.parseLines(lines('x "1"', 'x "2"'), ";")
	eq(e[";x"], "2", ";x")
end)

test("parser: a missing file gives nil", function()
	eq(parser.parseFile("/nonexistent/expansions.md", ";"), nil, "parseFile")
end)

test("parser: parseFile reads a real file", function()
	local dir = (os.getenv("TMPDIR") or "/tmp"):gsub("/$", "")
	local path = string.format("%s/expansions-test-%d-%d.md", dir, os.time(), math.random(1e9))
	local f = assert(io.open(path, "w"))
	f:write('# S\nk "v"\n')
	f:close()
	local e, s = parser.parseFile(path, ";")
	os.remove(path)
	eq(e[";k"], "v", ";k")
	eq(s[";k"], "S", "section")
end)

------------------------------------------------------------------------------------------
-- matcher.findUnique

test("findUnique: a start shared by several is false", function()
	local u = matcher.findUnique({ [";pi"] = "π", [";pig"] = "🐖", [";pin"] = "📌" })
	eq(u[";p"], false, ";p")
	eq(u[";pi"], false, ";pi (also starts ;pig, ;pin)")
	eq(u[";pig"], ";pig", ";pig")
	eq(u[";pin"], ";pin", ";pin")
end)

test("findUnique: a start of only one abbreviation points to it", function()
	local u = matcher.findUnique({ [";keyboard"] = "⌨️", [";key"] = "🔑" })
	eq(u[";ke"], false, ";ke")
	eq(u[";key"], false, ";key")
	eq(u[";keyb"], ";keyboard", ";keyb")
	eq(u[";keyboard"], ";keyboard", ";keyboard")
	eq(u[";x"], nil, "no abbreviation")
end)

------------------------------------------------------------------------------------------
-- matcher.currentWord

local function word(buffer, needChars, maxPrefix)
	return matcher.currentWord(buffer, ";", maxPrefix or 2, needChars)
end

test("currentWord: the word after the trigger", function()
	eq(word("hello ;do"), ";do", "after text")
	eq(word(";do"), ";do", "whole buffer")
	eq(word("x ;"), ";", "bare trigger")
end)

test("currentWord: needChars wants something after the trigger", function()
	eq(word("x ;", true), nil, "bare trigger")
	eq(word("x ;d", true), ";d", "one character")
end)

test("currentWord: a space ends the word", function()
	eq(word(";do it"), nil, "space after")
	eq(word("plain text"), nil, "no trigger")
end)

test("currentWord: starts at the last trigger", function()
	eq(word("a;b;done"), ";done", "earlier trigger")
	eq(word("foo();\238\156\129;han"), ";han", "stale trigger with a hidden character")
end)

test("currentWord: a doubled trigger for a longer prefix", function()
	eq(word("x ;;m1"), ";;m1", "maxPrefix 2")
	eq(word("x ;;m1", false, 1), ";m1", "maxPrefix 1")
	eq(word("x ;;;m1"), ";;m1", "never longer than maxPrefix")
	eq(word("foo();;m2"), ";;m2", "after code")
end)

test("currentWord: another trigger character", function()
	eq(matcher.currentWord("x ,smile", ",", 1, false), ",smile", "comma")
	eq(matcher.currentWord("x .dot", ".", 1, false), ".dot", "pattern-special character")
end)

------------------------------------------------------------------------------------------
-- matcher.setFor

test("setFor: longest matching prefix wins", function()
	local personal, main = { prefix = ";;" }, { prefix = ";" }
	local sets = { personal, main } -- longest prefix first
	eq(matcher.setFor(sets, ";;m1"), personal, ";;m1")
	eq(matcher.setFor(sets, ";;"), personal, ";;")
	eq(matcher.setFor(sets, ";pi"), main, ";pi")
	eq(matcher.setFor(sets, ";"), main, ";")
	eq(matcher.setFor({ personal }, ";pi"), nil, "no matching set")
end)

------------------------------------------------------------------------------------------
-- matcher.rank and matcher.rowRank

test("rank: exact, prefix, contains, section, none", function()
	eq(matcher.rank(";pi", ";pi", "pi", "Greek"), 0, "exact")
	eq(matcher.rank(";pin", ";pi", "pi", "Office"), 1, "starts with")
	eq(matcher.rank(";spider", ";pi", "pi", "Animals"), 2, "contains")
	eq(matcher.rank(";clap", ";han", "han", "Hands & gestures"), 3, "section contains")
	eq(matcher.rank(";done", ";han", "han", "Status"), 4, "no match")
	eq(matcher.rank(";done", ";han", "han", nil), 4, "no section")
end)

test("rank: contains ignores case, starts with doesn't", function()
	eq(matcher.rank(";DE", ";de", "de", "Flags"), 2, ";de vs ;DE")
end)

test("rowRank: by name, then text or section", function()
	local row = { name = "handshake", preview = "🤝", section = "Hands & gestures" }
	eq(matcher.rowRank(row, "handshake"), 0, "name is the query")
	eq(matcher.rowRank(row, "hand"), 1, "name starts with it")
	eq(matcher.rowRank(row, "shake"), 2, "name contains it")
	eq(matcher.rowRank(row, "gestures"), 3, "section contains it")
	eq(matcher.rowRank({ name = "m1", preview = "me@example.com", section = "" }, "example"), 3, "text contains it")
	eq(matcher.rowRank(row, "zzz"), nil, "left out")
	eq(matcher.rowRank(row, ""), 1, "empty query lists everything")
end)

------------------------------------------------------------------------------------------

for _, failure in ipairs(failed) do
	print("FAIL " .. failure)
end
print(string.format("%d passed, %d failed", passed, #failed))
os.exit(#failed == 0 and 0 or 1)
