-- Virtual workspaces 1–9 shared by all displays, like AeroSpace's default:
-- each workspace lives on one display and each display shows one. Windows of
-- hidden workspaces are parked off-screen in a bottom corner of their display.
-- The model is plain Lua so it can be tested without hs; fx does the window
-- work, and the hs glue is at the bottom.

local M = {}

local function rect(x, y, w, h) return { x = x, y = y, w = w, h = h } end

-- Frame f moved from display rect `from` to `to` at the same offset from the
-- origin, then clamped to fit (shrunk only if it doesn't).
function M.fit(f, from, to)
  local w, h = math.min(f.w, to.w), math.min(f.h, to.h)
  local x = math.max(to.x, math.min(to.x + f.x - from.x, to.x + to.w - w))
  local y = math.max(to.y, math.min(to.y + f.y - from.y, to.y + to.h - h))
  return rect(x, y, w, h)
end

local function overlap(a, b)
  local w = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
  local h = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
  return w > 0 and h > 0 and w * h or 0
end

-- Top-left for parking a window of f's size in the bottom-right or
-- bottom-left corner of display d with a 1 px sliver left on it, whichever
-- covers less of the other displays. (macOS keeps title bars below the menu
-- bar, so top corners don't work.)
function M.parkPoint(f, d, others)
  local best, least
  for _, x in ipairs({ d.x + d.w - 1, d.x - f.w + 1 }) do
    local p, covered = { x = x, y = d.y + d.h - 1 }, 0
    for _, o in ipairs(others) do covered = covered + overlap(rect(p.x, p.y, f.w, f.h), o) end
    if not least or covered < least then best, least = p, covered end
  end
  return best
end

-- Saved state from an earlier boot is useless: window ids are reused.
function M.restore(saved, boot)
  if type(saved) ~= "table" or saved.boot ~= boot then return { boot = boot } end
  return saved
end

-- State S: ws[1..9] = { display = uuid, home = uuid, windows = { [id] = v },
-- last = id }, shown[uuid] = n, away[uuid] = n, displays[uuid] = { full, usable }.
-- v is true while the window is where it belongs, else its saved frame. home
-- is the display a workspace left when that display went away; away is what
-- such a display showed. Ids are strings so S saves as JSON.
-- fx: frame(id) (nil if gone, hidden, minimized or full screen),
-- place(id, frame or point) → ok, focus(id) → ok, focusDisplay(uuid),
-- connected(uuid), save(S).
function M.model(S, fx)
  for _, k in ipairs({ "ws", "shown", "away", "displays" }) do S[k] = S[k] or {} end
  for n = 1, 9 do S.ws[n] = S.ws[n] or { windows = {} } end
  local m = { state = S }

  local function shownOn(n)
    local d = S.ws[n].display
    return d ~= nil and S.shown[d] == n
  end

  function m.workspaceOf(id)
    for n, w in ipairs(S.ws) do
      if w.windows[id] then return n end
    end
  end

  function m.parked(id)
    local n = m.workspaceOf(id)
    return n ~= nil and not shownOn(n)
  end

  -- The display under f's centre, if any.
  local function displayAt(f)
    local cx, cy = f.x + f.w / 2, f.y + f.h / 2
    for uuid, d in pairs(S.displays) do
      local r = d.full
      if cx >= r.x and cx < r.x + r.w and cy >= r.y and cy < r.y + r.h then return uuid end
    end
  end

  local function hide(id, f, uuid)
    local others = {}
    for u, d in pairs(S.displays) do
      if u ~= uuid then others[#others + 1] = d.full end
    end
    return fx.place(id, M.parkPoint(f, S.displays[uuid].full, others))
  end

  -- Take id out of its workspace; an empty hidden workspace loses its display.
  local function detach(id)
    local n = m.workspaceOf(id)
    if not n then return end
    local w = S.ws[n]
    w.windows[id] = nil
    if w.last == id then w.last = nil end
    if not shownOn(n) and not next(w.windows) then w.display, w.home = nil, nil end
    return n
  end

  -- Park shown workspace n, saving where its windows were.
  local function park(n)
    local w = S.ws[n]
    if S.shown[w.display] == n then S.shown[w.display] = nil end
    for id, v in pairs(w.windows) do
      local f = v == true and fx.frame(id) or v -- a frame means it never left
      if v == true and f ~= true and not displayAt(f) then f = true end -- never save an off-screen frame
      w.windows[id] = f
      if f ~= true then hide(id, f, w.display) end
    end
    if not next(w.windows) then w.display, w.home = nil, nil end
  end

  -- Show hidden workspace n on display uuid, parking what was there. Windows
  -- go back to their saved position; their size is never touched.
  local function show(n, uuid)
    local w = S.ws[n]
    if S.shown[uuid] then park(S.shown[uuid]) end
    w.display, w.home, S.shown[uuid] = uuid, nil, n
    for id, f in pairs(w.windows) do
      if f == true or fx.place(id, { x = f.x, y = f.y }) then w.windows[id] = true end
    end
  end

  local target -- the workspace the last switch focused
  local function focus(n)
    local w = S.ws[n]
    target = n
    if w.last and w.windows[w.last] and fx.focus(w.last) then return end
    for id in pairs(w.windows) do
      if fx.focus(id) then return end
    end
    fx.focusDisplay(w.display)
  end

  -- The display workspace n lives on, unless it's gone (synced or not).
  local function home(n)
    local d = S.ws[n].display
    return d and S.displays[d] and fx.connected(d) and d or nil
  end

  -- ⌃N: focus workspace n; if hidden, show it on its display, or here (the
  -- focused display) if it has none.
  -- Focus the last switch's workspace again: its last window, else the
  -- frontmost one on its display, else the desktop.
  function m.refocus()
    if target and shownOn(target) then focus(target) end
  end

  -- Already shown there, it still focuses n, so a parked window can't keep focus.
  function m.switch(n, here)
    if here and not S.displays[here] then here = S.main end -- just plugged in, not synced yet
    local d = home(n) or here
    if not d then return end
    if not shownOn(n) then show(n, d) end
    focus(n)
    fx.save(S)
  end

  -- ⌥⇧N: move shown window id to workspace n, onto n's display (fitted) if
  -- it has one, then follow it.
  function m.move(id, n)
    local k = m.workspaceOf(id)
    if not k or k == n or not shownOn(k) then return end
    local from = S.ws[k].display
    detach(id)
    local w, to = S.ws[n], home(n) or from
    w.display, w.last = to, id
    local f = fx.frame(id)
    if f and to ~= from then
      f = M.fit(f, S.displays[from].usable, S.displays[to].usable)
      fx.place(id, f)
    end
    w.windows[id] = shownOn(n) or f or true -- a hidden n is shown below
    m.switch(n, from)
  end

  -- A new or unknown window joins the workspace shown on display uuid, the
  -- one under it. A window off every display (uuid nil) that we didn't park
  -- (app relaunch, cascading, a crash mid-switch) is brought back first: a
  -- known one to its saved frame or the centre of its workspace's display,
  -- an unknown one to the centre of `here`.
  function m.join(id, uuid, here)
    local n = m.workspaceOf(id)
    if n and not shownOn(n) then return end -- parked
    if uuid and n then
      S.ws[n].windows[id] = true
      return
    end
    if not uuid then
      if here and not S.displays[here] then here = S.main end
      local f, v, to = fx.frame(id), n and S.ws[n].windows[id], n and home(n) or here
      local d = to and S.displays[to] and S.displays[to].usable
      if not (f and d) then return end
      local p = v ~= true and v and { x = v.x, y = v.y }
        or { x = d.x + math.max(0, (d.w - f.w) / 2), y = d.y + math.max(0, (d.h - f.h) / 2) }
      if not fx.place(id, p) then return end
      if n then
        S.ws[n].windows[id] = true
        return fx.save(S)
      end
      uuid = to
    end
    if S.shown[uuid] then
      S.ws[S.shown[uuid]].windows[id] = true
      fx.save(S)
    end
  end

  function m.remove(id)
    if detach(id) then fx.save(S) end
  end

  -- Drop windows that no longer exist (alive: set of ids).
  function m.prune(alive)
    for _, w in ipairs(S.ws) do
      for id in pairs(w.windows) do
        if not alive[id] then detach(id) end
      end
    end
  end

  -- Focus from anywhere; a parked window brings its workspace back.
  function m.focused(id)
    local n = m.workspaceOf(id)
    if not n then return end
    S.ws[n].last = id
    if shownOn(n) then fx.save(S) else m.switch(n) end
  end

  -- A window that comes back on screen (unminimized, unhidden, or put back by
  -- its app) while its workspace is hidden is parked again.
  function m.revealed(id)
    local n = m.workspaceOf(id)
    local w = n and S.ws[n]
    if not w or shownOn(n) then return end
    local f = fx.frame(id)
    if not f or not displayAt(f) then return end
    if w.windows[id] == true then w.windows[id] = f end
    hide(id, w.windows[id], w.display)
    fx.save(S)
  end

  -- Dragged onto another display: join the workspace shown there.
  function m.moved(id, uuid)
    local n, to = m.workspaceOf(id), S.shown[uuid]
    if not n or not to or to == n or not shownOn(n) then return end
    detach(id)
    S.ws[to].windows[id], S.ws[to].last = true, id
    fx.save(S)
  end

  -- Hidden workspace w now lives on display uuid; its saved frames follow.
  local function rebind(w, uuid, from)
    for id, f in pairs(w.windows) do
      if f ~= true then w.windows[id] = M.fit(f, from, S.displays[uuid].usable) end
    end
    w.display = uuid
  end

  -- Displays changed, and at load. screens: { uuid, full, usable } ordered
  -- left to right, then top to bottom; main: the main display's uuid.
  function m.sync(screens, main, loading)
    local old = S.displays
    S.displays = {}
    for _, s in ipairs(screens) do S.displays[s.uuid] = { full = s.full, usable = s.usable } end
    S.main = main

    -- A display that moved or changed resolution takes its saved frames along.
    for uuid, d in pairs(S.displays) do
      local was = old[uuid] and old[uuid].usable
      if was and (was.x ~= d.usable.x or was.y ~= d.usable.y or was.w ~= d.usable.w or was.h ~= d.usable.h) then
        for _, w in ipairs(S.ws) do
          if w.display == uuid then rebind(w, uuid, was) end
        end
      end
    end

    -- A gone display's workspaces move to main, parked; they remember it.
    for uuid, n in pairs(S.shown) do
      if not S.displays[uuid] then S.shown[uuid], S.away[uuid] = nil, n end
    end
    for _, w in ipairs(S.ws) do
      if w.display and not S.displays[w.display] then
        local from = (old[w.display] or S.displays[main]).usable
        w.home = w.home or w.display
        rebind(w, main, from)
        for id, f in pairs(w.windows) do -- shown ones: macOS moved them off it, or will
          local live = f == true and fx.frame(id)
          if live and not displayAt(live) then live = M.fit(live, from, S.displays[main].usable) end
          if live then w.windows[id] = live end
        end
      end
    end

    -- A display that's back gets its workspaces back, parked.
    for _, w in ipairs(S.ws) do
      if w.home and S.displays[w.home] then
        rebind(w, w.home, S.displays[w.display].usable)
        w.home = nil
      end
    end

    -- A display without a workspace shows what it showed before it went
    -- away, else the first workspace without a display, else the first
    -- hidden one, moved over.
    for _, s in ipairs(screens) do
      if not S.shown[s.uuid] then
        local pick = S.away[s.uuid]
        S.away[s.uuid] = nil
        if not (pick and S.ws[pick].display == s.uuid and not shownOn(pick)) then pick = nil end
        for n, w in ipairs(S.ws) do
          if not pick and not w.display then pick = n end
        end
        for n, w in ipairs(S.ws) do
          if not pick and not shownOn(n) then
            pick = n
            rebind(w, s.uuid, S.displays[w.display].usable)
          end
        end
        if pick then show(pick, s.uuid) end
      end
    end

    -- Park everything hidden: corners may have changed. At load, windows put
    -- back on screen at the last quit have their frames refreshed first.
    for n, w in ipairs(S.ws) do
      if w.display and not shownOn(n) then
        for id, f in pairs(w.windows) do
          local live = loading and fx.frame(id)
          if live and displayAt(live) then f, w.windows[id] = live, live end
          if f ~= true then hide(id, f, w.display) end
        end
      end
    end
    fx.save(S)
  end

  -- Every parked window back where it was; S is untouched, so a load parks them again.
  function m.unparkAll()
    for n, w in ipairs(S.ws) do
      if not shownOn(n) then
        for id, f in pairs(w.windows) do
          if f ~= true then fx.place(id, { x = f.x, y = f.y }) end
        end
      end
    end
  end

  return m
end

if not hs then return M end -- tests stop here

local function plain(r) return { x = r.x, y = r.y, w = r.w, h = r.h } end
local function idOf(win) return win and win:id() and tostring(win:id()) end
-- Native full-screen and non-standard windows are left alone.
local function managed(win) return win ~= nil and idOf(win) ~= nil and win:isStandard() and not win:isFullScreen() end

-- One id → window map per operation.
local byId
local function window(id)
  if not byId then
    byId = {}
    for _, win in ipairs(hs.window.allWindows()) do
      if idOf(win) then byId[idOf(win)] = win end
    end
  end
  return byId[id]
end

-- Run fn as one operation; log and alert if it fails.
local function op(fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    byId = nil
    if not ok then
      print("workspaces: " .. tostring(err))
      hs.alert.show("Workspaces failed, see the Hammerspoon console")
    end
  end
end


-- Mouse to the window centre, unless already inside or a button is held.
local function follow(win)
  for _, down in pairs(hs.eventtap.checkMouseButtons()) do
    if down then return end
  end
  local frame = win:frame()
  if not hs.geometry.new(hs.mouse.absolutePosition()):inside(frame) then
    hs.mouse.absolutePosition(frame.center)
  end
end

local model

-- After a switch focuses a window, parked windows macOS focuses on the way
-- are ignored until that window's focus event arrives, for 0.5 s at most.
-- Then, if a parked window has the keyboard anyway, the switch's workspace
-- is focused again.
local expect, expectCheck
local function switching()
  return expect ~= nil and hs.timer.secondsSinceEpoch() < expect.deadline
end
local rechecking
local function focusWindow(win)
  local current = hs.window.focusedWindow()
  if idOf(win) and current and idOf(current) == idOf(win) then return end
  expect = { id = idOf(win), deadline = hs.timer.secondsSinceEpoch() + 0.5 }
  win:focus()
  if rechecking then return end -- one check per switch, no loop
  if expectCheck then expectCheck:stop() end
  expectCheck = hs.timer.doAfter(0.5, op(function()
    expect = nil
    local now = hs.window.focusedWindow()
    if not (managed(now) and M.parked(now)) then return end
    rechecking = true
    local ok, err = pcall(model.refocus)
    rechecking = false
    if not ok then error(err) end
  end))
end

-- The display under the window's centre; nil when it's off every display.
local function displayOf(win)
  local centre = win:frame().center
  for _, s in ipairs(hs.screen.allScreens()) do
    if centre:inside(s:fullFrame()) then return s:getUUID() end
  end
end

local fx = {
  frame = function(id)
    local win = window(id)
    if managed(win) and win:isVisible() then return plain(win:frame()) end
  end,
  -- Move to a point, or set a frame when its size differs; ok if it moved.
  place = function(id, f)
    local win = window(id)
    if not win then return false end
    local before = win:frame()
    if f.w and (f.w ~= before.w or f.h ~= before.h) then win:setFrame(f, 0) else win:setTopLeft(f) end
    local after = win:frame()
    return after.x ~= before.x or after.y ~= before.y or (after.x == f.x and after.y == f.y)
  end,
  focus = function(id)
    local win = window(id)
    if not managed(win) or win:isMinimized() then return false end
    focusWindow(win)
    follow(win)
    return true
  end,
  -- An empty workspace: focus the frontmost window still on its display, else
  -- the desktop, so no parked window keeps the keyboard.
  focusDisplay = function(uuid)
    for _, win in ipairs(hs.window.orderedWindows()) do
      if managed(win) and not M.parked(win) and displayOf(win) == uuid then
        focusWindow(win)
        return follow(win)
      end
    end
    local desktop, screen = hs.window.desktop(), hs.screen.find(uuid)
    if desktop then focusWindow(desktop) end
    if screen then hs.mouse.absolutePosition(screen:frame().center) end
  end,
  connected = function(uuid) return hs.screen.find(uuid) ~= nil end,
  save = function(S) hs.settings.set("workspaces", hs.json.encode(S)) end,
}

-- Parked by us, or off every display anyway.
function M.parked(win) return (model ~= nil and model.parked(idOf(win))) or not displayOf(win) end

local function screens()
  local list = {}
  for _, s in ipairs(hs.screen.allScreens()) do
    list[#list + 1] = { uuid = s:getUUID(), full = plain(s:fullFrame()), usable = plain(s:frame()) }
  end
  table.sort(list, function(a, b)
    return a.full.x < b.full.x or (a.full.x == b.full.x and a.full.y < b.full.y)
  end)
  return list
end
local function main() return hs.screen.primaryScreen():getUUID() end

-- The focused window's display, else the one under the mouse.
local function here()
  local win = hs.window.focusedWindow()
  if managed(win) and not M.parked(win) then return win:screen():getUUID() end
  local screen = hs.mouse.getCurrentScreen()
  return screen and screen:getUUID()
end

local function join(win)
  if managed(win) then model.join(idOf(win), displayOf(win), here()) end
end
-- After a sync: known windows macOS left on another display join it.
local function joinAll()
  for _, win in ipairs(hs.window.allWindows()) do
    local uuid = managed(win) and displayOf(win)
    if uuid and model.workspaceOf(idOf(win)) then model.moved(idOf(win), uuid) else join(win) end
  end
end

local boot = hs.execute("sysctl -n kern.boottime"):match("sec = (%d+)")
local function start(saved)
  model = M.model(M.restore(saved, boot), fx)
  local alive = {}
  for _, win in ipairs(hs.window.allWindows()) do
    if managed(win) then alive[idOf(win)] = win end
  end
  model.prune(alive)
  model.sync(screens(), main(), true)
  joinAll()
end

M.switch = op(function(n) model.switch(n, here()) end)
M.move = op(function(n)
  local win = hs.window.focusedWindow()
  if managed(win) then model.move(idOf(win), n) end
end)
M.shutdown = op(function() if model then model.unparkAll() end end)
-- Every window back on-screen, then start over (`space unpark`).
M.unpark = op(function()
  if model then model.unparkAll() end
  hs.settings.clear("workspaces")
  start(nil)
end)
M.paused = false -- set while Mission Control is open: no mouse-follow

local events = hs.window.filter
M.filter = hs.window.filter.new(true) -- kept on M so it isn't collected
M.filter:subscribe({ events.windowCreated, events.windowUnfullscreened }, op(join))
M.filter:subscribe({ events.windowUnminimized, events.windowVisible }, op(function(win)
  if managed(win) then model.revealed(idOf(win)) end
end))
M.filter:subscribe({ events.windowDestroyed, events.windowFullscreened }, op(function(win)
  if idOf(win) then model.remove(idOf(win)) end
end))
M.filter:subscribe(events.windowFocused, op(function(win)
  if not managed(win) then return end
  local id, busy = idOf(win), switching()
  if busy and id == expect.id then
    expect = nil
  elseif busy and M.parked(win) then
    return
  end
  join(win)
  model.focused(id)
  -- Follow focus with the mouse; a switch does that itself.
  if not busy and not M.paused and not M.parked(win) then follow(win) end
end))
M.filter:subscribe(events.windowMoved, op(function(win)
  local uuid = managed(win) and displayOf(win)
  local n = uuid and model.workspaceOf(idOf(win))
  -- Windows macOS moves off an unplugged display are left to the sync.
  if n and fx.connected(model.state.ws[n].display) then model.moved(idOf(win), uuid) end
end))

-- Debounced: sleep and wake make displays flap.
local resync = hs.timer.delayed.new(2.5, op(function()
  model.sync(screens(), main())
  joinAll()
end))
M.screenWatcher = hs.screen.watcher.new(function() resync:start() end):start()

-- Last, so a load error still leaves shutdown, `space unpark` and the watchers working.
local ok, saved = pcall(hs.json.decode, hs.settings.get("workspaces") or "{}")
op(start)(ok and saved or nil)

return M
