--- === SemiExpand ===
---
--- Text expansions typed as `;name`, read from plain-text files.
---
--- * An abbreviation expands as soon as what you typed starts only it: when complete, or
---   from `minUniqueChars` letters on (`;keyb` → ⌨️; the rest of the name, if typed on,
---   is swallowed). One that several abbreviations start with (`;pi` vs `;pin`) waits.
--- * The picker key (space) after `;name` expands it; after a partial name that starts
---   only one abbreviation, expands that one; after any other partial name with matches,
---   opens a searchable picker (by name, text or section).
--- * A short pause ends the word: a complete `;name` expands, anything else is left as typed.
--- * Esc right after `;` types the text literally (`;⎋done` → `;done`).
---
--- Each file in `sets` has its own prefix (e.g. `;` and `;;`), and a word is only looked
--- up in the set with the longest matching prefix. File format, one entry per line:
---   name [name…] "text"     names share the text, written without the prefix
---   # Section               starts a searchable section
---   // comment
---
--- Needs Accessibility access for Hammerspoon. Keystrokes typed while macOS secure input
--- is on (password fields) can't be seen, so nothing expands then.
---
--- Download: [https://github.com/navid-abbaszadeh/Spoons/raw/main/Spoons/SemiExpand.spoon.zip](https://github.com/navid-abbaszadeh/Spoons/raw/main/Spoons/SemiExpand.spoon.zip)

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "SemiExpand"
obj.version = "0.9.0"
obj.author = "Navid Abbaszadeh"
obj.homepage = "https://github.com/navid-abbaszadeh/Spoons"
obj.license = "MIT - https://opensource.org/licenses/MIT"

--- SemiExpand.directory
--- Variable
--- The folder with the expansion files. Default: `$XDG_CONFIG_HOME/semiexpand` if that
--- variable is set for Hammerspoon, otherwise `~/.config/semiexpand`.
obj.directory = nil

--- SemiExpand.sets
--- Variable
--- The expansion files, each `{ file = path, prefix = string, optional = bool }`. A
--- relative `file` is inside `directory`. Prefixes are made of the trigger character (`;`,
--- `;;`, …). An optional file that doesn't exist is skipped silently. Default:
---  * `expansions.md` with `;`
---  * `personal.md` with `;;`, optional
obj.sets = {
	{ file = "expansions.md", prefix = ";" },
	{ file = "personal.md", prefix = ";;", optional = true },
}

--- SemiExpand.trigger
--- Variable
--- The character that starts an abbreviation. Default `";"`.
obj.trigger = ";"

--- SemiExpand.pickerKey
--- Variable
--- The character that expands or opens the picker after a partial name. Default `" "`.
obj.pickerKey = " "

--- SemiExpand.minUniqueChars
--- Variable
--- A partial name shorter than this (not counting the prefix) only expands when it is a
--- complete abbreviation, so a stray `;q` in normal text doesn't turn into something.
--- Default 2.
obj.minUniqueChars = 2

--- SemiExpand.pauseSeconds
--- Variable
--- After this pause while typing a name, a complete `;name` expands and anything else is
--- left as typed. Default 1.
obj.pauseSeconds = 1.0

--- SemiExpand.restSeconds
--- Variable
--- After an early expansion, the rest of the name is swallowed while it keeps coming
--- within this many seconds. Default 2.
obj.restSeconds = 2

--- SemiExpand.alertOnReload
--- Variable
--- Show an alert when an expansions file is reloaded after a save. Default true.
obj.alertOnReload = true

--- SemiExpand.picker
--- Variable
--- Picker appearance: `{ width = percent, rows = n, placeholder = text, matchColor = color,
--- tiles = bool }`.
obj.picker = {
	width = 36,
	rows = 9,
	placeholder = "Search by name, text or section…",
	matchColor = { red = 1, green = 0.65, blue = 0.25 },
	tiles = true,
}

local util = dofile(hs.spoons.resourcePath("util.lua"))
local parser = dofile(hs.spoons.resourcePath("parser.lua"))
local matcher = dofile(hs.spoons.resourcePath("matcher.lua"))
local pickerModule = dofile(hs.spoons.resourcePath("picker.lua"))

--- SemiExpand:init()
--- Method
--- Called by hs.loadSpoon; nothing runs until :start().
---
--- Parameters:
---  * None
---
--- Returns:
---  * The SemiExpand object
function obj:init()
	return self
end

-- Load (or reload) one set from its file
local function loadSet(self, set)
	local expansions, sections = parser.parseFile(set.path, set.prefix)
	if not expansions then
		if not set.optional then
			hs.alert.show(set.path:match("[^/]+$") .. " not found")
		end
		expansions, sections = {}, {}
	end
	set.expansions, set.sections = expansions, sections
	set.unique = matcher.findUnique(expansions)
	self._picker.warm(expansions)
end

--- SemiExpand:start()
--- Method
--- Loads the files, watches them for changes and starts expanding. Calling it again
--- restarts with the current settings.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The SemiExpand object
function obj:start()
	if self._tap then
		self:stop()
	end
	local trigger = self.trigger
	local triggerPattern = "^%" .. trigger .. "+$"

	-- Typing state: the recent characters, and the rest of a name expanded early
	local buffer = ""
	local rest, restTime = "", 0

	-- The folder with the files: the directory setting, else $XDG_CONFIG_HOME/semiexpand,
	-- else ~/.config/semiexpand
	local directory = self.directory and util.expandPath(self.directory)
	if not directory then
		local xdg = os.getenv("XDG_CONFIG_HOME")
		directory = ((xdg and xdg ~= "") and xdg or (os.getenv("HOME") .. "/.config")) .. "/semiexpand"
	end
	self._directory = directory

	-- Sets, longest prefix first; a relative file is inside the folder
	local sets, maxPrefix = {}, 1
	for _, config in ipairs(self.sets) do
		assert(config.prefix:match(triggerPattern), "SemiExpand: prefix " .. config.prefix .. " isn't made of " .. trigger)
		local path = config.file:match("^[/~]") and util.expandPath(config.file) or (directory .. "/" .. config.file)
		table.insert(sets, { path = path, prefix = config.prefix, optional = config.optional })
		maxPrefix = math.max(maxPrefix, #config.prefix)
	end
	table.sort(sets, function(a, b)
		return #a.prefix > #b.prefix
	end)
	self._sets = sets

	local function currentWord(needChars)
		return matcher.currentWord(buffer, trigger, maxPrefix, needChars)
	end

	local function setFor(word)
		return matcher.setFor(sets, word)
	end

	local function stripPrefix(word)
		return (word:gsub("^%" .. trigger .. "+", ""))
	end

	-- Replace the typed `partial` with `text`
	local function replacePartial(partial, text)
		util.replaceBeforeCursor(util.length(partial), text)
	end

	self._picker = pickerModule.new({
		width = self.picker.width,
		rows = self.picker.rows,
		placeholder = self.picker.placeholder,
		matchColor = self.picker.matchColor,
		tiles = self.picker.tiles,
		onChoose = function(partial, text, window)
			buffer = ""
			if window then
				window:focus()
			end
			-- give focus a moment to land back in the original app
			util.after(0.1, function()
				replacePartial(partial, text)
			end)
		end,
	}, util, matcher)
	local picker = self._picker

	for _, set in ipairs(sets) do
		loadSet(self, set)
		-- Reload whenever the file changes. The file's folder is watched rather than the
		-- file, so a file created later (an optional personal.md) is picked up too. The
		-- watcher is kept on the set; a folder that doesn't exist yet isn't watched.
		local folder, name = set.path:match("^(.*)/([^/]+)$")
		local ok, watcher = pcall(hs.pathwatcher.new, folder, function(paths)
			for _, changed in ipairs(paths) do
				if changed:match("[^/]+$") == name then
					loadSet(self, set)
					if self.alertOnReload then
						hs.alert.show(name .. " reloaded")
					end
					return
				end
			end
		end)
		set.watcher = ok and watcher and watcher:start() or nil
	end

	-- The picker key after ;name expands it; after a partial that starts exactly one
	-- abbreviation, expands that one. Returns true if it expanded (the key is swallowed).
	local function expandOnPickerKey()
		local partial = currentWord(true)
		if not partial then
			return false
		end
		local expansions = setFor(partial).expansions
		local text = expansions[partial]
		if not text then
			for abbr, candidate in pairs(expansions) do
				if abbr:sub(1, #partial) == partial then
					if text then
						return false -- more than one: leave it alone
					end
					text = candidate
				end
			end
		end
		if not text then
			return false
		end
		buffer = ""
		util.after(0, function()
			replacePartial(partial, text)
		end)
		return true
	end

	-- Open the picker for the partial word being typed (a single match is completed
	-- directly). Returns true if handled (the key that triggered it is swallowed).
	local function openPicker()
		local partial = currentWord(false)
		if not partial then
			return false
		end
		-- A bare ";" (or ";;") lists everything, but only at the start of a word,
		-- so "; " in prose is typed as usual
		local before = buffer:sub(1, -#partial - 1)
		if partial:match(triggerPattern) and before ~= "" and not before:match("%s$") then
			return false
		end
		local set = setFor(partial)
		local expansions, sections = set.expansions, set.sections
		local query = stripPrefix(partial):lower()

		local matches = {}
		for abbr, text in pairs(expansions) do
			if matcher.rank(abbr, partial, query, sections[abbr]) < 4 then
				table.insert(matches, { abbr = abbr, text = text })
			end
		end
		if #matches == 0 then
			return false
		end

		-- A single match is completed directly, like shell completion
		if #matches == 1 then
			buffer = ""
			util.after(0, function()
				replacePartial(partial, matches[1].text)
			end)
			return true
		end

		-- The picker lists every expansion of the set so its search can find any of them
		-- (e.g. "mouse" finds ";pcmouse"); ordered by rank, so abbreviation matches come
		-- before section matches. Names are shown without the prefix, as in the file.
		local all = {}
		for abbr, text in pairs(expansions) do
			table.insert(all, { abbr = abbr, text = text, rank = matcher.rank(abbr, partial, query, sections[abbr]) })
		end
		table.sort(all, function(a, b)
			if a.rank ~= b.rank then
				return a.rank < b.rank
			end
			return a.abbr < b.abbr
		end)
		local entries = {}
		for _, m in ipairs(all) do
			table.insert(entries, { name = m.abbr:sub(#set.prefix + 1), text = m.text, section = sections[m.abbr] })
		end
		local window = hs.window.focusedWindow()
		util.after(0, function()
			picker.show(partial, window, entries, stripPrefix(partial))
		end)
		return true
	end

	-- After a pause, the word being typed is done: a complete ;name expands, anything else
	-- is dropped from the buffer so a following picker key is just typed
	self._pauseTimer = hs.timer.delayed.new(self.pauseSeconds, function()
		local word = currentWord(true)
		buffer = ""
		if not word or picker.isVisible() then
			return
		end
		local text = setFor(word).expansions[word]
		if text then
			replacePartial(word, text)
		end
	end)
	local pauseTimer = self._pauseTimer

	-- Restart the pause countdown while a word is being typed
	local function restartPauseTimer()
		if currentWord(false) then
			pauseTimer:start()
		else
			pauseTimer:stop()
		end
	end

	-- After an early expansion (;keyb → ⌨️) the rest of the name ("oard") may still be
	-- typed out of habit: it is swallowed as long as it keeps matching and keeps coming
	local restSeconds = self.restSeconds
	local function swallowRest(ch)
		if rest == "" then
			return false
		end
		local now = hs.timer.secondsSinceEpoch()
		if ch ~= "" and rest:sub(1, #ch) == ch and now - restTime < restSeconds then
			rest, restTime = rest:sub(#ch + 1), now
			return true
		end
		rest = ""
		return false
	end

	-- Keys that move the cursor (or cancel) without typing: the buffer no longer matches
	-- the text before the cursor, so it is cleared
	local cursorKeys = {}
	for _, name in ipairs({ "left", "right", "up", "down", "home", "end", "pageup", "pagedown", "escape", "forwarddelete" }) do
		cursorKeys[hs.keycodes.map[name]] = true
	end
	local deleteKey = hs.keycodes.map.delete
	local pickerKey, minUniqueChars = self.pickerKey, self.minUniqueChars

	-- A typed character (after the checks for modifiers, cursor keys and delete): returns
	-- true if it is swallowed.
	local function typeCharacter(ch)
		if swallowRest(ch) then
			return true
		end
		if ch == pickerKey and (expandOnPickerKey() or openPicker()) then
			return true
		end
		buffer = (buffer .. ch):sub(-30)
		restartPauseTimer()

		-- Expand as soon as the word starts only one abbreviation: when it is complete
		-- (;done), or from minUniqueChars letters on (;keyb → ⌨️). A word several
		-- abbreviations start with (;pi: ;pig ;pin …) waits for the picker key.
		local word = currentWord(false)
		local set = word and setFor(word)
		local abbr = set and set.unique[word]
		local typed = word and set and util.length(word) - #set.prefix
		if abbr and (abbr == word or typed >= minUniqueChars) then
			local text = set.expansions[abbr]
			buffer = ""
			rest, restTime = abbr:sub(#word + 1), hs.timer.secondsSinceEpoch()
			util.after(0, function()
				util.replaceBeforeCursor(util.length(word) - 1, text)
			end)
			return true -- swallow the last key of the abbreviation
		end
		return false
	end

	local types = hs.eventtap.event.types
	self._tap = hs.eventtap
		.new({ types.keyDown, types.leftMouseDown, types.rightMouseDown }, function(e)
			-- Keys typed into the picker itself are not part of the buffer
			if picker.isVisible() then
				return false
			end
			-- A click may move the cursor anywhere, so start over
			if e:getType() ~= types.keyDown then
				buffer, rest = "", ""
				return false
			end
			if cursorKeys[e:getKeyCode()] then
				buffer, rest = "", ""
				return false
			end
			-- (rest is kept here: the expansion's own cmd-v passes through this check)
			local f = e:getFlags()
			if f.cmd or f.ctrl or f.alt then
				buffer = ""
				return false
			end
			if e:getKeyCode() == deleteKey then
				buffer = buffer:sub(1, -2)
				restartPauseTimer()
				return false
			end
			return typeCharacter(e:getCharacters() or "")
		end)
		:start()
	return self
end

--- SemiExpand:stop()
--- Method
--- Stops expanding and watching the files.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The SemiExpand object
function obj:stop()
	if self._tap then
		self._tap:stop()
		self._tap = nil
	end
	if self._pauseTimer then
		self._pauseTimer:stop()
		self._pauseTimer = nil
	end
	for _, set in ipairs(self._sets or {}) do
		if set.watcher then
			set.watcher:stop()
		end
	end
	self._sets = nil
	if self._picker then
		self._picker.delete()
		self._picker = nil
	end
	return self
end

--- SemiExpand:isRunning()
--- Method
--- Whether the Spoon is expanding.
---
--- Parameters:
---  * None
---
--- Returns:
---  * true while expanding, false otherwise
function obj:isRunning()
	return self._tap ~= nil and self._tap:isEnabled()
end

return obj
