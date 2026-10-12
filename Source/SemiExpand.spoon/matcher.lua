-- Matching abbreviations against what is being typed (pure Lua, no hs.* calls)
local M = {}

-- For every start of an abbreviation (";k", ";ke", ";key", …): the one abbreviation that
-- starts with it, or false if several do. Typing a start with a single candidate expands it
-- (;keyb → ;keyboard); one shared by several (;pi: ;pig ;pin …) waits for the picker key.
function M.findUnique(abbrs)
	local unique = {}
	for abbr in pairs(abbrs) do
		for len = 2, #abbr do
			local start = abbr:sub(1, len)
			if unique[start] == nil then
				unique[start] = abbr
			elseif unique[start] ~= abbr then
				unique[start] = false
			end
		end
	end
	return unique
end

-- The abbreviation being typed at the end of `buffer`: the trigger character plus what
-- follows it (at least one character if `needChars`), e.g. ";word". It starts at the last
-- trigger (plus up to maxPrefix - 1 more right before it, so ";;word" for a ";;" set), so a
-- stale trigger from earlier typing can't get glued on. nil if there is none.
function M.currentWord(buffer, trigger, maxPrefix, needChars)
	local t = "%" .. trigger
	local word = buffer:match(t .. "[^%s" .. t .. "]" .. (needChars and "+" or "*") .. "$")
	if word then
		local prefixLength = 1
		while prefixLength < maxPrefix and buffer:sub(-#word - 1, -#word - 1) == trigger do
			word = trigger .. word
			prefixLength = prefixLength + 1
		end
	end
	return word
end

-- The set a word belongs to: the one with the longest prefix the word starts with
-- (sets are sorted longest prefix first), e.g. ";;m1" → the ";;" set, ";pi" → the ";" set
function M.setFor(sets, word)
	for _, set in ipairs(sets) do
		if word:sub(1, #set.prefix) == set.prefix then
			return set
		end
	end
end

-- Rank of an abbreviation for a partial word (e.g. ";han") and its query ("han"):
-- 0 exact match, 1 starts with the partial, 2 contains the query, 3 its section contains
-- it, 4 no match
function M.rank(abbr, partial, query, section)
	if abbr == partial then
		return 0
	end
	if abbr:sub(1, #partial) == partial then
		return 1
	end
	if abbr:lower():find(query, 1, true) then
		return 2
	end
	if (section or ""):lower():find(query, 1, true) then
		return 3
	end
	return 4
end

-- Rank of a picker row ({ name, preview, section }) for the picker's own search query:
-- 0 name is the query, 1 name starts with it, 2 name contains it, 3 text or section
-- contains it; nil (left out) otherwise
function M.rowRank(row, query)
	local name = row.name:lower()
	if name == query then
		return 0
	elseif name:sub(1, #query) == query then
		return 1
	elseif name:find(query, 1, true) then
		return 2
	elseif row.preview:lower():find(query, 1, true) or row.section:lower():find(query, 1, true) then
		return 3
	end
end

return M
