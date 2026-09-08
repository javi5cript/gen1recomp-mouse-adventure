return function(mod, movement)
  local Game = require("src.core.Game")
  local Transition = require("src.render.Transition")
  local makeTargets = assert((loadstring or load)(assert(mod:read("mouse_targets.lua")),
    "@click_to_move/mouse_targets.lua"))()
  local targets = makeTargets(mod)
  local pending, pulse, held, capture, frame, dock
  local hoverX, hoverY
  local gameHoverX, gameHoverY
  local notice, noticeTicks
  local deferred, wheel, wheelRemainder, wheelState
  local observedRenderer, presentedUI
  local dockFonts, dockDPI = {}, nil
  local insideGame = false
  local dockPage, helpPage = 1, 0
  local buttons = {}
  local api = {}

  local function active() return movement.enabled("mouse_ui") end
  local function top(game) return movement.top(game) end
  local function sameContext(action, game)
    return action and action.state and action.state == top(game)
      and action.mode == action.state.mode and action.phase == action.state.phase
  end
  local function contains(rect, x, y)
    return rect and type(x) == "number" and type(y) == "number"
      and x >= rect.x and y >= rect.y and x < rect.x + rect.w and y < rect.y + rect.h
  end
  local function tell(text)
    notice, noticeTicks = text, 240
  end
  api.tell = tell
  local function releaseTokens(tokens)
    for _, token in ipairs(tokens or {}) do mod.input:release(token) end
  end
  local function stopHold(cancelled)
    if held and cancelled and held.catching then
      held.catching.catchInput:reset("mouse_cancelled", true)
    end
    releaseTokens(held and held.tokens)
    held = nil
  end
  function api.reset()
    releaseTokens(pulse)
    stopHold(true)
    pending, pulse, capture, frame, deferred, wheel = nil, nil, nil, nil, nil, nil
    wheelRemainder, wheelState, insideGame = 0, nil, false
    presentedUI = nil
    notice, noticeTicks, gameHoverX, gameHoverY = nil, nil, nil, nil
    buttons = {}
  end
  local function busy(game)
    local state = top(game)
    if not state or getmetatable(state) == Transition then return true end
    if state.isOverworld then
      return state.transitioning or state.player.inputLocked
        or (state.runner and state.runner:isRunning())
        or #(state.scriptMoves or {}) > 0 or state.engaging or state.emote
        or (state.hopLand or 0) > 0 or state.teleportOut or state.flyFade
        or state.flyAnim or state.flyArrive or state.spinArrive
        or state.holeFall or state.holeArrive
    end
    return false
  end
  local function foreignInput(game)
    for _, key in ipairs({"up","down","left","right","a","b","start","select"}) do
      if game.input:isDown(key) then
        local sources = game.input.sources and game.input.sources[key]
        if not sources then return true end
        for source in pairs(sources) do
          if type(source) ~= "string" or not source:match("^mod:click_to_move:") then return true end
        end
      end
    end
    return false
  end
  local function schedule(game, action)
    movement.cancel()
    stopHold(true)
    if busy(game) then tell("Wait for the current action to finish."); return end
    if foreignInput(game) then tell("Release keyboard/controller buttons first."); return end
    if pending then return end
    wheel = nil
    action.state, action.mode, action.phase = top(game), top(game).mode, top(game).phase
    action.ticks, action.time = 0, 0
    pending = action
  end
  local function startDeferred(game)
    local gesture = deferred
    deferred, capture = nil, nil
    if gesture and gesture.action.valid() and not busy(game) and not foreignInput(game) then
      movement.beginSteering(game, gesture.ev)
    end
  end
  local function claim(ev)
    capture = { id = ev.id, source = ev.source, button = ev.button }
  end
  local function owns(ev)
    return capture and ev.id == capture.id and ev.source == capture.source
  end

  local function observeRenderer(game)
    local renderer = game.renderer
    if not renderer or observedRenderer == renderer then return end
    observedRenderer = renderer
    if type(renderer.endFrame) ~= "function" then return end
    local innerEnd = renderer.endFrame
    function renderer:endFrame(...)
      local drawn
      if type(self.frameRects) == "function" then
        local r, state = self:frameRects(), top(game)
        local anchors = {}
        for i, a in ipairs(self.uiAnchors or {}) do
          local copy = {}
          for key, value in pairs(a) do copy[key] = value end
          anchors[i] = copy
        end
        local wide = Game.wideBattleInStack and Game.wideBattleInStack(game.stack)
        local offset = wide and wide.uiSize and not
          (state and state.isWideBattleLayout and state:isWideBattleLayout())
          and math.floor((r.uiw-160)/2) or 0
        drawn = {renderer=self, state=state, rect=r, anchors=anchors, offset=offset}
      end
      local result = innerEnd(self, ...)
      presentedUI = drawn
      return result
    end
  end
  api.observe = observeRenderer

  -- endFrame clears worldActive, which changes frameRects' zoom-dependent UI
  -- scale. Use the transform that actually drew this frame, not the next one.
  local function project(rect, drawn)
    local r = drawn.rect
    rect = {x=rect.x+drawn.offset, y=rect.y, w=rect.w, h=rect.h}
    local ox, oy = r.uox, r.uoy
    for i = #drawn.anchors, 1, -1 do
      local a = drawn.anchors[i]
      if rect.x >= a.x and rect.y >= a.y
          and rect.x + rect.w <= a.x + a.w and rect.y + rect.h <= a.y + a.h then
        local dx, dy = r.uox + a.x * r.Ux, r.uoy + a.y * r.Uy
        if a.anchor == "bottom" then
          dy = r.vuy + r.vuh - (r.uih - a.y) * r.Uy
        elseif a.anchor == "top" then
          dy = r.vuy + a.y * r.Uy
        elseif a.anchor == "topright" then
          dx, dy = r.vux + r.vuw - (r.uiw - a.x) * r.Ux, r.vuy + a.y * r.Uy
        end
        if a.windowClamped then
          dx = math.max(r.vux, math.min(math.max(r.vux, r.vux + r.vuw - a.w*r.Ux), dx))
          dy = math.max(r.vuy, math.min(math.max(r.vuy, r.vuy + r.vuh - a.h*r.Uy), dy))
        end
        ox, oy = dx - a.x*r.Ux, dy - a.y*r.Uy
        break
      end
    end
    local x, y = math.max(r.vux, ox + rect.x*r.Ux), math.max(r.vuy, oy + rect.y*r.Uy)
    local x2 = math.min(r.vux + r.vuw, ox + (rect.x + rect.w)*r.Ux)
    local y2 = math.min(r.vuy + r.vuh, oy + (rect.y + rect.h)*r.Uy)
    return { x = x, y = y, w = math.max(0, x2-x), h = math.max(0, y2-y) }
  end

  mod.hooks:wrap("input.step", function(next, game, dt)
    releaseTokens(pulse); pulse = nil
    if noticeTicks then
      noticeTicks = noticeTicks - 1
      if noticeTicks <= 0 then notice, noticeTicks = nil, nil end
    end
    if not active() then api.reset(); return next(game, dt) end
    local elapsed = dt / math.max(0.01, game.logicSpeed and game:logicSpeed() or 1)
    if foreignInput(game) or (wheelState and not wheelState.valid()) then
      wheel, wheelState, wheelRemainder = nil, nil, 0
    end
    if deferred then
      deferred.time = deferred.time + elapsed
      if busy(game) or foreignInput(game) or not deferred.action.valid()
          or not movement.deferredInteraction() then
        deferred = nil
      elseif deferred.time >= 0.18 then startDeferred(game) end
    end
    if held and (not sameContext(held, game) or busy(game) or foreignInput(game)
        or not movement.enabled("action_bar")) then stopHold(true) end
    if held and held.repeatButton and not top(game).repeatState then
      held.ticks = held.ticks + 1
      if held.ticks >= 24 and held.ticks % 7 == 0 then
        mod.input:tap(game, held.repeatButton)
      end
    end
    if pending then
      local action = pending
      action.ticks = action.ticks + 1
      action.time = (action.time or 0) + elapsed
      if not sameContext(action, game) or busy(game) or foreignInput(game) then
        pending = nil
      elseif action.buffered and (not movement.enabled("dialogue_buffer") or action.time > 0.35) then
        pending = nil
        tell("Early click expired. Click again when ready.")
      elseif action.ticks > 120 then
        pending = nil
        tell("Action cancelled: the player has not stopped.")
      elseif not (action.state.isOverworld and action.state.player.moving) then
        if action.valid and not action.valid() then
          pending = nil
        elseif action.ready and not action.ready() then
          -- Readiness delays a buffered click; validity still cancels it.
        elseif action.direction and action.state.player.facing ~= action.direction then
          -- A neutral native poll arms an in-place turn. B brakes Cycling
          -- Road during that poll; neither facing nor position is mutated.
          local button = action.state.player.turnArmed and action.direction or "b"
          pulse = { mod.input:press(game, button) }
        else
          pending = nil
          if action.select then action.select() end
          if action.run then action.run(game) end
          if action.button then
            pulse = { mod.input:press(game, action.button) }
          end
        end
      end
    end
    if wheel then
      if not movement.enabled("wheel_lists") or pending or held or not sameContext(wheel, game)
          or busy(game) or foreignInput(game) or not wheel.valid() then
        wheel = nil
      elseif wheel.neutral then
        wheel.neutral = false
      else
        pulse = {mod.input:press(game, wheel.button)}
        wheel.count, wheel.neutral = wheel.count-1, true
        if wheel.count <= 0 then wheel = nil end
      end
    end
    return next(game, dt)
  end, 2000)

  mod.hooks:wrap("render.viewport", function(next, ctx)
    local available = next(ctx)
    dock = nil
    if not active() or not movement.enabled("action_bar") then return available end
    local base = available or { x=0, y=0, width=ctx.width, height=ctx.height }
    local size = movement.option("dock_size")
    local cellH = size == "large" and 48 or size == "comfortable" and 40 or 32
    local minW = size == "large" and 140 or size == "comfortable" and 120 or 100
    local cols = math.max(2, math.min(6, math.floor(base.width/minW)))
    local small = base.width < 300 or base.height < 240
    local rows = math.max(1, math.min(math.ceil(12/cols), math.floor((base.height*0.45-48)/cellH)))
    local height = small and math.min(40, base.height*0.25) or rows*cellH+48
    dock = { x=base.x or 0, y=(base.y or 0)+base.height-height, w=base.width, h=height,
      cols=cols, rows=rows, cellH=cellH, small=small,
      fontSize=size == "large" and 20 or size == "comfortable" and 18 or 16 }
    buttons = {}
    local result = {}
    for k, v in pairs(base) do result[k] = v end
    result.height, result.capture = base.height-height, true
    return result
  end, -2000)

  local function wilds()
    local found = mod.find("overworld_wild_spawns")
    local exports = found and found.exports
    if exports and exports.overworldCatchingEnabled and exports.overworldCatchingEnabled() then
      local c = exports.catching
      if c and c.CatchBindings and c.catchInput then return c end
    end
  end
  local function startHold(game, btn, catching)
    movement.cancel()
    pending = nil
    stopHold(true)
    if busy(game) then tell("Wait for the current action to finish."); return end
    if foreignInput(game) then tell("Release keyboard/controller buttons first."); return end
    if catching and top(game).player.moving then
      tell("Stop moving before throwing a ball."); return
    end
    held = { state=top(game), mode=top(game).mode, phase=top(game).phase,
      tokens={}, ticks=0, catching=catching }
    local keys = { btn }
    if catching then
      local combo = catching.CatchBindings.throwCombo(catching.mod)
      if not combo then held=nil; tell("Enable a Wilds throw-button combo in MODS."); return end
      keys = { combo.modifier, combo.action }
    else
      held.repeatButton = btn
    end
    for _, key in ipairs(keys) do held.tokens[#held.tokens+1] = mod.input:press(game, key) end
  end
  local function dockActions(game)
    local state = top(game)
    local naming = state and type(state.grid) == "function" and type(state.glyphs) == "table"
    local rows = {
      { label=naming and "TYPE / A" or (state and state.isOverworld and "INTERACT / A" or "CONFIRM / A"),
        button="a" }, { label=naming and "DELETE / B" or "BACK / B", button="b" },
      { label=naming and "DONE" or "MENU", button="start" },
      { label=naming and "CASE" or "SELECT", button="select" },
      { label="UP", button="up", hold=true }, { label="DOWN", button="down", hold=true },
      { label="LEFT", button="left", hold=true }, { label="RIGHT", button="right", hold=true },
      { label="MODS", run=function(g) g:keypressed("f10") end },
    }
    rows[#rows+1] = { label="HELP", localAction=function()
      local help = {
        "Hold to move, point to steer. Right-click cancels.",
        "Click nearby objects. MENU opens Save, Bag and Party.",
        "Unknown screen? Use dock arrows, CONFIRM and BACK.",
        "Optional wheel, early click and precision controls: MODS.",
      }
      helpPage = helpPage % #help + 1
      tell(help[helpPage])
    end }
    local catching = state and state.isOverworld and wilds()
    rows[#rows+1] = {label="HOLD: THROW", catching=catching, disabled=not catching,
      hint="Throw requires Wilds overworld catching."}
    rows[#rows+1] = {label="NEXT BALL", disabled=not catching,
      hint="Ball cycling requires Wilds overworld catching.",
      run=function(g) catching:cycleSelectedBall(g, 1) end}
    return rows
  end
  local function contextHint(game)
    if pending and pending.buffered then return "Click buffered: waiting for this prompt." end
    if deferred then return "Release to interact; keep holding or drag to move." end
    if busy(game) then return "Waiting for the current action / animation." end
    for _, button in ipairs(buttons) do
      if contains(button.rect, hoverX, hoverY) and button.action.disabled then return button.action.hint end
    end
    local world = movement.hint(game, insideGame and gameHoverX or nil, insideGame and gameHoverY or nil)
    if world then return world end
    if sameContext(frame, game) then
      if frame.hint then return frame.hint end
      for _, entry in ipairs(frame.targets) do
        if contains(entry.rect, gameHoverX, gameHoverY) then
          return entry.action.hint or "Choose: click to confirm."
        end
      end
      if #frame.targets > 0 then return "Click a choice; right-click to go back." end
    end
    return "No direct-click adapter. Use dock arrows / CONFIRM."
  end
  local function fitted(text, font, width, scale)
    if font:getWidth(text)*scale <= width then return text end
    while #text > 0 and font:getWidth(text .. "...")*scale > width do text = text:sub(1, -2) end
    return #text > 0 and text .. "..." or ""
  end
  local function dockFont(size)
    local g = love.graphics
    local dpi = g.getDPIScale()
    if dpi ~= dockDPI then
      for _, font in pairs(dockFonts) do font:release() end
      dockFonts, dockDPI = {}, dpi
    end
    if not dockFonts[size] then dockFonts[size] = g.newFont(size, "normal", dpi) end
    g.setFont(dockFonts[size])
    return dockFonts[size]
  end
  local function dockText(text, x, y)
    love.graphics.print(text, math.floor(x*dockDPI+0.5)/dockDPI,
      math.floor(y*dockDPI+0.5)/dockDPI)
  end
  mod.hooks:wrap("render.window", function(next, game, ctx)
    local result = next(game, ctx)
    buttons = {}
    if not dock or not active() then return result end
    local g = love.graphics
    g.push("all"); g.origin(); g.setShader(); g.setScissor(); g.setCanvas()
    -- Never resize the game's current font texture: rasterize dock text at
    -- its own readable size and draw it at native scale.
    local font = dockFont(16)
    local rows = dockActions(game)
    local cols, cellH = dock.cols, dock.cellH
    local cellW = dock.w/cols
    local capacity = cols*dock.rows
    local pages = math.ceil(#rows/capacity)
    dockPage = math.min(dockPage, pages)
    g.setColor(0.04, 0.055, 0.08, 1); g.rectangle("fill", dock.x, dock.y, dock.w, dock.h)
    if dock.small then
      g.setColor(0.94, 0.96, 1, 1)
      dockText(fitted("Enlarge window for mouse controls.", font, dock.w-12, 1), dock.x+6, dock.y+6)
      g.pop()
      return result
    end
    local function button(rect, action, fontSize)
      local font = dockFont(fontSize)
      local hover = contains(rect, hoverX, hoverY)
      g.setColor(hover and 0.18 or 0.1, hover and 0.3 or 0.16, hover and 0.38 or 0.22, 1)
      g.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 4, 4)
      g.setColor(0.4, 0.7, 0.78, action.disabled and 0.3 or 1)
      g.rectangle("line", rect.x, rect.y, rect.w, rect.h, 4, 4)
      g.setColor(0.94, 0.96, 1, action.disabled and 0.4 or 1)
      local label = fitted(action.label, font, rect.w-8, 1)
      dockText(label, rect.x+(rect.w-font:getWidth(label))/2,
        rect.y+(rect.h-font:getHeight())/2)
      buttons[#buttons+1] = {rect=rect, action=action, state=top(game),
        mode=top(game) and top(game).mode, phase=top(game) and top(game).phase}
    end
    for slot = 1, capacity do
      local i = (dockPage-1)*capacity+slot
      local action = rows[i]
      if not action then break end
      local rect = {x=dock.x+((slot-1)%cols)*cellW+3,
        y=dock.y+math.floor((slot-1)/cols)*cellH+3, w=cellW-6, h=cellH-5}
      button(rect, action, dock.fontSize)
    end
    g.setColor(0.65, 0.78, 0.84, 1)
    local hint = notice or contextHint(game)
    font = dockFont(16)
    dockText(fitted(hint, font, dock.w-12, 1), dock.x+6, dock.y+dock.h-46)
    local key = movement.enabled("guide_hotkey") and movement.option("guide_key"):upper() .. ": " or ""
    button({x=dock.x+dock.w-137,y=dock.y+dock.h-25,w=131,h=22},
      {label=key .. "GUIDE " .. (movement.guideVisible() and "ON" or "OFF"),
        localAction=function()
          local _, message = movement.toggleGuide(game)
          tell(message)
        end}, 16)
    if pages > 1 then
      button({x=dock.x+6,y=dock.y+dock.h-25,w=104,h=22},
        {label="MORE " .. dockPage .. "/" .. pages, localAction=function()
          dockPage = dockPage % pages+1
          buttons = {}
        end}, 16)
    else
      g.setColor(0.65, 0.78, 0.84, 1)
      dockText(fitted("Hold: move | Click: choose | Right: back | MENU", font, dock.w-155, 1),
        dock.x+6, dock.y+dock.h-22)
    end
    g.pop()
    return result
  end, 2000)

  -- The dock lives outside the game viewport. Existing native/mod mouse
  -- handlers keep first refusal everywhere else.
  mod.hooks:wrap("input.pointer", function(next, game, ev)
    hoverX, hoverY = ev.x, ev.y
    gameHoverX, gameHoverY = ev.gameX, ev.gameY
    insideGame = ev.insideGame == true
    if ev.phase == "pressed" then wheel, wheelRemainder, wheelState = nil, 0, nil end
    if ev.phase == "pressed" and ev.source == "mouse" and ev.button == 2 and deferred then
      deferred, pending, capture = nil, nil, nil
      return true
    end
    if ev.phase == "pressed" and ev.source == "mouse" and ev.button == 2 and held then
      stopHold(true)
      pending = nil
      return true
    end
    if owns(ev) then
      if ev.phase == "cancelled" then api.reset(); return true end
      if ev.phase == "released"
          and (ev.source == "touch" or ev.button == capture.button) then
        if deferred then
          local action = deferred.action
          deferred = nil
          if ev.insideGame and action.valid() then schedule(game, action) end
        end
        stopHold(not contains(dock, ev.x, ev.y))
        capture = nil
        return true
      end
      if ev.phase == "moved" then
        if deferred then
          if not ev.insideGame then
            deferred = nil
          else
            deferred.ev = ev
            if type(ev.gameX) ~= "number" or type(ev.gameY) ~= "number"
                or ev.gameX ~= ev.gameX or ev.gameY ~= ev.gameY then
              deferred = nil
              tell("Gesture cancelled: invalid pointer coordinates.")
            elseif (ev.gameX-deferred.x)^2+(ev.gameY-deferred.y)^2 >= 36 then startDeferred(game) end
          end
        end
        if held and not contains(dock, ev.x, ev.y) then stopHold(true) end
        return true
      end
    end
    if ev.phase == "cancelled" then api.reset() end
    if active() and movement.enabled("action_bar")
        and ev.phase == "pressed" and contains(dock, ev.x, ev.y) then
      movement.cancel()
      if capture then return true end
      claim(ev)
      if ev.source == "mouse" and ev.button == 2 then
        schedule(game, {button="b"}); return true
      end
      if ev.source == "touch" or ev.button == 1 then
        for _, button in ipairs(buttons) do
          if sameContext(button, game) and contains(button.rect, ev.x, ev.y) then
            local a = button.action
            if a.disabled then tell(a.hint)
            elseif a.localAction then a.localAction()
            elseif a.hold or a.catching then startHold(game, a.button, a.catching)
            else schedule(game, a) end
            break
          end
        end
      end
      return true
    end
    return next(game, ev)
  end, 2000)

  mod.hooks:wrap("render.hud", function(next, game, vp)
    local result = next(game, vp)
    frame = nil
    observeRenderer(game)
    local drawn = presentedUI
    presentedUI = nil
    if not active() or not game.renderer.frameRects then return result end
    local state = top(game)
    if not state then return result end
    if not drawn then
      if type(game.renderer.endFrame) == "function" then return result end
      drawn = {renderer=game.renderer, state=state, rect=game.renderer:frameRects(),
        anchors=game.renderer.uiAnchors or {}, offset=0}
    end
    if drawn.renderer ~= game.renderer or drawn.state ~= state then return result end
    local entries, dialogue = targets.collect(game, state)
    frame = { state=state, mode=state.mode, phase=state.phase, targets={}, dialogue=dialogue,
      hint=entries.hint, waitAction=entries.waitAction }
    for _, entry in ipairs(entries) do
      if entry.space ~= "window" then entry.rect = project(entry.rect, drawn) end
      frame.targets[#frame.targets+1] = entry
    end
    for _, entry in ipairs(frame.targets) do
      if contains(entry.rect, gameHoverX, gameHoverY) then
        local g, r = love.graphics, entry.rect
        g.push("all"); g.origin(); g.setShader(); g.setScissor()
        g.setColor(0.15, 0.85, 0.95, 0.9)
        g.rectangle("line", r.x+1, r.y+1, math.max(0, r.w-2), math.max(0, r.h-2))
        g.pop()
        break
      end
    end
    return result
  end, -50)

  mod.hooks:wrap("input.pointer", function(next, game, ev)
    if not active() or ev.phase ~= "pressed" or not ev.insideGame then return next(game, ev) end
    if ev.source == "mouse" and ev.button == 2 then
      if movement.steering() or (pending and pending.direction) then
        movement.cancel()
        pending = nil
      else pending, wheel = nil, nil; schedule(game, {button="b"}) end
      claim(ev)
      return true
    end
    if not (ev.source == "touch" or ev.button == 1) then return next(game, ev) end
    if capture then return true end
    local interaction = movement.interaction(game, ev)
    if interaction then
      claim(ev)
      if movement.deferredInteraction() and movement.enabled("enabled") and not busy(game) then
        deferred = {action=interaction, ev=ev, x=ev.gameX, y=ev.gameY, time=0}
      else schedule(game, interaction) end
      return true
    end
    if sameContext(frame, game) then
      if frame.waitAction and movement.enabled("dialogue_buffer") then
        claim(ev); schedule(game, frame.waitAction); return true
      end
      for _, entry in ipairs(frame.targets) do
        if contains(entry.rect, ev.gameX, ev.gameY) then
          claim(ev); schedule(game, entry.action); return true
        end
      end
      if frame.dialogue then
        claim(ev); schedule(game, frame.dialogue); return true
      end
    end
    if top(game) and top(game).isOverworld then return next(game, ev) end
    -- An unrecognised menu is not a blind A click. Use the visible action
    -- bar rather than accidentally confirming a destructive selection.
    return next(game, ev)
  end, -50)

  -- No wheel hook exists in API 2. Preserve the existing handler first, and
  -- step aside if it consumes input or changes the selected list/row.
  local innerWheel = Game.wheelmoved
  function Game:wheelmoved(dx, dy, ...)
    local s = top(self)
    local valid, mapping
    if active() and movement.enabled("wheel_lists") then valid, mapping = targets.scroll(self, s) end
    local index, scroll = s and s.index, s and s.scroll
    local result
    if innerWheel then result = innerWheel(self, dx, dy, ...) end
    if result or not valid or not valid() or s.index ~= index or s.scroll ~= scroll
        or not insideGame or capture or pending or held or foreignInput(self)
        or type(dy) ~= "number" or dy ~= dy or math.abs(dy) == math.huge then
      wheel, wheelRemainder, wheelState = nil, 0, nil
      return result
    end
    if not wheelState or wheelState.state ~= s or not wheelState.valid() then
      wheelRemainder, wheelState = 0, {state=s,valid=valid}
    end
    wheelRemainder = math.max(-6, math.min(6, wheelRemainder+dy))
    local count = math.floor(math.abs(wheelRemainder))
    if count > 0 then
      local upward = wheelRemainder > 0
      local direction = upward and "up" or "down"
      local button = mapping and mapping[direction] or direction
      wheelRemainder = wheelRemainder+(upward and -count or count)
      if wheel and sameContext(wheel, self) and wheel.button == button then
        wheel.count = math.min(6, wheel.count+count)
      else
        wheel = {state=s, mode=s.mode, phase=s.phase, valid=valid, button=button, count=count,
          neutral=pulse ~= nil}
      end
    end
    return true
  end
  return api
end
