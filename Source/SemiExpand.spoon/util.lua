-- Small helpers shared by the Spoon's modules
local M = {}

-- One-shot timers and tasks that nothing refers to can be garbage-collected before they
-- fire (an expansion then silently doesn't happen), so each is kept here until it has run
local pending = {}

function M.keep(object)
	pending[object] = true
	return object
end

function M.release(object)
	pending[object] = nil
end

-- hs.timer.doAfter that is sure to fire
function M.after(seconds, fn)
	local timer
	timer = M.keep(hs.timer.doAfter(seconds, function()
		M.release(timer)
		fn()
	end))
	return timer
end

-- hs.task that is sure to run its callback: callback(output) on success, callback(nil)
-- if it fails or can't start
function M.run(bin, args, callback)
	local task
	task = hs.task.new(bin, function(code, out)
		M.release(task)
		callback(code == 0 and out or nil)
	end, args)
	M.keep(task)
	if not task:start() then
		M.release(task)
		callback(nil)
	end
end

-- Paste `text` through the clipboard, then put the previous clipboard back.
-- The temporary copy is marked transient so clipboard history ignores it, and
-- restoring every data type keeps markers like a password manager's "concealed".
function M.pasteText(text)
	local old = hs.pasteboard.readAllData()
	hs.pasteboard.writeAllData({
		["public.utf8-plain-text"] = text,
		["org.nspasteboard.TransientType"] = "",
	})
	hs.eventtap.keyStroke({ "cmd" }, "v")
	M.after(0.3, function()
		hs.pasteboard.writeAllData(old)
	end)
end

-- Delete `count` characters before the cursor (one backspace each), then paste `text`
function M.replaceBeforeCursor(count, text)
	for _ = 1, count do
		hs.eventtap.keyStroke({}, "delete", 0)
	end
	M.pasteText(text)
end

-- Number of characters in a string (bytes if it isn't valid UTF-8)
function M.length(s)
	return utf8.len(s) or #s
end

-- "~/x" → "/Users/me/x"
function M.expandPath(path)
	return (path:gsub("^~", os.getenv("HOME")))
end

function M.firstExisting(paths)
	for _, path in ipairs(paths) do
		if path and hs.fs.attributes(path) then
			return path
		end
	end
end

return M
