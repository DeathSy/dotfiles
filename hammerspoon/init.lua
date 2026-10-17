-- Keyboard window focus and throw-window-to-Space, without a tiling WM.
-- Needs Accessibility permission (System Settings → Privacy & Security).

local events = hs.eventtap.event.types
local windows = hs.window.filter.defaultCurrentSpace

-- ⌥h/j/k/l: focus the nearest window in that direction on this Space.
for key, dir in pairs({ h = "West", j = "South", k = "North", l = "East" }) do
  hs.hotkey.bind({ "alt" }, key, function()
    windows["focusWindow" .. dir](windows, nil, true, true)
  end)
end

-- Native "Switch to Desktop N" shortcut, ⌃N (nix-darwin/hotkeys.nix).
local function gotoSpace(n)
  hs.eventtap.keyStroke({ "ctrl" }, tostring(n), 0)
end

local function mouse(type, point)
  hs.eventtap.event.newMouseEvent(type, point, {}):post()
end

-- hs.spaces.moveWindowToSpace silently does nothing on recent macOS, so hold
-- the window by its title bar, switch Desktop, and let go there.
local timers = {} -- referenced so pending timers aren't garbage collected
local function throw(n)
  local win = hs.window.focusedWindow()
  if not win or #timers > 0 then return end
  if win:isFullScreen() then
    hs.alert.show("Can't move a full-screen window")
    return
  end

  local zoom, frame = win:zoomButtonRect(), win:frame()
  local grab = zoom and { x = zoom.x + zoom.w + 6, y = zoom.y + zoom.h / 2 }
    or { x = frame.x + 10, y = frame.y + 10 }
  local drag = { x = grab.x + 1, y = grab.y }
  local home = hs.mouse.absolutePosition()

  local function at(delay, fn) table.insert(timers, hs.timer.doAfter(delay, fn)) end
  hs.mouse.absolutePosition(grab)
  mouse(events.leftMouseDown, grab)
  -- A small drag makes macOS treat the press as a window move.
  at(0.05, function() mouse(events.leftMouseDragged, drag) end)
  at(0.15, function() gotoSpace(n) end)
  at(0.55, function()
    timers = {}
    mouse(events.leftMouseUp, drag)
    hs.mouse.absolutePosition(home)
  end)
end

-- ⌥⇧1…9: throw the focused window to Desktop N and follow it.
for n = 1, 9 do
  hs.hotkey.bind({ "alt", "shift" }, tostring(n), function() throw(n) end)
end

-- hammerspoon://space?n=N and hammerspoon://throw?n=N, used by the `space` CLI.
local function desktop(params)
  return params.n and params.n:match("^[1-9]$") and tonumber(params.n)
end
hs.urlevent.bind("space", function(_, params)
  local n = desktop(params)
  if n then gotoSpace(n) end
end)
hs.urlevent.bind("throw", function(_, params)
  local n = desktop(params)
  if n then throw(n) end
end)

-- Reload when a .lua file changes in the checkout init.lua links to.
local dir = hs.fs.pathToAbsolute(hs.configdir .. "/init.lua"):match("^(.*)/")
ConfigWatcher = hs.pathwatcher.new(dir, function(paths)
  for _, path in ipairs(paths) do
    if path:match("%.lua$") then return hs.reload() end
  end
end):start()
hs.alert.show("Hammerspoon config loaded")
