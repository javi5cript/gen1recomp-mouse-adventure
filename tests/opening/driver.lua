-- Native frame driver: observe the running game, act only through mouse
-- callbacks, and let the ordinary engine/mod input dispatch own every action.
return function(game)
  local Json = require("src.link.Json")
  local Viewport = require("src.render.GameViewport")
  local version = require("src.core.GameVersion").get()
  local reportPath = assert(os.getenv("MOUSE_ADVENTURE_REPORT"))
  local result = { status = "running", game = version, milestones = {}, clicks = 0, ticks = 0 }
  local phase = "startup"
  local held

  local function top() return game.stack:top() end
  local function snapshot()
    local s, p = top(), game.overworld.player
    local items = {}
    for id, count in pairs(game.save.inventory or {}) do
      items[#items+1] = { id = id, count = count }
    end
    local party = {}
    for _, mon in ipairs(game.save.party or {}) do
      party[#party+1] = { species = mon.species, level = mon.level, hp = mon.hp }
    end
    local menus = {}
    for _, item in ipairs(s and s.items or {}) do
      menus[#menus+1] = tostring(type(item) == "table" and (item.label or item.id or "?") or item)
    end
    return {
      stage = phase, mode = s and s.mode, phase = s and s.phase,
      screen = s and s.update and debug.getinfo(s.update, "S").short_src,
      map = game.overworld.map and game.overworld.map.id,
      x = p and p.cellX, y = p and p.cellY, moving = p and p.moving,
      playerName = game.save.player.name, rivalName = game.save.player.rival,
      party = party, bag = items, menus = menus,
      pcPotion = game.save.pcItems and game.save.pcItems.POTION,
      glyphs = s and s.glyphs and table.concat(s.glyphs),
      battle = s and s.isBattle, demo = s and s.demo,
    }
  end
  local function write()
    result.state = snapshot()
    local file = assert(io.open(reportPath, "wb"))
    assert(file:write(Json.encode(result)))
    assert(file:close())
  end
  local function step(n)
    for _ = 1, n or 1 do
      result.ticks = result.ticks + 1
      if result.ticks % 300 == 0 then write() end
      assert(result.ticks < 35000, "Opening exceeded its frame budget")
      coroutine.yield()
    end
  end
  local function shot(name)
    assert(love.filesystem.createDirectory("smoke"))
    love.graphics.captureScreenshot("smoke/" .. name .. ".png")
    step(2)
  end
  local function milestone(name)
    result.milestones[#result.milestones+1] = { name = name, tick = result.ticks, state = snapshot() }
    write()
    shot(string.format("%02d-%s", #result.milestones, name))
  end
  local function release()
    if held then
      love.mousereleased(held.x, held.y, 1, false)
      held = nil
    end
  end
  local function click(x, y, button)
    assert(not held, "A click cannot interrupt an unfinished steering gesture")
    button = button or 1
    love.mousemoved(x, y, 0, 0, false)
    love.mousepressed(x, y, button, false, 1)
    result.clicks = result.clicks + 1
    step(2)
    love.mousereleased(x, y, button, false, 1)
    step(10)
  end
  local function ui(x, y, button)
    local r, v = game.renderer:frameRects(), assert(Viewport.rect, "No rendered viewport")
    click(v.x + r.uox + x*r.Ux, v.y + r.uoy + y*r.Uy, button)
  end
  local function dock(index)
    local w, h = love.graphics.getDimensions()
    local cols, cellH = math.max(2, math.min(6, math.floor(w/100))), 32
    local rows = math.max(1, math.min(math.ceil(12/cols), math.floor((h*0.45-48)/cellH)))
    assert(index <= rows*cols and w >= 300 and h >= 240, "Dock control not on first page")
    local height, cellW = rows*cellH+48, w/cols
    click(((index-1)%cols+0.5)*cellW, h-height+math.floor((index-1)/cols)*cellH+cellH/2)
  end
  local function menu(label)
    local s = top()
    if not s or not s.items or not s.tx then return false end
    for i, item in ipairs(s.items) do
      local text = type(item) == "table" and item.label or item
      if text == label then
        local row = i-(s.scroll or 0)
        local count = math.min(s.maxVisible or #s.items, #s.items)
        assert(row >= 1 and row <= count, "Requested menu row is not visible: " .. label)
        local y = s.itemY and (s.ty+s.itemY+(row-1)*s.rowStep)*8
          or (s.ty+s.th-2-(count-row)*s.rowStep)*8
        ui((s.tx+2)*8, y+4)
        return true
      end
    end
    return false
  end
  local function choice(index)
    local s = top()
    assert(s.labels and s.tx and s.firstItem, "Expected a native choice box")
    ui((s.tx+2)*8, (s.ty+s.firstItem+(index-1)*2)*8+4)
  end
  local function listItem(index)
    local s = top()
    assert(s.items and s.rows, "Expected a native item list")
    local row = index-(s.scroll or 0)
    assert(row > 0 and row <= s.rows, "Requested item row is not visible")
    ui(s.itemBox and 56 or 32, s.itemBox and (36+(row-1)*16) or (12+row*16))
  end
  local function advance()
    local s = top()
    if s.boxTx then
      ui((s.boxTx+1)*8, (s.boxTy+1)*8)
    elseif s.isBattle and s.phase == "messages" then
      ui(80, 120)
    elseif getmetatable(s) == require("src.ui.IntroMovie")
        or getmetatable(s) == require("src.ui.YellowIntro")
        or getmetatable(s) == require("src.ui.TitleState") then
      ui(80, 72)
    else
      step(12)
    end
  end
  local function untilState(predicate, act, limit)
    local start = result.ticks
    while not predicate() do
      assert(result.ticks-start < (limit or 2400), "Timed out during " .. phase)
      if act then act() else step() end
    end
  end
  local function namePlayer(text)
    local s = top()
    assert(s.glyphs and s.grid, "Expected the native naming screen")
    assert(#s.glyphs == 0, "Naming screen was not empty")
    for n = 1, #text do
      local char, found = text:sub(n,n), false
      for row, cells in ipairs(s:grid()) do
        for col, glyph in ipairs(cells) do
          if glyph == char then
            ui(col*16, 28+row*16)
            found = true
            break
          end
        end
        if found then break end
      end
      assert(found and table.concat(s.glyphs) == text:sub(1,n), "Name glyph click failed: " .. char)
    end
    dock(3)
    untilState(function() return top() ~= s end)
  end
  local function worldPoint(px, py)
    local r, ow, v = game.renderer, game.overworld, assert(Viewport.rect)
    assert(r.wipeSx and r.wipeSy, "World has not rendered")
    return v.x+r.wipeWox+(px-math.floor(ow.camera.x))*r.wipeSx,
      v.y+r.wipeWoy+(py-math.floor(ow.camera.y))*r.wipeSy
  end
  local function worldClick(x, y)
    local wx, wy = worldPoint(x*16+8, y*16+4)
    click(wx, wy)
  end
  local function idle()
    local ow = game.overworld
    return top() == ow and not ow.player.moving and not ow.transitioning
      and not ow.player.inputLocked and not ow.runner:isRunning()
      and #(ow.scriptMoves or {}) == 0 and not ow.emote and not ow.engaging
  end
  local function walkTo(x, y)
    assert(idle(), "Cannot start walking while a native script or UI owns input")
    local ow, p = game.overworld, game.overworld.player
    local map, start = ow.map, result.ticks
    local dx, dy = x-p.cellX, y-p.cellY
    assert(dx == 0 or dy == 0, "Use cardinal waypoints for opening routes")
    if dx == 0 and dy == 0 then return end
    dx, dy = dx == 0 and 0 or (dx > 0 and 1 or -1), dy == 0 and 0 or (dy > 0 and 1 or -1)
    while ow.map == map and top() == ow and not ow.runner:isRunning() do
      if p.cellX == x and p.cellY == y or p.moving and p.targetX == x and p.targetY == y then
        release()
        untilState(function() return not p.moving or ow.map ~= map end)
        break
      end
      assert(result.ticks-start < 900, "Walking blocked before waypoint " .. x .. "," .. y)
      local wx, wy = worldPoint(p.px+8+dx*40, p.py+4+dy*40)
      if not held then
        love.mousemoved(wx, wy, 0, 0, false)
        love.mousepressed(wx, wy, 1, false, 1)
        held = { x = wx, y = wy }
        result.clicks = result.clicks+1
      else
        love.mousemoved(wx, wy, wx-held.x, wy-held.y, false)
        held.x, held.y = wx, wy
      end
      step()
    end
    release()
    step(2)
  end
  local function settle()
    untilState(idle, advance)
  end

  local function run()
    assert(love.filesystem.getIdentity() == os.getenv("POKEPORT_IDENTITY"),
      "Unexpected save identity")
    assert(version == os.getenv("POKEPORT_VERSION"), "Unexpected game version")
    assert(not require("src.core.SaveData").isPortable(), "Portable mode is not isolated")
    local loaded = game.modStatus.loaded
    assert(#loaded == 1 and loaded[1].id == "click_to_move", "Expected only Mouse Adventure loaded")
    assert(#game.modStatus.errors == 0, "The mod loader reported errors")
    step(3)
    milestone("boot")
    local names = 0
    untilState(function() return top().isOverworld and names == 2 end, function()
      local s = top()
      if s.glyphs and s.grid then
        names = names + 1
        assert(names <= 2, "Unexpected extra naming screen")
        namePlayer(names == 1 and "ASH" or "GARY")
        milestone(names == 1 and "named-ash" or "named-gary")
      elseif not menu("NEW GAME") and not menu("NEW NAME") then
        advance()
      end
    end, 7200)
    phase = "bedroom"
    assert(game.save.player.name == "ASH" and game.save.player.rival == "GARY",
      "The requested names were not saved")
    assert(game.overworld.map.id == "REDS_HOUSE_2F", "Expected the starting bedroom")
    settle()
    milestone("bedroom")
    phase = "pc-potion"
    walkTo(1, 6)
    walkTo(1, 2)
    walkTo(0, 2)
    worldClick(0, 1)
    untilState(function() return top().items and top().tx end, advance)
    assert(menu("WITHDRAW ITEM"), "The bedroom PC did not offer withdrawal")
    untilState(function() return top().kind == "pc_item_withdraw" end)
    local potion
    for i, item in ipairs(top().items) do
      if item.value == "POTION" then potion = i end
    end
    listItem(assert(potion, "The PC Potion is missing"))
    untilState(function() return getmetatable(top()) == require("src.ui.QuantityBox") end)
    assert(top().qty == 1, "Expected to withdraw exactly one Potion")
    dock(1)
    untilState(function()
      return game.save.inventory.POTION == 1 and not game.save.pcItems.POTION
    end, advance)
    milestone("potion-withdrawn")
    untilState(function() return top().kind == "pc_item_withdraw" end, advance)
    listItem(#top().items)
    untilState(function() return top().items and top().tx end)
    assert(menu("LOG OFF"), "Could not log off the bedroom PC")
    settle()

    phase = "downstairs"
    walkTo(7, 2)
    walkTo(7, 1)
    untilState(function() return game.overworld.map.id == "REDS_HOUSE_1F" and idle() end)
    milestone("downstairs")
    phase = "outside"
    walkTo(7, 6)
    walkTo(3, 6)
    walkTo(3, 7)
    untilState(function() return game.overworld.map.id == "PALLET_TOWN" and idle() end)
    milestone("outside")

    phase = "oak-scene"
    walkTo(10, game.overworld.player.cellY)
    walkTo(10, version == "yellow" and 0 or 1)
    milestone("oak-triggered")
    untilState(function()
      return game.overworld.map.id == "OAKS_LAB"
        and game.save.flags.EVENT_OAK_ASKED_TO_CHOOSE_MON and idle()
    end, advance, 7200)
    assert(game.save.flags.EVENT_FOLLOWED_OAK_INTO_LAB, "Oak escort was not completed")
    milestone("oak-lab")

    phase = "starter"
    local species = version == "red" and "CHARMANDER"
      or version == "blue" and "SQUIRTLE" or "PIKACHU"
    local ballX = version == "red" and 6 or 7
    walkTo(5, 4)
    walkTo(ballX, 4)
    worldClick(ballX, 3)
    untilState(function() return game.save.flags.EVENT_GOT_STARTER and idle() end, function()
      local s = top()
      if getmetatable(s) == require("src.ui.DexEntryMenu") then
        dock(1)
      elseif s.labels and s.firstItem then
        -- The take-starter question precedes the gift; the optional nickname
        -- question appears after the real party member has been added.
        choice(#game.save.party == 0 and 1 or 2)
      else
        advance()
      end
    end, 3600)
    assert(#game.save.party == 1 and game.save.party[1].species == species,
      "Received the wrong starter")
    result.starter = species
    milestone("starter-received")

    phase = "rival-battle"
    walkTo(game.overworld.player.cellX, 5)
    walkTo(5, 5)
    walkTo(5, 6)
    untilState(function() return top().isBattle and not top().demo end, advance)
    local battle = top()
    milestone("gary-battle-started")
    untilState(function() return top() ~= battle end, function()
      if battle.phase == "command" then
        ui(88, 116)
      elseif battle.phase == "moveSelect" then
        ui(60, 108)
      else
        advance()
      end
    end, 9000)
    assert(battle.result == "win" or battle.result == "lose", "Rival battle did not resolve naturally")
    result.battleResult = battle.result
    untilState(function() return game.save.flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB end)
    phase = "complete"
    milestone("gary-battle-completed")
  end
  local ok, err = xpcall(run, debug.traceback)
  release()
  if not ok then
    result.status, result.error = "failed", err
    write()
    shot("failure")
    error(err)
  end
  result.status = "passed"
  write()
end
