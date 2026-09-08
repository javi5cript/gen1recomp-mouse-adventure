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
  -- Session override for the steering guide. nil means
  -- "follow the STEERING GUIDE option"; true/false force it for this session.
  local guideOverride, guideBase
  local projectedFrame, followerFrame

  mod.options:define({
    { key = "enabled", type = "toggle", label = "HOLD TO MOVE", default = true },
    { key = "marker", type = "toggle", label = "STEERING GUIDE", default = true },
    { key = "deadzone", type = "number", label = "DEAD ZONE", default = 6,
      min = 2, max = 16, step = 1 },
    { key = "mouse_ui", type = "toggle", label = "MOUSE MENUS AND DIALOGUE", default = true },
    { key = "action_bar", type = "toggle", label = "MOUSE ACTION BAR", default = true },
    { key = "guide_hotkey", type = "toggle", label = "GUIDE HOTKEY", default = true },
    { key = "guide_key", type = "choice", label = "GUIDE KEY", default = "g",
      choices = {{"G", "g"}, {"H", "h"}, {"J", "j"}} },
    { key = "dock_size", type = "choice", label = "DOCK SIZE", default = "compact",
      choices = {{"COMPACT", "compact"}, {"COMFORTABLE", "comfortable"}, {"LARGE", "large"}} },
    { key = "wheel_lists", type = "toggle", label = "WHEEL NAVIGATION", default = true },
    { key = "dialogue_buffer", type = "toggle", label = "EARLY DIALOGUE CLICK", default = false },
    { key = "click_hold", type = "toggle", label = "TILT/VOXEL CLICK VS HOLD", default = false },
    { key = "projected_anchor", type = "toggle", label = "PROJECTED PLAYER ANCHOR", default = false },
    { key = "four_way", type = "toggle", label = "FOUR-DIRECTION STEERING", default = false },
    { key = "precision_guide", type = "toggle", label = "DEAD ZONE / DIRECTION", default = false },
    { key = "guide_contrast", type = "toggle", label = "HIGH-CONTRAST GUIDE", default = false },
    { key = "guide_width", type = "number", label = "GUIDE THICKNESS", default = 1,
      min = 1, max = 4, step = 1 },
  })

  local function enabled(key)
    local value = mod.options:get(key)
    return value ~= false and value ~= 0 and value ~= "OFF"
  end

  -- The steering guide's live visibility. Toggles may override the saved
  -- STEERING GUIDE option for the session; when the option itself can be
  -- written back (mod.options:set), the override is cleared so the menu and
  -- the hotkey stay in agreement.
  local function guideVisible()
    if guideOverride ~= nil and enabled("marker") ~= guideBase then guideOverride = nil end
    if guideOverride ~= nil then return guideOverride end
    return enabled("marker")
  end

  local function toggleGuide(game)
    local nextValue = not guideVisible()
    guideOverride, guideBase = nextValue, enabled("marker")
    local message = "Guide " .. (nextValue and "ON" or "OFF") .. " (this session)."
    if type(mod.options.set) == "function" then
      local ok, result = pcall(mod.options.set, mod.options, "marker", nextValue)
      if not ok or result == false or enabled("marker") ~= nextValue then
        guideBase = enabled("marker")
        mod.log:warn("Guide setting update failed: %s", tostring(result))
        return nextValue, message .. " Could not update settings."
      end
      guideOverride = nil
      if game and game.save and game.save.options and type(game.writeOptions) == "function" then
        local saved, err = pcall(game.writeOptions, game)
        if not saved or err == false then
          mod.log:warn("Guide setting save failed: %s", tostring(err))
          return nextValue, "Guide " .. (nextValue and "ON" or "OFF") .. "; settings save failed."
        end
        message = "Guide " .. (nextValue and "ON" or "OFF") .. "."
      end
    end
    mod.log:info("Mouse Adventure: steering guide " .. (nextValue and "on" or "off") .. ".")
    return nextValue, message
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

  local function directions(x, y)
    if not anchor then return nil end
    local dx = ((x or pointer.x) - anchor.x) / anchor.sx
    local dy = ((y or pointer.y) - anchor.y) / anchor.sy
    local radius = mod.options:get("deadzone")
    if dx * dx + dy * dy <= radius * radius then return nil end
    local ax, ay = math.abs(dx), math.abs(dy)
    local horizontal = dx < 0 and "left" or "right"
    local vertical = dy < 0 and "up" or "down"
    if enabled("four_way") then return ax >= ay and horizontal or vertical end
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

  local function isFollower(ow, npc)
    return npc.pikachuFollower == true or npc == ow.follower
  end

  local function followerSize(npc)
    local def = npc.sprite and npc.sprite.def or {}
    local scale = def.pokepcFollowerVisualScale or npc._pokepcFollowerVisualScale or 1
    if not finite(scale) or scale <= 0 then return end
    local w, h = def.frameWidth or 16, def.frameHeight or 16
    if not finite(w) or not finite(h) or w <= 0 or h <= 0 then return end
    return w*scale, h*scale
  end

  local function observeFollowers(ow, project, scale, mode)
    local boxes = {}
    if not finite(scale) or scale <= 0 then return boxes end
    for _, npc in ipairs(ow.entities or {}) do
      if isFollower(ow, npc) and not npc.hidden and npc.visible ~= false and not npc.moving then
        local w, h = followerSize(npc)
        if w and finite(npc.px) and finite(npc.py) then
          local x, y, depth = project(npc.px+8, npc.py+(mode == "voxel" and 8 or 16))
          local size = mode == "voxel" and depth or 1
          if finite(x) and finite(y) and finite(size) and size > 0 then
            local s = scale*size
            boxes[npc] = {x=x-w*s/2, y=y-h*s-(mode == "tilt" and 4*scale or 0),
              w=w*s, h=h*s, px=npc.px, py=npc.py}
          end
        end
      end
    end
    return boxes
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
    -- clicking an NPC's head resolves precisely. Projected followers use
    -- sprite-sized bounds; other neighbours retain directional interaction.
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
    local mode = cameraMode()
    local level = mode == "voxel" and Pipelines.level("voxel")
    local function followerHit(npc)
      if mode == "flat" then
        local w, h = followerSize(npc)
        if not w then return false end
        local wx = (ev.gameX-r.wipeWox)/r.wipeSx+math.floor(ow.camera.x)
        local wy = (ev.gameY-r.wipeWoy)/r.wipeSy+math.floor(ow.camera.y)
        local x, y = npc.px+8-w/2, npc.py+12-h
        return wx >= x and wx < x+w and wy >= y and wy < y+h
      end
      local f = followerFrame
      local box = f and f.boxes[npc]
      return box and f.state == ow and f.map == map and f.player == p
        and f.mode == mode and f.level == level
        and f.camX == ow.camera.x and f.camY == ow.camera.y
        and box.px == npc.px and box.py == npc.py
        and ev.gameX >= box.x and ev.gameX < box.x+box.w
        and ev.gameY >= box.y and ev.gameY < box.y+box.h
    end
    local function action(dir, valid, hint)
      return {button="a", direction=dir, hint=hint, valid=function()
        return top(game) == ow and ow.player == p and ow.map == map
          and game.save == save and p.cellX == px and p.cellY == py
          and not p.moving and cameraMode() == mode
          and (mode ~= "voxel" or Pipelines.level("voxel") == level) and valid()
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
        local follower = npc and isFollower(ow, npc)
        local targeted = npc and ((follower and followerHit(npc)) or
          (not follower and hit(npc.px or npc.cellX*16, (npc.py or npc.cellY*16)-4, dir)))
        if npc and not npc.hidden and npc.visible ~= false and not npc.moving and targeted then
          local nx, ny = npc.px, npc.py
          return action(dir, function()
            return npcAt(x, y, d) == npc and not npc.hidden
              and npc.visible ~= false and not npc.moving
              and (not follower or (npc.px == nx and npc.py == ny))
          end, "Talk / interact")
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
          end, "Read sign")
        end
        -- Inspecting solid scenery uses A, not an event probe. The engine
        -- resolves PCs, shelves, doors, hidden items and script-owned objects.
        local function scenery()
          return not ow:npcAtCell(x, y) and not map:isWalkableCell(x, y)
            and not map:isWaterCell(x, y)
        end
        if scenery() then return action(dir, scenery, "Inspect") end
      end
    end
  end

  -- Observe the camera's own projection while it renders, not guessed camera
  -- angles. A frame is consumed once below so stale map/camera data cannot steer.
  if type(Pipelines.drawWorld) == "function" then
    local inner = Pipelines.drawWorld
    function Pipelines.drawWorld(id, ctx)
      if id ~= "voxel" or not supported()
          or type(ctx.drawFx) ~= "function" then return inner(id, ctx) end
      projectedFrame = nil
      local observed
      local copy = {}
      for k, v in pairs(ctx) do copy[k] = v end
      copy.drawFx = function(project, scale)
        local p = ctx.state.player
        local x, y = project(p.px + 8, p.py + 16)
        local target = love.graphics.getCanvas()
        local width, height
        if target then width, height = target:getWidth(), target:getHeight() end
        if finite(x) and finite(y) and finite(width) and width > 0
            and finite(height) and height > 0 then
          observed = {x=x, y=y, scale=scale or ctx.scale, state=ctx.state,
            projectionWidth=width, projectionHeight=height,
            player=p, map=ctx.state.map, mode="voxel", level=Pipelines.level("voxel"),
            followers=observeFollowers(ctx.state, project, scale or ctx.scale, "voxel"),
            camX=ctx.state.camera.x, camY=ctx.state.camera.y}
        end
        return ctx.drawFx(project, scale)
      end
      local canvas = inner(id, copy)
      if observed and canvas then
        observed.width, observed.height = canvas:getWidth(), canvas:getHeight()
        observed.canvas = canvas
        projectedFrame = observed
      end
      return canvas
    end
  end

  local observedRenderer
  local function observeTilt(game)
    local renderer = game.renderer
    if not renderer or observedRenderer == renderer then return end
    observedRenderer = renderer
    if type(renderer.endFrame) == "function" then
      local innerEnd = renderer.endFrame
      function renderer:endFrame(...)
        if projectedFrame and projectedFrame.mode == "voxel" then
          projectedFrame.accepted = self.worldOverride == projectedFrame.canvas
          projectedFrame.rect = self:frameRects()
        end
        return innerEnd(self, ...)
      end
    end
    if type(renderer.drawTiltedWorld) ~= "function" then return end
    local inner = renderer.drawTiltedWorld
    function renderer:drawTiltedWorld(zones, sx, sy, ox, oy, ...)
      local drawn = inner(self, zones, sx, sy, ox, oy, ...)
      local ow = mod.world:overworld()
      if drawn and ow and top(game) == ow and ow.player
          and ow.camera and type(Tilt.groundPoint) == "function" then
        local p, cam = ow.player, ow.camera
        local x, y = Tilt.groundPoint(p.px + 8 - math.floor(cam.x),
          p.py + 16 - math.floor(cam.y), self.worldCanvas:getWidth(), self.worldCanvas:getHeight())
        if finite(x) and finite(y) and finite(sx) and sx > 0 and finite(sy or sx) and (sy or sx) > 0 then
          local function project(wx, wy)
            return Tilt.groundPoint(wx-math.floor(cam.x), wy-math.floor(cam.y),
              self.worldCanvas:getWidth(), self.worldCanvas:getHeight())
          end
          projectedFrame = {x=ox+x*sx, y=oy+y*(sy or sx), sx=sx, sy=sy or sx,
            state=ow, player=p, map=ow.map, mode="tilt", camX=cam.x, camY=cam.y,
            followers=observeFollowers(ow, project, 1, "tilt"), ox=ox, oy=oy}
        end
      end
      return drawn
    end
  end

  local function hint(game, x, y)
    local ow = mod.world:overworld()
    if not ow or top(game) ~= ow then return end
    if not supported() then return "Mouse steering unavailable: use this camera's controls." end
    if not enabled("enabled") then return "Held steering is OFF. Dock arrows still work." end
    if not anchor then return "Waiting for a rendered overworld frame." end
    local target = x and y and interaction(game, {gameX=x, gameY=y})
    if target then
      return target.hint .. (enabled("click_hold") and not flat() and ": short click; hold to move." or ": click.")
    end
    local first, second
    if x and y then first, second = directions(x, y) end
    if not first and x and y then return "Dead zone: movement paused." end
    local text = first and ("Hold to move " .. first .. (second and " / " .. second or "") .. ".")
      or "Hold to move, point to steer. Click nearby objects."
    if not flat() and not anchor.projected then text = text .. " Approximate centre anchor." end
    return text
  end

  local function beginSteering(game, ev)
    local ow = mod.world:overworld()
    if not enabled("enabled") or not ev.insideGame or not (ow and top(game) == ow and ow.player)
        or ow.transitioning or ow.player.inputLocked or manualInput(game) then return false end
    if not projectionOK() then return false end
    if not anchor or not finite(ev.gameX) or not finite(ev.gameY) then
      mod.log:warn("Hold to Move cannot start before a valid overworld frame.")
      return false
    end
    cancel()
    pointer = {id=ev.id, source=ev.source, x=ev.gameX, y=ev.gameY}
    return true
  end

  local makeUI = assert((loadstring or load)(assert(mod:read("mouse_ui.lua")),
    "@click_to_move/mouse_ui.lua"))()
  local ui = makeUI(mod, {
    cancel = cancel, steering = function() return pointer ~= nil end,
    enabled = enabled, top = top, interaction = interaction,
    guideVisible = guideVisible, toggleGuide = toggleGuide, hint = hint,
    option = function(key) return mod.options:get(key) end,
    deferredInteraction = function() return enabled("click_hold") and not flat() and supported() end,
    beginSteering = beginSteering,
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
    if beginSteering(game, ev) then return true end
    return next(game, ev)
  end, -100)

  mod.hooks:wrap("input.step", function(next, game, dt)
    drive(game)
    return next(game, dt)
  end)

  mod.hooks:wrap("render.hud", function(next, game, vp)
    local result = next(game, vp)
    viewport, anchor, followerFrame = vp, nil, nil
    local ow = mod.world:overworld()
    local r = game.renderer
    observeTilt(game)
    local projected = projectedFrame
    projectedFrame = nil
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
        -- Preserve the centre anchor unless a fresh native projection is
        -- available and explicitly enabled.
        local s = viewport.height / 144
        if s <= 0 then s = 1 end
        anchor = {
          x = viewport.width / 2, y = viewport.height / 2,
          sx = s, sy = s,
        }
        if projected and projected.state == ow
            and projected.player == ow.player and projected.map == ow.map and projected.mode == mode then
          local candidate, ox, oy, sx, sy
          if mode == "tilt" then
            candidate = {x=projected.x, y=projected.y, sx=projected.sx, sy=projected.sy, projected=true}
            ox, oy, sx, sy = projected.ox, projected.oy, projected.sx, projected.sy
          elseif projected.accepted and projected.rect and projected.level == Pipelines.level("voxel")
              and finite(projected.scale) and projected.scale > 0
              and projected.width > 0 and projected.height > 0 then
            local f = projected.rect
            -- Voxel AA resolves the projection canvas before the engine blit.
            ox, oy = f.vux, f.vuy
            sx = projected.width/projected.projectionWidth/f.dpiX
            sy = projected.height/projected.projectionHeight/f.dpiY
            candidate = {x=f.vux+projected.x*sx, y=f.vuy+projected.y*sy,
              sx=projected.scale*sx, sy=projected.scale*sy, projected=true}
          end
          if candidate then
            if enabled("projected_anchor") then anchor = candidate end
            local boxes = {}
            for npc, b in pairs(projected.followers or {}) do
              boxes[npc] = {x=ox+b.x*sx, y=oy+b.y*sy, w=b.w*sx, h=b.h*sy, px=b.px, py=b.py}
            end
            followerFrame = {boxes=boxes, state=ow, map=ow.map, player=ow.player,
              camX=projected.camX, camY=projected.camY, mode=mode,
              level=mode == "voxel" and projected.level}
          end
        end
      end
    end
    if pointer and anchor and inside() and enabled("enabled") and guideVisible() then
      local g = love.graphics
      g.push("all")
      local dx, dy = pointer.x - anchor.x, pointer.y - anchor.y
      local length = math.sqrt(dx * dx + dy * dy)
      local first, second = directions()
      if enabled("precision_guide") then
        local radius = mod.options:get("deadzone")
        g.setColor(0.15, 0.85, 0.95, 0.9)
        g.ellipse("line", anchor.x, anchor.y, radius*anchor.sx, radius*anchor.sy)
        local label = not first and "PAUSED" or (lastDir or first):upper()
        if second and not lastDir then label = first:upper() .. " / " .. second:upper() end
        g.print(label, anchor.x+10, anchor.y+10)
      end
      if length > 0 and (first or not enabled("precision_guide")) then
        local ux, uy = dx / length, dy / length
        local x, y = pointer.x, pointer.y
        local function draw()
          g.line(anchor.x, anchor.y, x, y)
          g.line(x - ux * 9 - uy * 5, y - uy * 9 + ux * 5,
                 x, y, x - ux * 9 + uy * 5, y - uy * 9 - ux * 5)
        end
        local width = mod.options:get("guide_width")
        if enabled("guide_contrast") then
          g.setLineWidth(width+3); g.setColor(0, 0, 0, 1); draw()
        end
        g.setLineWidth(width); g.setColor(1, 1, 1, enabled("guide_contrast") and 1 or 0.65); draw()
      end
      g.pop()
    end
    return result
  end)

  mod.events:on("game.ready", function(event)
    cancel()
    ui.reset()
    viewport, anchor = nil, nil
    projectedFrame, followerFrame = nil, nil
    if event and event.game then observeTilt(event.game); ui.observe(event.game) end
  end)

  -- Bind the configured guide key. The engine has no dedicated key hook,
  -- so -- like the voxel fork does for its pipeline keys -- wrap Game:keypressed
  -- and claim the key only during free-roam. A screen with its own key handler
  -- (naming, menus) keeps the key, so typing a nickname never toggles the guide.
  do
    local okGame, Game = pcall(require, "src.core.Game")
    if okGame and type(Game) == "table" then
      local inner = Game.keypressed
      function Game:keypressed(key, ...)
        if key == mod.options:get("guide_key") and enabled("guide_hotkey") then
          local states = self.stack and self.stack.states
          local topState = states and states[#states]
          local ow = mod.world and mod.world:overworld()
          local isOverworld = topState ~= nil
            and (topState.isOverworld or topState == ow)
          local bound = self.input and self.input.keyBindings and self.input.keyBindings[key]
          if isOverworld and not bound and not (topState and topState.onKeyPressed) then
            local _, message = toggleGuide(self)
            ui.tell(message)
            return
          end
        end
        if inner then return inner(self, key, ...) end
      end
    end
  end

  mod.log:info("Mouse Adventure 1.4.0: hold to move, point to steer; click menus; right-click back; guide controls in the dock.")
end
