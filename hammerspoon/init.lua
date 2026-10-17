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

-- Pressing one of these would click it instead of holding the window.
local clickable = { AXButton = true, AXRadioButton = true, AXTab = true }

-- hs.spaces.moveWindowToSpace silently does nothing on recent macOS, so hold
-- the window by its title bar, switch Desktop, and let go there.
local pending -- the running throw's timer, referenced so it isn't garbage collected
local function throw(n)
  local win = hs.window.focusedWindow()
  if pending or not win or not win:isStandard() then return end
  if win:isFullScreen() then return hs.alert.show("Can't move a full-screen window") end

  -- Grab just right of the zoom button: empty title bar in most apps, and the
  -- empty start of WezTerm's tab bar.
  local zoom = win:zoomButtonRect()
  local grab = zoom and { x = zoom.x + zoom.w + 6, y = zoom.y + zoom.h / 2 }
  local hit = grab and hs.axuielement.systemElementAtPosition(grab)
  if not grab or (hit and clickable[hit:attributeValue("AXRole")]) then
    return hs.alert.show("No title bar to grab")
  end
  local drag = { x = grab.x + 1, y = grab.y }
  local home = hs.mouse.absolutePosition()
  local function release()
    pending = nil
    mouse(events.leftMouseUp, drag)
    hs.mouse.absolutePosition(home)
  end

  hs.mouse.absolutePosition(grab)
  mouse(events.leftMouseDown, grab)
  pending = hs.timer.doAfter(0.05, function()
    -- A small drag makes macOS treat the press as a window move.
    mouse(events.leftMouseDragged, drag)
    -- Wait for ⌥⇧ to come up so it doesn't leak into ⌃N.
    local deadline = hs.timer.secondsSinceEpoch() + 1.5
    pending = hs.timer.waitUntil(function()
      return not heldModifiers() or hs.timer.secondsSinceEpoch() > deadline
    end, function()
      if heldModifiers() then
        release()
        return hs.alert.show("Let go of ⌥⇧ to throw the window")
      end
      gotoSpace(n)
      pending = hs.timer.doAfter(0.4, release)
    end, 0.02)
  end)
end

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
