-- Keyboard window focus and throw-window-to-Space, without a tiling WM.
-- Needs Accessibility permission (System Settings → Privacy & Security).
-- Keys are raw keycodes so they work with any input source (ABC or Thai).

-- Track Mission Control always; hide borders when Nix supplies a restore colour.
local hasBorderColor, borderColor = pcall(dofile, "/etc/hammerspoon-borders.lua")
local missionControl, bordersHidden, borderTask = false, false
MissionControlWatcher = hs.timer.doEvery(0.1, function()
  local open = false
  -- true lists every on-screen window without the name-dependent Dock filter.
  for _, w in ipairs(hs.window.list(true)) do
    local layer = w.kCGWindowLayer
    if w.kCGWindowOwnerName == "WindowManager" and layer >= 14 and layer <= 19 then
      open = true
      break
    end
  end
  missionControl = open
  if not hasBorderColor or bordersHidden == missionControl then return end
  local task = hs.task.new("/run/current-system/sw/bin/borders", nil,
    { "active_color=" .. (open and "0x00000000" or borderColor) })
  if task and task:start() then borderTask, bordersHidden = task, open end
end)

local events = hs.eventtap.event.types
local digits = { 18, 19, 20, 21, 23, 22, 26, 28, 25 } -- 1…9

-- ⌃⌥h/j/k/l: focus the nearest standard, visible window on this Space.
for key, dir in pairs({ [4] = "West", [38] = "South", [40] = "North", [37] = "East" }) do
  hs.hotkey.bind({ "ctrl", "alt" }, key, function()
    local win = hs.window.focusedWindow()
    if not win then return end
    local candidates = {}
    for _, w in ipairs(hs.window.orderedWindows()) do
      if w:isStandard() and w:isVisible() then candidates[#candidates + 1] = w end
    end
    win["focusWindow" .. dir](win, candidates, true, true)
  end)
end

-- Steps from screen's current Space to its Desktop n, in Mission Control order
-- (a full-screen app counts as a step), negative = left; or nil and why not.
local function desktopSteps(screen, n)
  local current, from, to, count = hs.spaces.activeSpaceOnScreen(screen), nil, nil, 0
  for i, id in ipairs(hs.spaces.spacesForScreen(screen) or {}) do
    if id == current then from = i end
    if hs.spaces.spaceType(id) == "user" then
      count = count + 1
      if count == n then to = i end
    end
  end
  if not to then return nil, "No Desktop " .. n .. " on this display" end
  if not from then return nil, "Can't find this display's current Space" end
  if to == from then return nil, "Already on Desktop " .. n end
  return to - from
end

local function mouse(type, point)
  hs.eventtap.event.newMouseEvent(type, point, {}):post()
end

local function heldModifiers()
  local mods = hs.eventtap.checkKeyboardModifiers()
  return mods.alt or mods.shift or mods.cmd or mods.ctrl
end

-- Pressing inside one of these would click it instead of holding the window.
local controls = { AXButton = true, AXRadioButton = true, AXTab = true,
  AXTextField = true, AXTextArea = true, AXLink = true }

-- True only if the point is on win itself, not on a control in it or on
-- another window floating over it. Anything unreadable counts as "no".
local function bareTitleBar(win, point)
  local el = hs.axuielement.systemElementAtPosition(point)
  for _ = 1, 20 do
    local role = el and el:attributeValue("AXRole")
    if not role or controls[role] then return false end
    if role == "AXWindow" then return el == hs.axuielement.windowElement(win) end
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
    pcall(mouse, events.leftMouseUp, h.drag)
    pcall(hs.mouse.absolutePosition, h.home)
    held = nil
  end
end
hs.shutdownCallback = function() -- runs on reload and quit
  cleanup()
  if hasBorderColor and bordersHidden then
    hs.execute("/run/current-system/sw/bin/borders active_color=" .. borderColor)
  end
end

-- Follow focus from any source, without disturbing clicks or a running throw.
FocusWatcher = hs.window.filter.new(true):subscribe(hs.window.filter.windowFocused, function(win)
  pcall(function()
    if held or missionControl or not win or not win:isStandard() then return end
    for _, down in pairs(hs.eventtap.checkMouseButtons()) do
      if down then return end
    end
    local frame = win:frame()
    if not frame then return end
    if not hs.geometry.new(hs.mouse.absolutePosition()):inside(frame) then
      hs.mouse.absolutePosition(frame.center)
    end
  end)
end)

-- Run fn, and let go of the window if it fails.
local function guarded(fn)
  return function(...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    cleanup()
    print("throw failed: " .. tostring(result))
    hs.alert.show("Throw failed")
  end
end

-- Press "Move left/right a space" (nix-darwin/hotkeys.nix 79/81: ⌃⌥⌘←/→,
-- which acts on the display under the mouse) steps times, waiting for each
-- slide to land since macOS drops keys mid-animation. Then done(ok).
local function stepSpaces(screen, steps, done)
  local before = hs.spaces.activeSpaceOnScreen(screen)
  hs.eventtap.keyStroke({ "fn", "ctrl", "alt", "cmd" }, steps > 0 and 124 or 123, 0)
  local deadline = hs.timer.secondsSinceEpoch() + 1
  pending = hs.timer.waitUntil(function()
    return hs.spaces.activeSpaceOnScreen(screen) ~= before or hs.timer.secondsSinceEpoch() > deadline
  end, guarded(function()
    if hs.spaces.activeSpaceOnScreen(screen) == before then return done(false) end
    local rest = steps > 0 and steps - 1 or steps + 1
    if rest == 0 then return done(true) end
    stepSpaces(screen, rest, done)
  end), 0.02)
end

-- hs.spaces.moveWindowToSpace silently does nothing on recent macOS, so hold
-- the window by its title bar, switch Desktop, and let go there.
local throw = guarded(function(n)
  local win = hs.window.focusedWindow()
  if pending or held or not win or not win:isStandard() then return end
  if win:isFullScreen() then return hs.alert.show("Can't move a full-screen window") end
  local screen = win:screen()
  local steps, why = desktopSteps(screen, n)
  if not steps then return hs.alert.show(why) end

  -- Grab just right of the zoom button: empty title bar in most apps, and the
  -- empty start of WezTerm's tab bar.
  local zoom = win:zoomButtonRect()
  local grab = zoom and { x = zoom.x + zoom.w + 6, y = zoom.y + zoom.h / 2 }
  if not grab or not bareTitleBar(win, grab) then return hs.alert.show("No title bar to grab") end

  held = { drag = { x = grab.x + 1, y = grab.y }, home = hs.mouse.absolutePosition() }
  hs.mouse.absolutePosition(grab)
  mouse(events.leftMouseDown, grab)
  pending = hs.timer.doAfter(0.05, guarded(function()
    -- A small drag makes macOS treat the press as a window move.
    mouse(events.leftMouseDragged, held.drag)
    -- Wait for the modifiers to come up so they don't leak into the shortcut.
    local deadline = hs.timer.secondsSinceEpoch() + 1.5
    pending = hs.timer.waitUntil(function()
      return not heldModifiers() or hs.timer.secondsSinceEpoch() > deadline
    end, guarded(function()
      if heldModifiers() then
        cleanup()
        return hs.alert.show("Let go of ⌥⇧ to throw the window")
      end
      -- The mouse is on the title bar, so the steps move the window's display.
      stepSpaces(screen, steps, function(ok)
        if not ok then
          cleanup()
          return hs.alert.show("Desktop didn't switch")
        end
        pending = hs.timer.doAfter(0.4, guarded(function()
          held.home = win:frame().center
          cleanup()
        end))
      end)
    end), 0.02)
  end))
end)

-- ⌥⇧1…9: throw the focused window to Desktop N of its display and follow it.
for n, key in ipairs(digits) do
  hs.hotkey.bind({ "alt", "shift" }, key, function() throw(n) end)
end

-- hammerspoon://space?n=N switches to Desktop N of the focused window's
-- display, or the one under the mouse, moving the mouse there first for the
-- step shortcut; used by the `space` CLI.
hs.urlevent.bind("space", guarded(function(_, params)
  local n = params.n and params.n:match("^[1-9]$")
  if pending or held or not n then return end
  local win = hs.window.focusedWindow()
  local screen = win and win:screen() or hs.mouse.getCurrentScreen()
  local steps, why = desktopSteps(screen, tonumber(n))
  if not steps then return hs.alert.show(why) end
  local under = hs.mouse.getCurrentScreen()
  if not under or under:id() ~= screen:id() then hs.mouse.absolutePosition(screen:frame().center) end
  stepSpaces(screen, steps, function(ok)
    pending = nil
    if not ok then hs.alert.show("Desktop didn't switch") end
  end)
end))

-- Reload when a .lua file changes in the checkout init.lua links to.
local dir = hs.fs.pathToAbsolute(hs.configdir .. "/init.lua"):match("^(.*)/")
ConfigWatcher = hs.pathwatcher.new(dir, function(paths)
  for _, path in ipairs(paths) do
    if path:match("%.lua$") then return hs.reload() end
  end
end):start()
hs.alert.show("Hammerspoon config loaded")
