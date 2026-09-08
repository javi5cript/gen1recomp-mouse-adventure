return function(mod)
  local Pipelines = require("src.render.Pipelines")
  local Tilt = require("src.render.Tilt")
  local Transition = require("src.render.Transition")
  local Collision = require("src.world.Collision")
  local OCTANT = 0.4142135623730951
  local RETRY_TICKS = 12
  local pointer, token, anchor, viewport
  local lastDir, lastAxis, lastPlayer, lastMap, lastX, lastY
  local idleTicks = 0
  local projectionWarned = false
  -- Session override for the steering guide, driven by the G hotkey. nil means
  -- "follow the STEERING GUIDE option"; true/false force it for this session.
  local guideOverride = nil
  local GUIDE_KEY = "g"

  mod.options:define({
    { key = "enabled", type = "toggle", label = "HOLD TO MOVE", default = true },
    { key = "marker", type = "toggle", label = "STEERING GUIDE", default = true },
    { key = "deadzone", type = "number", label = "DEAD ZONE", default = 6,
      min = 2, max = 16, step = 1 },
    { key = "mouse_ui", type = "toggle", label = "MOUSE MENUS AND DIALOGUE", default = true },
    { key = "action_bar", type = "toggle", label = "MOUSE ACTION BAR", default = true },
    { key = "guide_hotkey", type = "toggle", label = "GUIDE HOTKEY (G)", default = true },
  })

  local function enabled(key)
    local value = mod.options:get(key)
    return value ~= false and value ~= 0 and value ~= "OFF"
  end

  -- The steering guide's live visibility. The G hotkey may override the saved
  -- STEERING GUIDE option for the session; when the option itself can be
  -- written back (mod.options:set), the override is cleared so the menu and
  -- the hotkey stay in agreement.
  local function guideVisible()
    if guideOverride ~= nil then return guideOverride end
    return enabled("marker")
  end

  local function toggleGuide(game)
    local nextValue = not guideVisible()
    if type(mod.options.set) == "function" then
      pcall(function() mod.options:set("marker", nextValue) end)
      if game and type(game.writeOptions) == "function" then
        pcall(function() game:writeOptions() end)
      end
      guideOverride = nil
    else
      guideOverride = nextValue
    end
    mod.log:info("Mouse Adventure: steering guide " .. (nextValue and "on" or "off") .. ".")
    return nextValue
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

  -- Classify the overworld camera. Every supported camera -- the flat blit,
  -- engine tilt, and voxel orbit/diorama levels -- shares one property: no
  -- yaw. The camera only pitches down from the south, so world east/west
  -- always maps to screen right/left and north/south to up/down. That lets
  -- the same octant steering and neighbour interaction work in all three
  -- modes. Only the free-look voxel cameras (first/third person) and unknown
  -- world pipelines are left to the mod's own look/move controls.
  local function cameraMode()
    local pipe = Pipelines.worldPipeline()
    if pipe == nil then
      return Tilt.active() and "tilt" or "flat"
    end
    if pipe == "voxel" then
      local level = Pipelines.level("voxel")
      if level == 6 or level == 7 then return "unsupported" end
      return "voxel"
    end
    return "unsupported"
  end

  local function supported()
    return cameraMode() ~= "unsupported"
  end

  local function projectionOK()
    if supported() then projectionWarned = false; return true end
    if not projectionWarned then
      mod.log:warn("Hold to Move supports the flat, tilt and voxel-orbit overworld; the free-look voxel camera isn't supported.")
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

  -- Collapse a click to a single cardinal, measured from the anchor (player
  -- foot in flat mode, viewport centre under tilt/voxel). Used for directional
  -- interaction where no mod-visible pixel unprojection exists.
  local function clickCardinal(ev)
    if not anchor then return nil end
    local dx = (ev.gameX - anchor.x) / anchor.sx
    local dy = (ev.gameY - anchor.y) / anchor.sy
    if dx * dx + dy * dy < 1 then return nil end
    if math.abs(dx) >= math.abs(dy) then
      return dx < 0 and "left" or "right"
    end
    return dy < 0 and "up" or "down"
  end

  local function interaction(game, ev)
    local ow, r = mod.world:overworld(), game.renderer
    if not (ow and top(game) == ow and ow.map and ow.camera and ow.player)
        or (game.save and game.save.generation == 2) or not supported()
        or not anchor or ow.player.moving or not finite(ev.gameX) or not finite(ev.gameY)
        or not ow.npcAtCell or not ow.map.signAtCell then return end
    local p, map, save = ow.player, ow.map, game.save
    local px, py = p.cellX, p.cellY
    -- Two ways to test whether a click targets a neighbour cell. The flat blit
    -- unprojects the pointer to a world pixel and hit-tests the 16x16 cell, so
    -- clicking an NPC's head resolves precisely. Tilt and voxel have no
    -- mod-visible projection, so they fall back to a directional test: the
    -- click's cardinal (relative to screen centre) picks the neighbour.
    local hit
    if flat() and r.wipeSx and r.wipeSy and r.wipeSx > 0 and r.wipeSy > 0 then
      local wx = (ev.gameX - r.wipeWox) / r.wipeSx + math.floor(ow.camera.x)
      local wy = (ev.gameY - r.wipeWoy) / r.wipeSy + math.floor(ow.camera.y)
      hit = function(x, y, _)
        return wx >= x and wx < x + 16 and wy >= y and wy < y + 16
      end
    else
      local clickDir = clickCardinal(ev)
      if not clickDir then return end
      hit = function(_, _, dir) return dir == clickDir end
    end
    local function action(dir, valid)
      return {button="a", direction=dir, valid=function()
        return top(game) == ow and ow.player == p and ow.map == map
          and game.save == save and p.cellX == px and p.cellY == py
          and not p.moving and supported() and valid()
      end}
    end
    local function npcAt(x, y, d)
      local npc = ow:npcAtCell(x, y)
      if not npc and map:isCounterCell(x, y) then
        npc = ow:npcAtCell(x + d[1], y + d[2])
      end
      return npc
    end
    -- Sprite heads sit four pixels above their map cell. Resolve sprites
    -- before scenery, including the native one-counter interaction reach.
    for _, dir in ipairs({"up", "down", "left", "right"}) do
      local d = Collision.DELTA[dir]
      local x, y = px + d[1], py + d[2]
      if map:inBounds(x, y) then
        local npc = npcAt(x, y, d)
        if npc and not npc.hidden and npc.visible ~= false and not npc.moving
            and hit(npc.px or npc.cellX * 16, (npc.py or npc.cellY * 16) - 4, dir) then
          return action(dir, function()
            return npcAt(x, y, d) == npc and not npc.hidden
              and npc.visible ~= false and not npc.moving
          end)
        end
      end
    end
    for _, dir in ipairs({"up", "down", "left", "right"}) do
      local d = Collision.DELTA[dir]
      local x, y = px + d[1], py + d[2]
      if map:inBounds(x, y) and hit(x * 16, y * 16, dir) and not ow:npcAtCell(x, y) then
        local sign = map:signAtCell(x, y)
        if sign then
          return action(dir, function()
            return not ow:npcAtCell(x, y) and map:signAtCell(x, y) == sign
          end)
        end
        -- Inspecting solid scenery uses A, not an event probe. The engine
        -- resolves PCs, shelves, doors, hidden items and script-owned objects.
        local function scenery()
          return not ow:npcAtCell(x, y) and not map:isWalkableCell(x, y)
            and not map:isWaterCell(x, y)
        end
        if scenery() then return action(dir, scenery) end
      end
    end
  end

  local makeUI = assert((loadstring or load)(assert(mod:read("mouse_ui.lua")),
    "@click_to_move/mouse_ui.lua"))()
  local ui = makeUI(mod, {
    cancel = cancel, steering = function() return pointer ~= nil end,
    enabled = enabled, top = top, interaction = interaction,
    guideVisible = guideVisible,
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
    if ow and top(game) == ow and ow.player and ow.camera then
      local mode = cameraMode()
      if mode == "flat" and r.wipeSx and r.wipeSy and r.wipeSx > 0 and r.wipeSy > 0 then
        anchor = {
          x = r.wipeWox + (ow.player.px + 8 - math.floor(ow.camera.x)) * r.wipeSx,
          y = r.wipeWoy + (ow.player.py + 4 - math.floor(ow.camera.y)) * r.wipeSy,
          sx = r.wipeSx, sy = r.wipeSy,
        }
      elseif (mode == "tilt" or mode == "voxel") and viewport
          and viewport.width and viewport.height and viewport.height > 0 then
        -- Tilt and voxel expose no world blit transform, but both keep the
        -- player near the viewport centre with no camera yaw. A centre anchor
        -- therefore yields correct cardinal steering. Scaling by height/144
        -- maps the deadzone to roughly Game Boy pixels so the feel matches the
        -- flat blit across zoom levels.
        local s = viewport.height / 144
        if s <= 0 then s = 1 end
        anchor = {
          x = viewport.width / 2, y = viewport.height / 2,
          sx = s, sy = s,
        }
      end
    end
    if pointer and anchor and inside() and enabled("enabled") and guideVisible() then
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

  -- Bind G to toggle the steering guide. The engine has no dedicated key hook,
  -- so -- like the voxel fork does for its pipeline keys -- wrap Game:keypressed
  -- and claim the key only during free-roam. A screen with its own key handler
  -- (naming, menus) keeps the key, so typing a nickname never toggles the guide.
  do
    local okGame, Game = pcall(require, "src.core.Game")
    if okGame and type(Game) == "table" then
      local inner = Game.keypressed
      function Game:keypressed(key)
        if key == GUIDE_KEY and enabled("guide_hotkey") then
          local states = self.stack and self.stack.states
          local topState = states and states[#states]
          local ow = mod.world and mod.world:overworld()
          local isOverworld = topState ~= nil
            and (topState.isOverworld or topState == ow)
          if isOverworld and not (topState and topState.onKeyPressed) then
            toggleGuide(self)
            return
          end
        end
        if inner then return inner(self, key) end
      end
    end
  end

  mod.log:info("Mouse Adventure 1.3.0: hold to steer (flat/tilt/voxel-orbit); click menus; right-click back; G toggles guide.")
end
