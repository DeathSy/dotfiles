-- Keyboard window focus and virtual workspaces (workspaces.lua), without a tiling WM.
-- Needs Accessibility permission (System Settings → Privacy & Security).
-- Keys are raw keycodes so they work with any input source (ABC or Thai).

-- The checkout init.lua links to; workspaces.lua is loaded from there too.
local dir = hs.fs.pathToAbsolute(hs.configdir .. "/init.lua"):match("^(.*)/")
package.path = dir .. "/?.lua;" .. package.path
-- If workspaces.lua breaks, the rest still loads.
local loaded, workspaces = pcall(require, "workspaces")
if not loaded then
  print("workspaces: " .. tostring(workspaces))
  workspaces = nil
end

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
  if workspaces then workspaces.paused = open end
  if not hasBorderColor or bordersHidden == missionControl then return end
  local task = hs.task.new("/run/current-system/sw/bin/borders", nil,
    { "active_color=" .. (open and "0x00000000" or borderColor) })
  if task and task:start() then borderTask, bordersHidden = task, open end
end)

local digits = { 18, 19, 20, 21, 23, 22, 26, 28, 25 } -- 1…9

-- ⌃⌥h/j/k/l: focus the nearest standard, visible window, skipping parked ones.
for key, side in pairs({ [4] = "West", [38] = "South", [40] = "North", [37] = "East" }) do
  hs.hotkey.bind({ "ctrl", "alt" }, key, function()
    local win = hs.window.focusedWindow()
    if not win then return end
    local candidates = {}
    for _, w in ipairs(hs.window.orderedWindows()) do
      if w:isStandard() and w:isVisible() and not (workspaces and workspaces.parked(w)) then
        candidates[#candidates + 1] = w
      end
    end
    win["focusWindow" .. side](win, candidates, true, true)
  end)
end

hs.shutdownCallback = function() -- runs on reload and quit
  if workspaces then workspaces.shutdown() end
  if hasBorderColor and bordersHidden then
    hs.execute("/run/current-system/sw/bin/borders active_color=" .. borderColor)
  end
end

if workspaces then
  -- ⌃1…9: focus workspace N, showing it if hidden. ⌥⇧1…9: move the focused
  -- window there and follow it. The mouse follows focus (workspaces.lua).
  for n, key in ipairs(digits) do
    hs.hotkey.bind({ "ctrl" }, key, function() workspaces.switch(n) end)
    hs.hotkey.bind({ "alt", "shift" }, key, function() workspaces.move(n) end)
  end

  -- hammerspoon://space?n=N does what ⌃N does; space?unpark=1 brings every
  -- window back on-screen and starts over. Used by the `space` CLI.
  hs.urlevent.bind("space", function(_, params)
    local n = params.n and params.n:match("^[1-9]$")
    if n then workspaces.switch(tonumber(n)) elseif params.unpark then workspaces.unpark() end
  end)
end

-- Reload when a .lua file changes in the checkout.
ConfigWatcher = hs.pathwatcher.new(dir, function(paths)
  for _, path in ipairs(paths) do
    if path:match("%.lua$") then return hs.reload() end
  end
end):start()
hs.alert.show("Hammerspoon config loaded")
