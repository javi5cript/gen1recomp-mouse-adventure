return function(mod)
  local Pipelines = require("src.render.Pipelines")
  local Tilt = require("src.render.Tilt")
  local Transition = require("src.render.Transition")
  local OCTANT = 0.4142135623730951
  local RETRY_TICKS = 12
  local pointer, token, anchor, viewport
  local lastDir, lastAxis, lastPlayer, lastMap, lastX, lastY
  local idleTicks = 0
  local projectionWarned = false

  mod.options:define({
    { key = "enabled", type = "toggle", label = "HOLD TO MOVE", default = true },
    { key = "marker", type = "toggle", label = "STEERING GUIDE", default = true },
    { key = "deadzone", type = "number", label = "DEAD ZONE", default = 6,
      min = 2, max = 16, step = 1 },
    { key = "mouse_ui", type = "toggle", label = "MOUSE MENUS AND DIALOGUE", default = true },
    { key = "action_bar", type = "toggle", label = "MOUSE ACTION BAR", default = true },
  })

  local function enabled(key)
    local value = mod.options:get(key)
    return value ~= false and value ~= 0 and value ~= "OFF"
  end

  local function release()
    if token then mod.input:release(token); token = nil end
  end

  local function cancel()
    release()
    pointer, lastDir, lastAxis = nil, nil, nil
    lastPlayer, lastMap, lastX, lastY = nil, nil, nil, nil
    idleTicks = 0
  end

  local function top(game)
    local states = game.stack and game.stack.states
    return states and states[#states]
  end

  local function flat()
    return not Tilt.active() and Pipelines.worldPipeline() == nil
  end

  local function projectionOK()
    if flat() then projectionWarned = false; return true end
    if not projectionWarned then
      mod.log:warn("Hold to Move needs the flat overworld: turn VOXEL/TILT off.")
      projectionWarned = true
    end
    return false
  end

  local function finite(n)
    return type(n) == "number" and n == n and n > -math.huge and n < math.huge
  end

  local function inside()
    return pointer and viewport and pointer.x >= 0 and pointer.y >= 0
      and pointer.x < viewport.width and pointer.y < viewport.height
  end

  local function axis(dir)
    return (dir == "left" or dir == "right") and "x" or "y"
  end

  local function directions()
    if not anchor then return nil end
    local dx = (pointer.x - anchor.x) / anchor.sx
    local dy = (pointer.y - anchor.y) / anchor.sy
    local radius = mod.options:get("deadzone")
    if dx * dx + dy * dy <= radius * radius then return nil end
    local ax, ay = math.abs(dx), math.abs(dy)
    local horizontal = dx < 0 and "left" or "right"
    local vertical = dy < 0 and "up" or "down"
    if ay <= ax * OCTANT then return horizontal end
    if ax <= ay * OCTANT then return vertical end
    return horizontal, vertical
  end

  local function manualInput(game)
    for _, btn in ipairs({ "up", "down", "left", "right", "a", "b", "start", "select" }) do
      if game.input:isDown(btn) then return true end
    end
    return false
  end

  local function drive(game)
    -- Release only our input source before checking physical input. Re-press
    -- before the engine polls, so continuous walking has no neutral frame.
    release()
    if not pointer then return end
    if not enabled("enabled") or not projectionOK() or manualInput(game) then
      cancel()
      return
    end
    local ow = mod.world:overworld()
    if not (ow and ow.map and ow.player) then cancel(); return end
    local state = top(game)
    if state ~= ow then
      -- A map fade must not end the gesture. Menus/battles must not inherit it.
      if ow.transitioning and getmetatable(state) == Transition then return end
      cancel()
      return
    end
    if ow.transitioning or ow.player.inputLocked
        or (ow.runner and ow.runner:isRunning())
        or #(ow.scriptMoves or {}) > 0 or ow.engaging or ow.emote
        or (ow.hopLand or 0) > 0 or ow.teleportOut or ow.flyFade
        or ow.flyAnim or ow.flyArrive or ow.spinArrive
        or ow.holeFall or ow.holeArrive then
      return
    end
    if not inside() or not anchor then return end

    local first, second = directions()
    if not first then lastDir = nil; idleTicks = 0; return end
    local p = ow.player
    if lastPlayer ~= p or lastMap ~= ow.map then
      lastPlayer, lastMap = p, ow.map
      lastX, lastY, idleTicks = p.cellX, p.cellY, 0
    elseif p.cellX ~= lastX or p.cellY ~= lastY then
      if lastDir then lastAxis = axis(lastDir) end
      lastX, lastY, idleTicks = p.cellX, p.cellY, 0
    end

    local dir
    if p.moving then
      -- Do not change the sprite's facing or coordinates during interpolation.
      lastAxis = axis(p.facing)
      idleTicks = 0
      dir = lastDir or first
    else
      dir = second and (lastAxis == "x" and second or first) or first
      if second and dir == lastDir and (p.turnTimer or 0) <= 0 then
        idleTicks = idleTicks + 1
        if idleTicks >= RETRY_TICKS then
          -- A blocked diagonal component gets a turn on the other axis.
          -- The engine still decides collisions, ledges and connection exits.
          lastAxis = axis(dir)
          dir = lastAxis == "x" and second or first
          idleTicks = 0
        end
      else
        idleTicks = 0
      end
    end
    lastDir = dir
    token = mod.input:press(game, dir)
  end

  local function owns(ev)
    return pointer and pointer.id == ev.id and pointer.source == ev.source
  end

  local makeUI = assert((loadstring or load)(assert(mod:read("mouse_ui.lua")),
    "@click_to_move/mouse_ui.lua"))()
  local ui = makeUI(mod, {
    cancel = cancel, steering = function() return pointer ~= nil end,
    enabled = enabled, top = top,
  })

  mod.hooks:wrap("input.pointer", function(next, game, ev)
    if ev.phase == "pressed" and ev.source == "mouse" and ev.button == 2 then
      if pointer then cancel(); return true end
    end
    if owns(ev) then
      if ev.phase == "cancelled" or (ev.phase == "released"
          and (ev.source == "touch" or ev.button == 1)) then
        cancel()
        return true
      end
      if ev.phase == "moved" then
        if not finite(ev.gameX) or not finite(ev.gameY) then
          cancel()
          mod.log:warn("Hold to Move cancelled: invalid pointer coordinates.")
          return true
        end
        pointer.x, pointer.y = ev.gameX, ev.gameY
        if not inside() then release() end
        return true
      end
    end
    if ev.phase ~= "pressed" or pointer or not ev.insideGame
        or not enabled("enabled") then return next(game, ev) end
    if not (ev.source == "touch" or (ev.source == "mouse" and ev.button == 1)) then
      return next(game, ev)
    end
    local ow = mod.world:overworld()
    if not (ow and top(game) == ow and ow.player) or ow.transitioning
        or ow.player.inputLocked then return next(game, ev) end
    if not projectionOK() then return next(game, ev) end
    if not anchor or not finite(ev.gameX) or not finite(ev.gameY) then
      mod.log:warn("Hold to Move cannot start before a valid overworld frame.")
      return next(game, ev)
    end
    cancel()
    pointer = { id = ev.id, source = ev.source, x = ev.gameX, y = ev.gameY }
    return true
  end, -100)

  mod.hooks:wrap("input.step", function(next, game, dt)
    drive(game)
    return next(game, dt)
  end)

  mod.hooks:wrap("render.hud", function(next, game, vp)
    local result = next(game, vp)
    viewport, anchor = vp, nil
    local ow = mod.world:overworld()
    local r = game.renderer
    -- Use the actual world blit's scale/origin, not the UI letterbox. This
    -- accounts for zoom, aspect ratio, high DPI and reserved game viewports.
    if ow and top(game) == ow and ow.player and ow.camera and flat()
        and r.wipeSx and r.wipeSy and r.wipeSx > 0 and r.wipeSy > 0 then
      anchor = {
        x = r.wipeWox + (ow.player.px + 8 - math.floor(ow.camera.x)) * r.wipeSx,
        y = r.wipeWoy + (ow.player.py + 4 - math.floor(ow.camera.y)) * r.wipeSy,
        sx = r.wipeSx, sy = r.wipeSy,
      }
    end
    if pointer and anchor and inside() and enabled("enabled") and enabled("marker") then
      local g = love.graphics
      local red, green, blue, alpha = g.getColor()
      local dx, dy = pointer.x - anchor.x, pointer.y - anchor.y
      local length = math.sqrt(dx * dx + dy * dy)
      if length > 0 then
        local ux, uy = dx / length, dy / length
        local x, y = pointer.x, pointer.y
        g.setColor(1, 1, 1, 0.65)
        g.line(anchor.x, anchor.y, x, y)
        g.line(x - ux * 9 - uy * 5, y - uy * 9 + ux * 5,
               x, y, x - ux * 9 + uy * 5, y - uy * 9 - ux * 5)
        g.setColor(red, green, blue, alpha)
      end
    end
    return result
  end)

  mod.events:on("game.ready", function()
    cancel()
    ui.reset()
    viewport, anchor = nil, nil
  end)
  mod.log:info("Mouse Adventure 1.2.0: hold to steer; click menus; right-click back.")
end
