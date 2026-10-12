-- The picker: an hs.chooser listing expansions, filtered, ranked and highlighted like fzf,
-- with a tile at the left of each row showing the expansion.
local M = {}

function M.new(options, util, matcher)
	local self = {}

	------------------------------------------------------------------------------------
	-- Tiles: the expansion drawn large on a rounded square. Symbols and emoji are drawn
	-- as they are; longer text (names, emails, URLs) gets a neutral "Aa". Drawing one
	-- takes ~2 ms, so tiles are cached by text and drawn in small batches in the
	-- background after a file loads (see self.warm).
	local tileCache = {}
	local tileSize = 64

	local function isSymbol(text)
		return #text <= 40 and not text:find("[%w%s]")
	end

	local function drawTile(label, size, color)
		local canvas = hs.canvas.new({ x = 0, y = 0, w = tileSize, h = tileSize })
		canvas[1] = {
			type = "rectangle",
			action = "fill",
			roundedRectRadii = { xRadius = 14, yRadius = 14 },
			fillColor = { white = 0.5, alpha = 0.16 },
		}
		canvas[2] = {
			type = "text",
			text = hs.styledtext.new(label, {
				font = { name = ".AppleSystemUIFont", size = size },
				color = color,
				paragraphStyle = { alignment = "center" },
			}),
			frame = { x = 0, y = (tileSize - size * 1.2) / 2, w = tileSize, h = size * 1.3 },
		}
		local image = canvas:imageFromCanvas()
		canvas:delete()
		return image
	end

	local textTile -- the shared "Aa" tile, drawn on first use

	local function tileFor(text)
		if not options.tiles then
			return nil
		end
		if not isSymbol(text) then
			textTile = textTile or drawTile("Aa", 26, { list = "System", name = "secondaryLabelColor" })
			return textTile
		end
		local tile = tileCache[text]
		if not tile then
			tile = drawTile(text, 38, { list = "System", name = "labelColor" })
			tileCache[text] = tile
		end
		return tile
	end

	-- Draw the tiles of a set's expansions ahead of time, a few at a time
	function self.warm(expansions)
		if not options.tiles then
			return
		end
		local todo = {}
		for _, text in pairs(expansions) do
			if isSymbol(text) and not tileCache[text] then
				todo[#todo + 1] = text
			end
		end
		local i = 1
		local function batch()
			for _ = 1, 25 do
				if i > #todo then
					return
				end
				tileFor(todo[i])
				i = i + 1
			end
			util.after(0.05, batch)
		end
		util.after(1, batch)
	end

	------------------------------------------------------------------------------------
	-- Rows: filtered, ranked and highlighted for the query. With a query callback set the
	-- chooser doesn't filter by itself, so each query change sets the rows again.
	local rows = {} -- { name, preview, section, expansion } of the open picker, as plain strings

	local function boldFont(size)
		local ok, font = pcall(hs.styledtext.convertFont, { name = ".AppleSystemUIFont", size = size }, hs.styledtext.fontTraits.boldFont)
		return ok and font or { name = ".AppleSystemUIFont", size = size }
	end

	local rowStyle = {
		name = { font = boldFont(16), color = { list = "System", name = "labelColor" } },
		section = { font = { name = ".AppleSystemUIFont", size = 11 }, color = { list = "System", name = "tertiaryLabelColor" } },
		preview = { font = { name = ".AppleSystemUIFont", size = 13 }, color = { list = "System", name = "secondaryLabelColor" } },
	}

	local function highlight(str, query, style)
		local match = { font = style.font, color = options.matchColor }
		local result = hs.styledtext.new("", style)
		local lower, pos = str:lower(), 1
		if query ~= "" then
			while true do
				local s, e = lower:find(query, pos, true)
				if not s then
					break
				end
				result = result .. hs.styledtext.new(str:sub(pos, s - 1), style) .. hs.styledtext.new(str:sub(s, e), match)
				pos = e + 1
			end
		end
		return result .. hs.styledtext.new(str:sub(pos), style)
	end

	local function styledChoices(query)
		query = (query or ""):lower()
		local ranked = {}
		for i, row in ipairs(rows) do
			local rank = matcher.rowRank(row, query)
			if rank then
				table.insert(ranked, { row = row, rank = rank, index = i })
			end
		end
		table.sort(ranked, function(a, b)
			if a.rank ~= b.rank then
				return a.rank < b.rank
			end
			return a.index < b.index
		end)
		local choices = {}
		for n, entry in ipairs(ranked) do
			local row = entry.row
			local text = highlight(row.name, query, rowStyle.name)
			if row.section ~= "" then
				text = text .. hs.styledtext.new("   ", rowStyle.section) .. highlight(row.section, query, rowStyle.section)
			end
			table.insert(choices, {
				text = text,
				subText = highlight(row.preview, query, rowStyle.preview),
				-- only the first rows draw a missing tile right away; the rest show one once drawn
				image = (n <= 40 or not isSymbol(row.expansion)) and tileFor(row.expansion) or tileCache[row.expansion],
				expansion = row.expansion,
			})
		end
		return choices
	end

	------------------------------------------------------------------------------------
	-- The chooser. On a choice, options.onChoose(partial, text, window) replaces the typed
	-- partial word in `window`; cancelling leaves the typed text alone.
	local openPartial, openWindow

	local chooser = hs.chooser.new(function(choice)
		local partial, window = openPartial, openWindow
		openPartial, openWindow = nil, nil
		if choice then
			options.onChoose(partial, choice.expansion, window)
		end
	end)
	chooser:width(options.width)
	chooser:rows(options.rows)
	chooser:placeholderText(options.placeholder)

	-- Setting choices reports the query again, so ignore that nested call
	local restyling = false
	chooser:queryChangedCallback(function(query)
		if restyling then
			return
		end
		restyling = true
		chooser:choices(styledChoices(query))
		restyling = false
	end)

	function self.isVisible()
		return chooser:isVisible()
	end

	-- Show the picker for `partial` (typed in `window`), listing `entries`
	-- ({ name, text, section } in order) and searching for `query`
	function self.show(partial, window, entries, query)
		rows = {}
		for _, entry in ipairs(entries) do
			table.insert(rows, {
				name = entry.name,
				preview = (entry.text:gsub("\n", " ⏎ ")),
				section = entry.section or "",
				expansion = entry.text,
			})
		end
		openPartial, openWindow = partial, window
		chooser:choices(styledChoices(query))
		chooser:query(query)
		chooser:bgDark(hs.host.interfaceStyle() == "Dark") -- follow the system appearance
		chooser:show()
		-- The pre-filled query is selected when the picker gets focus, so the next key
		-- would replace it. Press → once the picker has focus to put the cursor after it.
		local waiting
		waiting = util.keep(hs.timer.waitUntil(function()
			if not chooser:isVisible() then
				return true
			end
			local w = hs.window.focusedWindow()
			return w ~= nil and w:application():bundleID() == "org.hammerspoon.Hammerspoon"
		end, function()
			util.release(waiting)
			if chooser:isVisible() then
				hs.eventtap.keyStroke({}, "right", 0)
			end
		end, 0.02))
	end

	function self.delete()
		chooser:delete()
	end

	return self
end

return M
