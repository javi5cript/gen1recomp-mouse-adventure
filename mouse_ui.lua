return function(mod, movement)
  local Transition = require("src.render.Transition")
  local makeTargets = assert((loadstring or load)(assert(mod:read("mouse_targets.lua")),
    "@click_to_move/mouse_targets.lua"))()
  local targets = makeTargets(mod)
  local pending, pulse, held, capture, frame, dock
  local hoverX, hoverY
  local gameHoverX, gameHoverY
  local notice, noticeTicks
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
    pending, pulse, capture, frame = nil, nil, nil, nil
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
    if pending then return end
    action.state, action.mode, action.phase = top(game), top(game).mode, top(game).phase
    action.ticks = 0
    pending = action
  end
  local function claim(ev)
    capture = { id = ev.id, source = ev.source, button = ev.button }
  end
  local function owns(ev)
    return capture and ev.id == capture.id and ev.source == capture.source
  end

  -- Read the renderer's actual UI transforms, including independently
  -- anchored dialogue/choice boxes. World zoom is not a UI scale.
  local function project(rect, renderer)
    local r = renderer:frameRects()
    local ox, oy = r.uox, r.uoy
    for i = #(renderer.uiAnchors or {}), 1, -1 do
      local a = renderer.uiAnchors[i]
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
      if not sameContext(action, game) or busy(game) or foreignInput(game) then
        pending = nil
      elseif action.ticks > 120 then
        pending = nil
        tell("Action cancelled: the player has not stopped.")
      elseif not (action.state.isOverworld and action.state.player.moving) then
        if action.valid and not action.valid() then
          pending = nil
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
    return next(game, dt)
  end, 2000)

  mod.hooks:wrap("render.viewport", function(next, ctx)
    local available = next(ctx)
    dock = nil
    if not active() or not movement.enabled("action_bar") then return available end
    local base = available or { x=0, y=0, width=ctx.width, height=ctx.height }
    local height = math.min(100, math.floor(base.height * 0.24))
    dock = { x=base.x or 0, y=(base.y or 0)+base.height-height, w=base.width, h=height }
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
    local catching = state and state.isOverworld and wilds()
    if catching then
      rows[#rows+1] = { label="HOLD: THROW", catching=catching }
      rows[#rows+1] = { label="NEXT BALL", run=function(g) catching:cycleSelectedBall(g, 1) end }
    end
    rows[#rows+1] = { label="HELP", run=function()
      tell("Hold LMB: steer. Click choices. RMB: back. Arrows: navigate / face. MENU: save, bag, party.")
    end }
    return rows
  end
  mod.hooks:wrap("render.window", function(next, game, ctx)
    local result = next(game, ctx)
    buttons = {}
    if not dock or not active() then return result end
    local g = love.graphics
    g.push("all"); g.origin(); g.setShader(); g.setScissor(); g.setCanvas()
    local font = g.getFont()
    local rows = dockActions(game)
    local cols = math.ceil(#rows/2)
    local cellW, cellH = dock.w/cols, (dock.h-22)/2
    g.setColor(0.04, 0.055, 0.08, 1); g.rectangle("fill", dock.x, dock.y, dock.w, dock.h)
    for i, action in ipairs(rows) do
      local rect = { x=dock.x+((i-1)%cols)*cellW+3,
        y=dock.y+math.floor((i-1)/cols)*cellH+3, w=cellW-6, h=cellH-5 }
      local hover = contains(rect, hoverX, hoverY)
      g.setColor(hover and 0.18 or 0.1, hover and 0.3 or 0.16, hover and 0.38 or 0.22, 1)
      g.rectangle("fill", rect.x, rect.y, rect.w, rect.h, 4, 4)
      g.setColor(0.4, 0.7, 0.78, 1); g.rectangle("line", rect.x, rect.y, rect.w, rect.h, 4, 4)
      g.setColor(0.94, 0.96, 1, 1)
      local scale = math.max(0.2, math.min(1, (rect.w-6)/math.max(1, font:getWidth(action.label)),
        (rect.h-4)/font:getHeight()))
      g.print(action.label, rect.x+(rect.w-font:getWidth(action.label)*scale)/2,
        rect.y+(rect.h-font:getHeight()*scale)/2, 0, scale, scale)
      buttons[#buttons+1] = { rect=rect, action=action, state=top(game),
        mode=top(game).mode, phase=top(game).phase }
    end
    g.setColor(0.65, 0.78, 0.84, 1)
    local hint = notice or "Hold left: move   |   Click: choose / talk   |   Right: back   |   MENU: save / party / bag"
    local scale = math.min(1, (dock.w-12)/math.max(1, font:getWidth(hint)))
    g.print(hint, dock.x+6, dock.y+dock.h-19, 0, scale, scale)
    g.pop()
    return result
  end, 2000)

  -- The dock lives outside the game viewport. Existing native/mod mouse
  -- handlers keep first refusal everywhere else.
  mod.hooks:wrap("input.pointer", function(next, game, ev)
    hoverX, hoverY = ev.x, ev.y
    gameHoverX, gameHoverY = ev.gameX, ev.gameY
    if ev.phase == "pressed" and ev.source == "mouse" and ev.button == 2 and held then
      stopHold(true)
      pending = nil
      return true
    end
    if owns(ev) then
      if ev.phase == "cancelled" then api.reset(); return true end
      if ev.phase == "released"
          and (ev.source == "touch" or ev.button == capture.button) then
        stopHold(not contains(dock, ev.x, ev.y))
        capture = nil
        return true
      end
      if ev.phase == "moved" then
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
            if a.hold or a.catching then startHold(game, a.button, a.catching)
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
    if not active() or not game.renderer.frameRects then return result end
    local state = top(game)
    if not state then return result end
    local entries, dialogue = targets.collect(game, state)
    frame = { state=state, mode=state.mode, phase=state.phase, targets={}, dialogue=dialogue }
    for _, entry in ipairs(entries) do
      if entry.space ~= "window" then entry.rect = project(entry.rect, game.renderer) end
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
      else schedule(game, {button="b"}) end
      claim(ev)
      return true
    end
    if not (ev.source == "touch" or ev.button == 1) then return next(game, ev) end
    if capture then return true end
    local interaction = movement.interaction(game, ev)
    if interaction then
      claim(ev); schedule(game, interaction); return true
    end
    if sameContext(frame, game) then
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
  return api
end
