-- Keyboard window focus and throw-window-to-Space, without a tiling WM.
-- Needs Accessibility permission (System Settings → Privacy & Security).
-- Keys are raw keycodes so they work with any input source (ABC or Thai).

local events = hs.eventtap.event.types
local windows = hs.window.filter.defaultCurrentSpace
local digits = { 18, 19, 20, 21, 23, 22, 26, 28, 25 } -- 1…9

-- ⌃⌥h/j/k/l: focus the nearest window in that direction on this Space.
for key, dir in pairs({ [4] = "West", [38] = "South", [40] = "North", [37] = "East" }) do
  hs.hotkey.bind({ "ctrl", "alt" }, key, function()
    windows["focusWindow" .. dir](windows, nil, true, true)
  end)
end

-- Native "Switch to Desktop N" shortcut, ⌃N (nix-darwin/hotkeys.nix).
local function gotoSpace(n)
  hs.eventtap.keyStroke({ "ctrl" }, digits[n], 0)
end

local function mouse(type, point)
  hs.eventtap.event.newMouseEvent(type, point, {}):post()
end

local function heldModifiers()
  local mods = hs.eventtap.checkKeyboardModifiers()
  return mods.alt or mods.shift or mods.cmd
end

-- Pressing inside one of these would click it instead of holding the window.
local controls = { AXButton = true, AXRadioButton = true, AXTab = true, AXTabGroup = true,
  AXTextField = true, AXTextArea = true, AXLink = true }

-- True only if the point is on the window itself, not on a control in it.
-- Anything unreadable counts as "no".
local function bareTitleBar(point)
  local el = hs.axuielement.systemElementAtPosition(point)
  for _ = 1, 20 do
    local role = el and el:attributeValue("AXRole")
    if not role or controls[role] then return false end
    if role == "AXWindow" then return true end
    el = el:attributeValue("AXParent")
  end
  return false
end

-- The running throw: its current timer (referenced so it isn't garbage
-- collected) and, while the mouse is held, where to release and restore it.
local pending, held
local function cleanup()
  if pending then pending:stop() end
  pending = nil
  if held then
    local h = held
    held = nil
    pcall(mouse, events.leftMouseUp, h.drag)
    pcall(hs.mouse.absolutePosition, h.home)
  end
end
hs.shutdownCallback = cleanup -- runs on reload and quit

-- Run fn, and let go of the window if it fails.
local function guarded(fn)
  return function(...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    cleanup()
    print("throw failed: " .. tostring(result))
  end
end

-- hs.spaces.moveWindowToSpace silently does nothing on recent macOS, so hold
-- the window by its title bar, switch Desktop, and let go there.
local throw = guarded(function(n)
  local win = hs.window.focusedWindow()
  if held or not win or not win:isStandard() then return end
  if win:isFullScreen() then return hs.alert.show("Can't move a full-screen window") end

  -- Grab just right of the zoom button: empty title bar in most apps, and the
  -- empty start of WezTerm's tab bar.
  local zoom = win:zoomButtonRect()
  local grab = zoom and { x = zoom.x + zoom.w + 6, y = zoom.y + zoom.h / 2 }
  if not grab or not bareTitleBar(grab) then return hs.alert.show("No title bar to grab") end

  held = { drag = { x = grab.x + 1, y = grab.y }, home = hs.mouse.absolutePosition() }
  hs.mouse.absolutePosition(grab)
  mouse(events.leftMouseDown, grab)
  pending = hs.timer.doAfter(0.05, guarded(function()
    -- A small drag makes macOS treat the press as a window move.
    mouse(events.leftMouseDragged, held.drag)
    -- Wait for ⌥⇧ to come up so it doesn't leak into ⌃N.
    local deadline = hs.timer.secondsSinceEpoch() + 1.5
    pending = hs.timer.waitUntil(guarded(function()
      return not heldModifiers() or hs.timer.secondsSinceEpoch() > deadline
    end), guarded(function()
      if heldModifiers() then
        cleanup()
        return hs.alert.show("Let go of ⌥⇧ to throw the window")
      end
      gotoSpace(n)
      pending = hs.timer.doAfter(0.4, cleanup)
    end), 0.02)
  end))
end)

-- ⌥⇧1…9: throw the focused window to Desktop N and follow it.
for n, key in ipairs(digits) do
  hs.hotkey.bind({ "alt", "shift" }, key, function() throw(n) end)
end

-- hammerspoon://space?n=N switches to Desktop N; used by the `space` CLI.
hs.urlevent.bind("space", function(_, params)
  local n = params.n and params.n:match("^[1-9]$")
  if n then gotoSpace(tonumber(n)) end
end)

-- Reload when a .lua file changes in the checkout init.lua links to.
local dir = hs.fs.pathToAbsolute(hs.configdir .. "/init.lua"):match("^(.*)/")
ConfigWatcher = hs.pathwatcher.new(dir, function(paths)
  for _, path in ipairs(paths) do
    if path:match("%.lua$") then return hs.reload() end
  end
end):start()
hs.alert.show("Hammerspoon config loaded")
