-- Actual installed engine Input, Player, Collision, Camera, Hooks and
-- Transition code; controller input/edge methods are extracted unmodified.
-- Graphics, map fixtures and controller surroundings are headless doubles.
local warnings = {}
package.preload["src.core.Logger"] = function()
  return { warn = function(...) warnings[#warnings + 1] = {...} end }
end
package.preload["src.mods.Runtime"] = function()
  return { wantsHook = function() return false end,
    emit = function() end,
    call = function(_, fn, ...) return fn(...) end }
end
package.preload["src.render.Assets"] = function() return {register=function() end} end
package.preload["src.render.Font"] = function()
  return {
    split=function(text)
      local spans={}
      for i=1,#text do spans[i]={from=i,to=i} end
      return spans
    end,
    encode=function(text)
      local codes={}
      for i=1,#text do codes[i]=text:byte(i) end
      return codes
    end,
    spansFitting=function(spans, pixels) return math.min(#spans, math.floor(pixels/8)) end,
    width=function(text) return #text*8 end, advanceOf=function() return 8 end,
    draw=function() end, drawCode=function() end, drawBox=function() end,
  }
end
package.preload["src.render.HudTiles"] = function() return {} end
package.preload["src.battle.UIVisibility"] = function()
  return {bottomVisible=function() return true end}
end
package.preload["src.battle.BattleState"] = function()
  return { StatBox = {} }
end
package.preload["src.ui.DexEntryMenu"] = function()
  return assert(load("local DexEntryMenu = {}; DexEntryMenu.__index = DexEntryMenu\n"
    .. DEX_METHODS .. "\nfunction DexEntryMenu.draw() end\nreturn DexEntryMenu"))()
end
package.preload["src.ui.PartyMenu"] = function()
  return assert(load([[
    local Runtime, Strings, Screens = ...
    local PartyMenu = {}; PartyMenu.__index = PartyMenu
  ]] .. PARTY_METHODS .. "\nfunction PartyMenu.draw() end\nreturn PartyMenu"))(
    require("src.mods.Runtime"), require("src.core.Strings"),
    {push=function(g,screen,mon) g.stack:push({screen=screen,mon=mon}) end})
end
package.preload["src.world.PikachuFollower"] = function()
  return {isFollowingDisabled=function() return false end}
end
package.preload["src.ui.MoveSelectMenu"] = function() return {draw=function() end} end
package.preload["src.ui.MoveLearnMenu"] = function() return {draw=function() end} end
package.preload["src.core.Strings"] = function()
  return function(text, ...) return select("#",...)>0 and string.format(text,...) or text end
end
package.preload["src.ui.Theme"] = function()
  return {textBox={tx=0,ty=12,tw=20,th=6,maxCols=18},
    choiceBox={tx=14,ty=7,tw=6,th=5,firstItem=1}}
end
package.preload["src.core.GamepadMap"] = function()
  return { gamepadBindings = function() return {} end,
    rawBindings = function() return {} end, DEFAULT_PAD_ACTIONS = {} }
end
package.preload["src.core.GameVersion"] = function() return {} end
package.preload["src.core.Sound"] = function()
  return { play = function() end, playPress = function() end,
    playPikaCry=function() end, playCry=function() end }
end
package.preload["src.core.Music"] = function()
  return {play=function() end,stop=function() end}
end
package.preload["src.world.FieldDefaults"] = function()
  return { world = function() end, fieldValue = function() return "player" end }
end
package.preload["src.render.SpriteRenderer"] = function()
  return { new = function() return {} end }
end
local tilted, projected, voxelLevel = false, false, 3
local projectionCase, draws, wheelBehavior, previousKeys, frameCase
local currentFont, fontStack, fontDPI, fontsCreated
local function testFont(size)
  return {size=size, getWidth=function(_,text) return #text*7*size/12 end,
    getHeight=function() return size end, release=function(self) self.released=true end}
end
package.preload["src.render.Tilt"] = function()
  return { active = function() return tilted end,
    groundPoint=function(x,y,w,h)
      projectionCase.observed = {x,y,w,h}
      if projectionCase.project then return projectionCase.project(x,y,w,h) end
      return projectionCase.x, projectionCase.y
    end }
end
package.preload["src.render.Pipelines"] = function()
  return {
    worldPipeline = function() return projected and "voxel" or nil end,
    level = function(id) return id == "voxel" and voxelLevel or 0 end,
    drawWorld=function(_, ctx)
      if not projectionCase.skipFx then
        ctx.drawFx(function(x,y)
          projectionCase.observed = {x,y}
          local px,py,depth=projectionCase.x,projectionCase.y,projectionCase.depth or 1
          if projectionCase.project then px,py,depth=projectionCase.project(x,y) end
          local aa=projectionCase.aa or 1
          return px*aa,py*aa,depth
        end, (projectionCase.scale or 4)*(projectionCase.aa or 1))
      end
      return projectionCase.canvas
    end,
  }
end
love = { graphics = {
  getColor = function() return 1, 1, 1, 1 end,
  setColor = function() end, line = function(...) draws.lines[#draws.lines+1] = {...} end,
  ellipse=function(...) draws.ellipses[#draws.ellipses+1] = {...} end,
  setLineWidth=function(w) draws.widths[#draws.widths+1] = w end,
  push=function() fontStack[#fontStack+1]=currentFont end,
  pop=function() currentFont=table.remove(fontStack) end, origin=function() end,
  setCanvas=function() end, setShader=function() end, setScissor=function() end,
  getCanvas=function()
    if not projectionCase or projectionCase.noCanvas then return nil end
    local canvas,aa=projectionCase.canvas,projectionCase.aa or 1
    return {getWidth=function() return canvas:getWidth()*aa end,
      getHeight=function() return canvas:getHeight()*aa end}
  end,
  rectangle=function(...) draws.rects[#draws.rects+1] = {...} end,
  print=function(...)
    local t={...}; t.font=currentFont; draws.text[#draws.text+1]=t
  end,
  getDimensions=function() return 960,720 end,
  getFont=function() return currentFont end,
  setFont=function(font) currentFont=font end,
  getDPIScale=function() return fontDPI end,
  newFont=function(size,hinting,dpi)
    local font=testFont(size); font.dpi=dpi; font.hinting=hinting
    fontsCreated[#fontsCreated+1]=font
    return font
  end,
} }

local Player = require("src.world.Player")
local Input = require("src.core.Input")
local Collision = require("src.world.Collision")
local Camera = require("src.render.Camera")
local Transition = require("src.render.Transition")
local Hooks = require("src.mods.Hooks")
local game, ow, hooks, options, events, holds, steps, rect, origin, registry, mod
local noop = function() end
local function eq(a, b, why)
  assert(a == b, (why or "mismatch") .. ": " .. tostring(a) .. " != " .. tostring(b))
end
local function map(id, blocked)
  return {
    id = id, width = 100, height = 100,
    inBounds = function(self, x, y)
      return x >= 0 and y >= 0 and x < self.width and y < self.height
    end,
    isWalkableCell = function(_, x, y) return not (blocked and blocked(x, y)) end,
    isWaterCell = function() return false end,
    isCounterCell = function(self,x,y) return self.counters and self.counters[x.."_"..y] end,
    signAtCell = function(self,x,y) return self.signs and self.signs[x.."_"..y] end,
    connection = function(self, dir) return self.connections and self.connections[dir] end,
  }
end
local function render()
  ow.camera:follow(ow.player.px, ow.player.py, 160, 144)
  local r = game.renderer
  origin = {
    x = r.wipeWox + (ow.player.px + 8 - math.floor(ow.camera.x)) * r.wipeSx,
    y = r.wipeWoy + (ow.player.py + 4 - math.floor(ow.camera.y)) * r.wipeSy,
  }
  if projectionCase then
    if projectionCase.mode == "voxel" then
      r.worldOverride = require("src.render.Pipelines").drawWorld("voxel",
        {state=ow,scale=4,drawFx=function() projectionCase.fxCalled=true end})
      if projectionCase.rejected then r.worldOverride = nil end
    else
      r:drawTiltedWorld({}, 3, 2, 17, 29)
    end
  end
  if frameCase then r.worldActive=frameCase.worldActive end
  if r.endFrame then r:endFrame() end
  hooks:call("render.hud", noop, game, rect)
end
local function setup()
  warnings, tilted, projected, voxelLevel = {}, false, false, 3
  projectionCase, wheelBehavior, previousKeys, frameCase = nil, nil, {}, nil
  currentFont, fontStack, fontDPI, fontsCreated = testFont(12), {}, 1, {}
  draws = {lines={},ellipses={},widths={},rects={},text={}}
  package.loaded["src.render.Pipelines"] = nil
  holds, options, events, steps, registry = {}, {}, {}, {}, {}
  hooks = Hooks.new()
  game = { data = { sprites = { player = {} }, field = {} }, save = {},
    options = {textSpeed=1},
    input = setmetatable({}, { __index = Input }),
    renderer = { wipeWox = 0, wipeWoy = 0, wipeSx = 3, wipeSy = 3,
      drawTiltedWorld=function() return not projectionCase.rejected end,
      endFrame=function(self) self.worldOverride=nil; self.worldActive=false end,
      worldCanvas={getWidth=function() return 160 end,getHeight=function() return 144 end} } }
  game.wheelmoved=function(self, ...)
    if wheelBehavior then return wheelBehavior(self, ...) end
  end
  game.keypressed=function(_,key) previousKeys[#previousKeys+1]=key end
  package.loaded["src.core.Game"] = game
  game.input:init()
  ow = { isOverworld = true, map = map("start"),
    player = Player.new(game.data, 50, 50, "down"), camera = Camera.new(),
    entities = {}, npcs = {}, runner = { isRunning = function() return false end }, scriptMoves = {} }
  game.stack = { states = { ow },
    top = function(self) return self.states[#self.states] end,
    push = function(self, state) self.states[#self.states+1] = state end,
    pop = function(self) return table.remove(self.states) end }
  local factory = assert(load([[
    local Game, Collision, Warp, Screens = ...
    local Runtime = require("src.mods.Runtime")
    local mapScripts = {get=function() end}
    local COMPASS = {up="north",down="south",left="west",right="east"}
    local OverworldState = {}
  ]] .. INTERACTION_HELPERS .. "\n" .. CONTROLLER_METHODS .. "\nreturn OverworldState"))
  local native = factory(game, Collision, {
    onEdge = function() end, onCollision = function() end,
  }, { push = function(g) table.insert(g.stack.states, { menu = true }) end })
  ow.handleInput, ow.checkEdgeExit = native.handleInput, native.checkEdgeExit
  ow.dirHeld = native.dirHeld
  ow.npcAtCell, ow.nativeInteract = native.npcAtCell, native.interact
  ow.checkLedgeHop = function() return false end
  ow.checkBoulderPush = function() return false end
  ow.canCollisionWarp = function() return false end
  ow.interact = function() table.insert(game.stack.states, { dialog = true }) end
  ow.crossConnection = function(self, dir, conn)
    self.map = map(conn.map)
    local p = self.player
    p.cellX, p.cellY, p.px, p.py = 0, 50, 0, 800
    p:tryMove(dir, self.map, self.entities)
    return true
  end
  rect = { width = 960, height = 720 }
  mod = { hooks = hooks, options = {}, events = {}, input = {}, world = {},
    log = { info = noop, warn = function(...) warnings[#warnings + 1] = {...} end } }
  function mod.options:define(rows)
    for _, row in ipairs(rows) do options[row.key] = row.default end
  end
  function mod.options:get(key) return options[key] end
  function mod.options:set(key, value) options[key] = value end
  function mod:read(name) return MOD_FILES[name] end
  function mod.find(id) return registry[id] end
  function mod.events:on(name, callback) events[name] = callback end
  local sequence = 0
  function mod.input:press(g, btn)
    sequence = sequence + 1
    local token = "mod:click_to_move:" .. sequence
    holds[token] = btn
    g.input:sourcePress(btn, token)
    return token
  end
  function mod.input:release(token)
    local btn = holds[token]
    if not btn then return false end
    game.input:sourceRelease(btn, token)
    holds[token] = nil
    return true
  end
  function mod.input:tap(g, btn)
    local token = self:press(g, btn)
    self:release(token)
  end
  function mod.world:overworld() return ow end
  assert(load(MOD_SOURCE, "click_to_move"))()(mod)
  events["game.ready"]({game=game})
  render()
end
local function pointer(phase, dx, dy, changes)
  local ev = { phase = phase, source = "mouse", id = "mouse",
    button = phase == "moved" and nil or 1, insideGame = true,
    gameX = origin.x + (dx or 70) * game.renderer.wipeSx,
    gameY = origin.y + (dy or 0) * game.renderer.wipeSy }
  -- Deliberately distinct absolute window coordinates.
  ev.x, ev.y = ev.gameX + 317, ev.gameY + 129
  for key, value in pairs(changes or {}) do ev[key] = value end
  return hooks:call("input.pointer", function() return false end, game, ev)
end
local function tick(n)
  for _ = 1, n or 1 do
    hooks:call("input.step", noop, game, 1/60)
    game.input:step()
    local state = game.stack:top()
    if state == ow and not ow.transitioning then
      if not ow.player.inputLocked and not ow.runner:isRunning()
          and #ow.scriptMoves == 0 and not ow.engaging and not ow.emote then
        local result = ow:handleInput()
        if result == "moved" then steps[#steps + 1] = ow.player.facing end
      end
      ow.player:update()
    elseif state.update then
      state:update(1/60)
    end
    render()
  end
  if #warnings > 0 then
    for _, value in ipairs(warnings[1]) do print(tostring(value)) end
  end
  eq(#warnings, 0, "unexpected mod/hook warning")
end
local function noHold()
  eq(next(holds), nil, "mod hold leaked")
end
local function warp()
  ow.transitioning = true
  table.insert(game.stack.states, Transition.new(game, function()
    ow.map = map("indoors")
    ow.player = Player.new(game.data, 40, 40, "down")
  end, function() ow.transitioning = false end, true, { frames = 8, framesIn = 4 }))
end
local count = 0
local function test(name, fn)
  setup()
  fn()
  pointer("cancelled")
  noHold()
  count = count + 1
  print("PASS " .. name)
end

for _, case in ipairs({
  {"east", 70, 0, "right"}, {"west", -65, 0, "left"},
  {"north", 0, -65, "up"}, {"south", 0, 70, "down"},
  {"northeast", 65, -65, "right", "up"}, {"northwest", -65, -65, "left", "up"},
  {"southeast", 65, 65, "right", "down"}, {"southwest", -65, 65, "left", "down"},
}) do
  test("octant " .. case[1], function()
    pointer("pressed", case[2], case[3])
    tick(145)
    assert(#steps >= 8, "held steering stopped")
    for i, step in ipairs(steps) do
      eq(step, case[5] and (i % 2 == 0 and case[5] or case[4]) or case[4])
    end
  end)
end
test("continues beyond initially clicked location", function()
  pointer("pressed", 20, 0)
  tick(320)
  assert(ow.player.cellX >= 69)
end)
test("drag changes direction after current tile", function()
  pointer("pressed", 70, 0); tick(10)
  local facing = ow.player.facing
  pointer("moved", 0, -60); tick()
  eq(ow.player.facing, facing, "changed facing mid-step")
  tick(70)
  eq(steps[#steps], "up")
end)
test("release completes only current step", function()
  pointer("pressed"); tick(10)
  pointer("released", nil, nil, { insideGame = false })
  noHold(); tick(70)
  eq(ow.player.cellX, 51)
end)
test("hover does not move", function()
  pointer("moved"); tick(60); eq(#steps, 0)
end)
test("dead zone pauses then resumes same hold", function()
  pointer("pressed", 0, 0); tick(30); eq(#steps, 0)
  pointer("moved", 70, 0); tick(50); assert(#steps > 0)
  pointer("moved", 0, 0); tick(20); noHold()
end)
test("diagonal blocked axis tries open axis", function()
  ow.map = map("wall", function(x) return x > 50 end)
  pointer("pressed", 65, -65); tick(200)
  eq(ow.player.cellX, 50); assert(ow.player.cellY < 47)
end)
test("solid wall cannot be bypassed", function()
  ow.map = map("wall", function() return true end)
  pointer("pressed", 65, -65); tick(120)
  eq(ow.player.cellX, 50); eq(ow.player.cellY, 50)
end)
test("NPC collision is preserved", function()
  ow.entities = { {cellX=51, cellY=50} }
  pointer("pressed"); tick(80); eq(ow.player.cellX, 50)
end)
test("native edge-exit dispatch crosses map while held", function()
  ow.map.width = 52; ow.map.connections = { east = {map="route"} }
  pointer("pressed"); tick(160)
  eq(ow.map.id, "route"); assert(ow.player.cellX > 3)
end)
test("door fade and replaced player resume while held", function()
  pointer("pressed"); tick(10); warp(); tick(3); noHold()
  tick(80); eq(ow.map.id, "indoors"); assert(ow.player.cellX > 42)
end)
test("release in fade never resumes", function()
  pointer("pressed"); tick(10); warp(); tick(2)
  pointer("released"); tick(80); eq(ow.player.cellX, 40)
end)
test("menu above a fade cancels rather than inheriting the warp hold", function()
  pointer("pressed"); tick(10); warp()
  table.insert(game.stack.states, {menu=true})
  tick(); noHold()
  game.stack:pop(); tick(80); eq(ow.player.cellX, 40)
end)
for _, name in ipairs({"menu", "battle"}) do
  test(name .. " cancels instead of resuming", function()
    pointer("pressed"); tick(10)
    table.insert(game.stack.states, {[name]=true}); tick(2); noHold()
    game.stack:pop(); tick(80); eq(ow.player.cellX, 51)
  end)
end
test("disable mid-hold cancels", function()
  pointer("pressed"); tick(10)
  options.enabled = false; tick(); noHold()
  options.enabled = true; tick(80); eq(ow.player.cellX, 51)
end)
test("focus cancellation stops hold", function()
  pointer("pressed"); tick(10); pointer("cancelled")
  tick(80); eq(ow.player.cellX, 51)
end)
test("right press cancels but right release does not", function()
  pointer("pressed"); tick(10)
  pointer("released", nil, nil, {button=2}); tick(40)
  assert(ow.player.cellX > 51)
  pointer("pressed", nil, nil, {button=2}); noHold()
end)
test("unowned touch cannot steer or cancel", function()
  pointer("pressed"); tick(10)
  pointer("moved", -60, 0, {source="touch", id="finger2"})
  pointer("released", nil, nil, {source="touch", id="finger2"})
  tick(50); eq(steps[#steps], "right")
end)
test("touch owns full gesture", function()
  pointer("pressed", 70, 0, {source="touch", id="finger1"}); tick(50)
  pointer("released", nil, nil, {source="touch", id="finger1", button=false})
  noHold()
end)
test("leaving viewport pauses and returning resumes", function()
  pointer("pressed"); tick(10)
  pointer("moved", nil, nil, {gameX=-1,insideGame=false}); noHold()
  tick(50); eq(ow.player.cellX, 51)
  pointer("moved"); tick(50); assert(ow.player.cellX > 51)
end)
test("physical hold survives cancellation and takes over", function()
  pointer("pressed"); tick(10)
  game.input:sourcePress("up", "keyboard:up")
  tick(); noHold(); assert(game.input:isDown("up"))
  tick(50); eq(steps[#steps], "up")
  game.input:sourceRelease("up", "keyboard:up")
end)
test("scripted arrival pauses then resumes", function()
  pointer("pressed"); tick(10)
  ow.scriptMoves = {{}}
  tick(30); noHold()
  ow.scriptMoves = {}; tick(60); assert(ow.player.cellX > 52)
end)
test("one-frame steps still alternate", function()
  ow.player.stepFrames = 1
  pointer("pressed", 65, -65); tick(30)
  for i, step in ipairs(steps) do eq(step, i%2 == 1 and "right" or "up") end
end)
test("zoom DPI viewport offsets use world transform", function()
  game.renderer = {wipeWox=45, wipeWoy=-17, wipeSx=5, wipeSy=2}
  render()
  pointer("pressed", 50, -50); tick(90)
  for i, step in ipairs(steps) do eq(step, i%2 == 1 and "right" or "up") end
end)
test("marker disabled does not disable movement", function()
  options.marker = false
  pointer("pressed"); tick(50); assert(#steps > 1)
end)
test("game-ready clears stale capture", function()
  pointer("pressed"); tick(10); events["game.ready"]()
  noHold(); tick(60); eq(ow.player.cellX, 51)
end)
test("free-look voxel camera rejects input and explains why", function()
  projected = true; voxelLevel = 6
  eq(pointer("pressed"), false)
  eq(#warnings, 1)
  warnings = {}
  tick(40); eq(#steps, 0)
end)
test("switching to free-look during steering cancels hold", function()
  pointer("pressed"); tick(10)
  projected = true; voxelLevel = 7
  hooks:call("input.step", noop, game, 1/60)
  noHold(); eq(#warnings, 1); warnings = {}
  projected = false; tick(50); eq(ow.player.cellX, 51)
end)
for _, case in ipairs({
  {"tilt east", "tilt", 700, 360, "right"},
  {"tilt south", "tilt", 480, 580, "down"},
  {"voxel-orbit west", "voxel", 260, 360, "left"},
  {"voxel-orbit north", "voxel", 480, 140, "up"},
}) do
  test("centre-anchor steering drives " .. case[1], function()
    if case[2] == "tilt" then tilted = true else projected = true end
    render()
    pointer("pressed", nil, nil, {gameX = case[3], gameY = case[4]})
    tick(120)
    assert(#steps >= 4, "held steering stopped")
    for _, step in ipairs(steps) do eq(step, case[5]) end
  end)
end
test("invalid drag clears input and reports", function()
  pointer("pressed"); tick(10)
  pointer("moved", nil, nil, {gameX=0/0})
  noHold(); eq(#warnings, 1); warnings = {}
  tick(40); eq(ow.player.cellX, 51)
end)

local function uiFrame(state, anchors)
  if state then game.stack:push(state) end
  game.renderer.frameRects = function()
    return {uox=80,uoy=30,Ux=3,Uy=2,uiw=160,uih=144,
      vux=0,vuy=0,vuw=960,vuh=620}
  end
  game.renderer.uiAnchors = anchors
  render()
end
local function uiPointer(phase, x, y, button, absolute)
  return hooks:call("input.pointer", function() return false end, game, {
    phase=phase, source="mouse", id="mouse", button=button or 1,
    gameX=x,gameY=y,x=absolute and x or x+317,y=absolute and y or y+129,
    insideGame=not absolute,
  })
end
local function clickUI(x, y, button)
  local used=uiPointer("pressed",80+x*3,30+y*2,button)
  uiPointer("released",80+x*3,30+y*2,button)
  tick(2)
  return used
end
local function drawDock()
  hooks:call("render.viewport", function(ctx)
    return {x=0,y=0,width=ctx.width,height=ctx.height}
  end, {width=960,height=720})
  hooks:call("render.window", noop, game, {})
end
local function clickDock(index, phase)
  local cols=6
  local x=((index-1)%cols+0.5)*960/cols
  local y=608+math.floor((index-1)/cols)*32+16
  return uiPointer(phase or "pressed",x,y,1,true)
end
local Menu=require("src.ui.Menu")
local ListMenu=require("src.ui.ListMenu")
local ChoiceBox=require("src.ui.ChoiceBox")
local NamingScreen=require("src.ui.NamingScreen")
local TextBox=require("src.render.TextBox")
local TitleState=require("src.ui.TitleState")
local IntroMovie=require("src.ui.IntroMovie")
local YellowIntro=require("src.ui.YellowIntro")
local function worldFixture(dx,dy)
  local npc={cellX=50+dx,cellY=50+dy,def={}}
  ow.npcs,ow.entities={npc},{npc}
  ow.interact=ow.nativeInteract
  local calls={}
  ow.talkTo=function(_,target) calls[#calls+1]=target end
  ow.showMapText=function(_,text) calls[#calls+1]=text end
  ow.tryCardKeyDoor=function() return false end
  ow.tryHiddenObject=function() return false end
  ow.tryBookshelf=function() return false end
  return npc,calls
end
for _,case in ipairs({{"up",0,-1},{"down",0,1},{"left",-1,0},{"right",1,0}}) do
  test("adjacent NPC click faces "..case[1].." then uses native interaction",function()
    local npc,calls=worldFixture(case[2],case[3])
    ow.player.turnArmed=false
    pointer("pressed",case[2]*16,case[3]*16)
    pointer("released",case[2]*16,case[3]*16); tick(5)
    eq(ow.player.facing,case[1]); eq(calls[1],npc); eq(#calls,1)
    eq(ow.player.cellX,50); eq(ow.player.cellY,50); eq(#steps,0); noHold()
  end)
end
for _,case in ipairs({{"up",0,-1,480,140},{"down",0,1,480,580},{"left",-1,0,260,360},{"right",1,0,700,360}}) do
  test("voxel-orbit NPC click faces "..case[1].." via direction",function()
    projected=true
    local npc,calls=worldFixture(case[2],case[3])
    ow.player.turnArmed=false
    render()
    pointer("pressed",nil,nil,{gameX=case[4],gameY=case[5]})
    pointer("released",nil,nil,{gameX=case[4],gameY=case[5]}); tick(5)
    eq(ow.player.facing,case[1]); eq(calls[1],npc); eq(#calls,1)
    eq(ow.player.cellX,50); eq(ow.player.cellY,50); eq(#steps,0); noHold()
  end)
end
test("held object click interacts once and never resumes steering",function()
  local npc,calls=worldFixture(1,0)
  pointer("pressed",16,0); tick(10)
  pointer("moved",70,0); tick(60)
  eq(calls[1],npc); eq(#calls,1); eq(#steps,0)
end)
test("clicking a sign uses map text and never steps onto a passable sign cell",function()
  local _,calls=worldFixture(3,0)
  ow.map.signs={["51_50"]={text="SIGN"}}
  pointer("pressed",16,4); pointer("released",16,4); tick(5)
  eq(calls[1],"SIGN"); eq(ow.player.cellX,50); eq(#steps,0)
end)
test("item-ball clicks enter the native NPC interaction path",function()
  local npc,calls=worldFixture(1,0)
  npc.def.item="POTION"
  pointer("pressed",16,0); pointer("released",16,0); tick(5)
  eq(calls[1],npc); eq(npc.def.item,"POTION")
end)
test("nurse across a single counter is clickable",function()
  local npc,calls=worldFixture(0,-2)
  ow.map.counters={["50_49"]=true}
  pointer("pressed",0,-32); pointer("released",0,-32); tick(5)
  eq(calls[1],npc); eq(#steps,0)
end)
test("solid scenery dispatches native hidden-object interaction",function()
  local _,calls=worldFixture(3,0)
  ow.map=map("room",function(x,y) return x==50 and y==49 end)
  ow.tryHiddenObject=function(_,x,y)
    eq(x,50); eq(y,49); calls[#calls+1]="PC"; return true
  end
  pointer("pressed",0,-12); pointer("released",0,-12); tick(5)
  eq(calls[1],"PC"); eq(#steps,0)
end)
test("sprite-head clicks use world scaling and camera offsets not UI scale",function()
  local npc,calls=worldFixture(1,0)
  game.renderer.wipeWox,game.renderer.wipeWoy=75,45
  game.renderer.wipeSx,game.renderer.wipeSy=2.5,1.5
  uiFrame(); pointer("pressed",16,-7); pointer("released",16,-7); tick(5)
  eq(calls[1],npc); eq(#steps,0)
end)
test("distant NPC click keeps steering instead of interacting",function()
  local _,calls=worldFixture(4,0)
  pointer("pressed",64,0); tick(45)
  eq(#calls,0); assert(#steps>0)
end)
test("diagonal NPC click keeps steering instead of remote interaction",function()
  local _,calls=worldFixture(1,1)
  pointer("pressed",16,16); tick(45)
  eq(#calls,0); assert(#steps>0)
end)
test("removed NPC cannot receive a queued interaction",function()
  local _,calls=worldFixture(1,0)
  pointer("pressed",16,0); tick()
  ow.npcs={}; tick(5); eq(#calls,0); noHold()
end)
test("NPC starting to walk cancels a queued interaction",function()
  local npc,calls=worldFixture(1,0)
  pointer("pressed",16,0); tick()
  npc.moving=true; tick(5); eq(#calls,0)
end)
test("queued interaction cannot follow a map or player replacement",function()
  local _,calls=worldFixture(1,0)
  pointer("pressed",16,0)
  ow.map=map("new"); tick(5); eq(#calls,0); noHold()
end)
test("right-click cancels a pending turn-and-interact",function()
  local _,calls=worldFixture(1,0)
  ow.player.turnArmed=false
  pointer("pressed",16,0); tick()
  pointer("pressed",16,0,{button=2}); tick(5)
  eq(#calls,0); noHold()
end)
test("focus loss cancels interaction even while its pointer is captured",function()
  local _,calls=worldFixture(1,0)
  pointer("pressed",16,0); pointer("cancelled"); tick(5)
  eq(#calls,0); noHold()
end)
test("physical input takes priority over turn-and-interact",function()
  local _,calls=worldFixture(1,0)
  pointer("pressed",16,0)
  game.input:sourcePress("b","keyboard"); tick(5); eq(#calls,0)
  assert(game.input:isDown("b")); game.input:sourceRelease("b","keyboard")
end)
test("world clicks obey the mouse UI toggle",function()
  local _,calls=worldFixture(1,0)
  options.mouse_ui=false
  pointer("pressed",16,0); tick(40); eq(#calls,0)
end)
test("scripts retain control over adjacent object clicks",function()
  local _,calls=worldFixture(1,0)
  ow.runner.isRunning=function() return true end
  pointer("pressed",16,0); pointer("released",16,0); tick(5)
  eq(#calls,0); eq(#steps,0); noHold()
end)
test("changed sign identity cancels its queued confirmation",function()
  local _,calls=worldFixture(3,0)
  ow.map.signs={["51_50"]={text="OLD"}}
  pointer("pressed",16,4); tick()
  ow.map.signs["51_50"]={text="NEW"}; tick(5); eq(#calls,0)
end)
test("adjacent clicks never rotate a player in the middle of a step",function()
  local _,calls=worldFixture(0,-1)
  ow.player.facing="right"; ow.player.turnTimer=0
  ow.player:tryMove("right",ow.map,ow.entities)
  assert(ow.player.moving)
  pointer("pressed",0,-16); tick()
  eq(ow.player.facing,"right"); eq(#calls,0)
end)
local function titleFixture(yellow)
  local state=setmetatable({game=game,phase="loop",menuOpen=false,
    yellowLayout=yellow,timer=0,blink=0,updateBlink=noop,updateCycle=noop,
    cycleSpecies={"PIKACHU"},cycleIndex=1,updateSequence=noop},TitleState)
  uiFrame(state)
  return state
end
test("Yellow title click runs the normal Pikachu cry transition",function()
  local state=titleFixture(true)
  assert(clickUI(80,60)); eq(state.phase,"exitCry"); noHold()
end)
test("Red and Blue title click runs the normal title transition",function()
  local state=titleFixture(false)
  assert(clickUI(80,60)); eq(state.phase,"exitCry")
end)
test("title animation does not consume clicks or queue a later confirmation",function()
  local state=titleFixture(true)
  state.phase="drop"; render()
  eq(clickUI(80,60),false)
  state.phase="loop"; tick()
  eq(state.phase,"loop")
end)
test("title click cannot leak into an overlay menu",function()
  titleFixture(true)
  uiPointer("pressed",80+80*3,30+60*2)
  game.stack:push(Menu.new(game,{{label="NEW GAME",
    onSelect=function() error("stale title click") end}}))
  tick(); assert(not game.input:wasPressed("a"))
end)
test("Yellow intro click uses its native skip handler",function()
  local state=setmetatable({game=game,pendingDelay=0,
    exitToTitle=function(self) self.finished=true end},YellowIntro)
  uiFrame(state); assert(clickUI(80,60)); assert(state.finished)
end)
test("Yellow intro delays cannot retain clicks",function()
  local state=setmetatable({game=game,pendingDelay=4,updateObjects=noop,
    exitToTitle=function() error("must not skip delay") end},YellowIntro)
  uiFrame(state); eq(clickUI(80,60),false); eq(state.pendingDelay,2)
end)
test("Red and Blue intro click uses its native skip handler",function()
  local state=setmetatable({game=game,phase=3,timer=10,
    exitToTitle=function(self) self.phase=4 end},IntroMovie)
  uiFrame(state); assert(clickUI(80,60)); eq(state.phase,4)
end)
test("copyright card keeps its native delay even when clicked",function()
  local state=setmetatable({game=game,phase=1,timer=0},IntroMovie)
  uiFrame(state); clickUI(80,60); eq(state.phase,1); eq(state.timer,2)
end)
test("Yellow pre-intro uses the native splash skip",function()
  local pre=setmetatable({game=game,phase=2,timer=90,
    startPhase=function(self,phase) self.phase=phase end,fightStep=noop},IntroMovie)
  local state=setmetatable({game=game,pre=pre},YellowIntro)
  uiFrame(state); assert(clickUI(80,60)); eq(pre.phase,3)
end)
test("queued Yellow pre-intro click cannot cross a splash phase",function()
  local pre=setmetatable({game=game,phase=2,timer=90,
    exitToTitle=function() error("stale pre-intro click") end,fightStep=noop},IntroMovie)
  local state=setmetatable({game=game,pre=pre},YellowIntro)
  uiFrame(state); uiPointer("pressed",80+80*3,30+60*2)
  pre.phase=3; tick(); assert(not game.input:wasPressed("a"))
end)
test("custom title drawing does not inherit native click targets",function()
  local state=titleFixture(true)
  state.draw=noop; render(); eq(clickUI(80,60),false); eq(state.phase,"loop")
end)
test("Continue information click uses the native confirmation",function()
  local state=titleFixture(true)
  state.menuOpen=true
  local loaded=false
  state.onContinue=function() loaded=true end
  local version=require("src.core.GameVersion")
  local previousGet, previousSaveData, previousFs =
    version.get, package.loaded["src.core.SaveData"], love.filesystem
  version.get=function() return "yellow" end
  package.loaded["src.core.SaveData"]={
    saveFilename=function() return "save_yellow.lua" end,
    load=function() return {player={name="YELLOW"}} end}
  love.filesystem={getInfo=function() return {} end}
  state:openMenu(); render(); clickUI(24,18)
  assert(game.stack:top().title == state)
  assert(not loaded)
  eq(clickUI(8,140),false); assert(not loaded)
  assert(clickUI(80,90,2)); assert(not loaded)
  assert(game.stack:top().items); render(); assert(clickUI(24,18))
  assert(clickUI(80,90)); assert(loaded)
  version.get,package.loaded["src.core.SaveData"],love.filesystem =
    previousGet,previousSaveData,previousFs
end)

test("native Menu direct row uses normal confirmation",function()
  local picked
  uiFrame(Menu.new(game,{
    {label="FIRST",onSelect=function() picked=1 end},
    {label="SECOND",onSelect=function() picked=2 end},
  },{tx=0,ty=0,tw=20}))
  assert(clickUI(24,34))
  eq(picked,2); eq(game.stack:top(),ow)
end)
test("right-click cancels Menu through native B",function()
  local cancelled=false
  uiFrame(Menu.new(game,{{label="KEEP"}},{onCancel=function() cancelled=true end}))
  clickUI(5,5,2)
  assert(cancelled); eq(game.stack:top(),ow)
end)
test("noncancelable Menu still refuses right-click",function()
  local menu=Menu.new(game,{{label="KEEP"}},{cancelable=false})
  uiFrame(menu); clickUI(5,5,2)
  eq(game.stack:top(),menu)
end)
test("scrolled Menu row uses visible item identity",function()
  local picked
  local items={}
  for i=1,8 do
    local value=i
    items[i]={label="ROW "..i,onSelect=function() picked=value end}
  end
  local menu=Menu.new(game,items,{tx=0,ty=0,tw=20,maxVisible=3})
  menu.index=6; menu:clampScroll()
  uiFrame(menu); clickUI(24,18); eq(picked,4)
end)
test("stale removed row is never activated",function()
  local picked=false
  local menu=Menu.new(game,{{label="OLD",onSelect=function() picked=true end}},
    {tx=0,ty=0,tw=20})
  uiFrame(menu); uiPointer("pressed",80+24*3,30+18*2)
  menu.items[1]={label="REPLACEMENT",onSelect=function() picked=true end}
  tick(2); assert(not picked)
end)
test("native ListMenu visible item click",function()
  local picked
  local menu=ListMenu.new(game,"ITEMS",{
    {label="ONE",value=1},{label="TWO",value=2}
  },{onChoose=function(item) picked=item.value end})
  uiFrame(menu); clickUI(40,42); eq(picked,2)
end)
test("native item-box list click and lookahead protection",function()
  local picked
  local items={}
  for i=1,6 do items[i]={label="ITEM "..i,value=i} end
  local menu=ListMenu.new(game,"ITEMS",items,{itemBox=true,onChoose=function(item) picked=item.value end})
  uiFrame(menu); clickUI(55,50); eq(picked,2)
end)
test("dialogue click advances without moving player",function()
  local done=false
  local box=TextBox.new(game,"HELLO",function() done=true end,{instant=true})
  uiFrame(box); clickUI(8,8); tick(40)
  assert(done); eq(ow.player.cellX,50); eq(ow.player.cellY,50)
end)
test("choice click selects NO without bypassing answer delay",function()
  local answer
  local box=ChoiceBox.new(game,function(yes) answer=yes end)
  uiFrame(box); clickUI(132,82)
  eq(answer,nil); tick(30); eq(answer,false)
end)
test("bottom anchored choice coordinates use UI scale not world scale",function()
  local answer
  local box=ChoiceBox.new(game,function(yes) answer=yes end,{anchor="bottom"})
  uiFrame(box,{{x=112,y=56,w=48,h=40,anchor="bottom"}})
  local x=80+132*3
  local y=620-(144-82)*2
  uiPointer("pressed",x,y); uiPointer("released",x,y); tick(30)
  eq(answer,false)
end)
test("naming grid clicks type delete change case and finish",function()
  local name
  local screen=NamingScreen.new(game,{onDone=function(value) name=value end})
  uiFrame(screen); clickUI(18,42)
  eq(table.concat(screen.glyphs),"A")
  clickUI(34,42); eq(table.concat(screen.glyphs),"AB")
  clickUI(5,5,2); eq(table.concat(screen.glyphs),"A")
  clickUI(20,122); assert(screen.lower)
  clickUI(34,42); eq(table.concat(screen.glyphs),"Ab")
  clickUI(146,106); eq(name,"Ab")
end)
test("unrecognised menu clicks do not blindly confirm",function()
  local pressed=false
  uiFrame({update=function() if game.input:wasPressed("a") then pressed=true end end})
  eq(clickUI(25,30),false); assert(not pressed)
end)
test("level-up stat card click sends A to dismiss it",function()
  local StatBox=require("src.battle.BattleState").StatBox
  local dismissed=false
  local card=setmetatable({game=game,
    update=function() if game.input:wasPressed("a") then dismissed=true end end},StatBox)
  uiFrame(card)
  assert(clickUI(80,60)); tick()
  assert(dismissed)
end)
test("caught Pokedex data page click sends A to advance and close it",function()
  local DexEntryMenu=require("src.ui.DexEntryMenu")
  local advanced=false
  local page=setmetatable({game=game,
    update=function() if game.input:wasPressed("a") then advanced=true end end},DexEntryMenu)
  uiFrame(page)
  assert(clickUI(80,60)); tick()
  assert(advanced)
end)
test("pending input cannot cross a battle phase on same state",function()
  local state={phase="menu",update=function() end}
  uiFrame(state)
  uiPointer("pressed",100,100,2)
  state.phase="messages"; tick()
  assert(not game.input:wasPressed("b"))
end)
test("physical input wins over a pending click",function()
  local picked=false
  uiFrame(Menu.new(game,{{label="ROW",onSelect=function() picked=true end}},
    {tx=0,ty=0,tw=20}))
  uiPointer("pressed",80+24*3,30+18*2)
  game.input:sourcePress("up","keyboard:up")
  tick(2); assert(not picked); assert(game.input:isDown("up"))
  game.input:sourceRelease("up","keyboard:up")
end)
test("action dock reserves space without covering dialogue",function()
  local result=hooks:call("render.viewport",function()
    return {x=17,y=29,width=900,height=660}
  end,{width=960,height=720})
  eq(result.x,17); eq(result.y,29); eq(result.height,548); assert(result.capture)
end)
test("dock menu works outside game viewport",function()
  drawDock(); assert(clickDock(3)); clickDock(3,"released"); tick(2)
  assert(game.stack:top().menu); noHold()
end)
test("dock interact waits for the current native walking step",function()
  pointer("pressed"); tick(10)
  drawDock(); clickDock(1); clickDock(1,"released")
  tick(30); assert(game.stack:top().dialog); eq(ow.player.cellX,51)
end)
test("dock directional hold navigates and cancels on focus loss",function()
  local menu=Menu.new(game,{{label="ONE"},{label="TWO"},{label="THREE"}})
  uiFrame(menu); drawDock(); clickDock(6); tick(30)
  assert(menu.index~=1)
  uiPointer("cancelled",96,677,1,true); noHold()
end)
test("disabling mouse UI cancels queued dock actions",function()
  drawDock(); clickDock(3); options.mouse_ui=false; tick(2)
  eq(game.stack:top(),ow); noHold()
end)
local function catchingFixture()
  local c={cancelled=0,cycled=0,mod={}}
  c.catchInput={reset=function(_,_,cancel) if cancel then c.cancelled=c.cancelled+1 end end}
  c.CatchBindings={throwCombo=function() return {modifier="select",action="a"} end}
  function c:cycleSelectedBall(_,direction) self.cycled=self.cycled+direction end
  registry.overworld_wild_spawns={exports={
    overworldCatchingEnabled=function() return true end, catching=c}}
  return c
end
test("Wilds throw uses configured combo and normal release",function()
  local c=catchingFixture()
  drawDock(); clickDock(11)
  assert(game.input:isDown("select")); assert(game.input:isDown("a"))
  clickDock(11,"released")
  noHold(); eq(c.cancelled,0)
end)
test("right-click cancels Wilds charge without releasing a throw",function()
  local c=catchingFixture()
  drawDock(); clickDock(11)
  uiPointer("pressed",560,677,2,true)
  noHold(); eq(c.cancelled,1)
end)
test("dragging out of dock cancels Wilds charge",function()
  local c=catchingFixture()
  drawDock(); clickDock(11)
  uiPointer("moved",560,600,1,true)
  noHold(); eq(c.cancelled,1)
end)
test("Wilds next ball invokes owned exported cycler",function()
  local c=catchingFixture()
  drawDock(); clickDock(12); clickDock(12,"released"); tick(2)
  eq(c.cycled,1)
end)
test("existing higher-priority pointer handlers keep game clicks",function()
  local selected=false
  uiFrame(Menu.new(game,{{label="NATIVE",onSelect=function() selected=true end}},
    {tx=0,ty=0,tw=20}))
  hooks:wrap("input.pointer",function() return true end,1000,"existing-ui")
  clickUI(24,18); assert(not selected)
end)
local Battle=assert(load([[
  local Timing, Runtime, Party = ...
  local WideBattle={navigate=function() return nil end}
  local BattleState={}
]]..BATTLE_UPDATE_SOURCE.."\n"..BATTLE_UPDATEQUEUE_SOURCE.."\n"
  ..BATTLE_BEGINMSGLINE_SOURCE.."\n"..BATTLE_OPENPARTY_SOURCE.."\nreturn BattleState"))(
  require("src.core.Timing"),require("src.mods.Runtime"),{firstHealthy=function() return true end})
Battle.__index=Battle
package.loaded["src.battle.BattleState"]=Battle
local function battleFixture(phase, wide)
  local state=setmetatable({isBattle=true,game=game,data=game.data,phase=phase or "menu",
    menuIndex=1,moveIndex=1,mimicIndex=1,
    player={mon={hp=10},curMoves={{id="TACKLE",pp=35},{id="GROWL",pp=40}}},
    mimicMoves={{id="TACKLE",pp=35},{id="GROWL",pp=40}},
    tickFx=noop,clearTurnFlinches=noop,updateQueue=function() return true end,
    menuLockedAction=function() return false end,
    bottomUIVisible=function(self)
      return hooks:call("battle.bottom_ui_visible",function() return true end,self)
    end,
    wideLayout=function() return wide or false end,
    moveGridNavigation=function() return wide or false end,
    chooseMenu=function(self,value) self.chosen=value; self.phase="messages" end,
    chooseMove=function(self,value) self.chosen=value; self.phase="messages" end,
    chooseMimic=function(self,value) self.chosen=value; self.phase="messages" end,
    chooseSafari=function(self,value) self.chosen=value; self.phase="messages" end,
    cancelMove=function(self) self.phase="menu" end},Battle)
  uiFrame(state)
  return state
end
for index, command in ipairs({"fight","party","item","run"}) do
  test("classic battle click dispatches native "..command,function()
    local state=battleFixture()
    clickUI(80+((index-1)%2)*48,114+math.floor((index-1)/2)*16)
    eq(state.chosen,command)
  end)
end
test("wide battle click dispatches native item",function()
  local state=battleFixture("menu",true)
  clickUI(176,130); eq(state.chosen,"item")
end)
test("native move click and B cancellation",function()
  local state=battleFixture("moveSelect")
  clickUI(50,114); eq(state.chosen,2)
  state.phase="moveSelect"; render(); clickUI(10,10,2)
  eq(state.phase,"menu")
end)
test("Mimic cannot be cancelled with B",function()
  local state=battleFixture("mimicSelect")
  clickUI(10,10,2); eq(state.phase,"mimicSelect")
  clickUI(20,74); eq(state.chosen,2)
end)
test("Safari click uses Safari native action order",function()
  local state=battleFixture()
  state.safari={balls=10}; render()
  clickUI(112,114); eq(state.chosen,"bait")
end)
test("hidden battle commands have no ghost click targets",function()
  local state=battleFixture()
  hooks:wrap("battle.bottom_ui_visible",function() return false end,1000)
  render(); clickUI(80,114); eq(state.chosen,nil)
end)
test("old-man demonstration ignores direct battle clicks",function()
  local state=battleFixture()
  state.demo=true; render()
  clickUI(80,114); eq(state.chosen,nil)
end)
local function messageFixture(demo, wide)
  local state=battleFixture("messages",wide)
  state.demo=demo
  state.current={text="PIKACHU was caught!"}
  state.shown={{1,2}}
  state.codes={1,2}
  state.lines={{codes={1,2}},{codes={3,4},cont=true}}
  state.lineIndex=2
  state.charIndex=2
  state.queue={}
  state.msgPrompt=true
  state.msgPromptWait=0
  state.updateQueue=Battle.updateQueue
  state.beginMsgLine=Battle.beginMsgLine
  render()
  return state
end
test("Yellow Oak catching-demo prompt accepts a click anywhere",function()
  local state=messageFixture(true)
  assert(clickUI(8,8))
  eq(state.current,nil); eq(state.msgPrompt,nil); assert(state.msgHold)
  eq(state.chosen,nil); noHold()
end)
test("normal wide battle prompt accepts a click outside its text box",function()
  local state=messageFixture(false,true)
  assert(clickUI(8,8)); eq(state.current,nil)
end)
test("demo CONT dialogue advances through the native scroll wait",function()
  local state=messageFixture(true)
  state.lineIndex=1; state.msgPrompt=nil; state.msgWaiting=true; state.msgPreWait=0
  render(); assert(clickUI(8,8))
  eq(state.msgWaiting,nil); eq(state.lineIndex,2)
  assert(state.waitFrames>0); eq(state.chosen,nil)
end)
test("demo-owned TextBox dialogue is clickable but its scripted bag is not",function()
  local state=battleFixture()
  state.demo=true
  local done=false
  local box=TextBox.new(game,"HELLO",function() done=true end,{instant=true})
  game.stack:push(box); render()
  assert(clickUI(8,8)); assert(done); eq(game.stack:top(),state)
  local menu=Menu.new(game,{{label="BALL",onSelect=function() error("script owns this") end}},
    {tx=0,ty=0,tw=20})
  game.stack:push(menu); render()
  eq(clickUI(24,18),false)
end)
for _, gate in ipairs({"msgPromptWait","waitFrames","introSlide"}) do
  test("battle dialogue click respects "..gate,function()
    local state=messageFixture(true)
    state[gate]=20; render()
    eq(clickUI(8,8),false); assert(state.current)
  end)
end
test("battle dialogue click respects sounds and animations",function()
  local state=messageFixture(true)
  state.waitingSound={isPlaying=function() return true end}
  render(); eq(clickUI(8,8),false); assert(state.current)
  state.waitingSound=nil; state.animPlaying=true
  state.animPlayer={update=noop,isDone=function() return false end}
  render(); eq(clickUI(8,8),false); assert(state.current)
end)
test("queued battle dialogue click cannot advance a replaced message",function()
  local state=messageFixture(true)
  uiPointer("pressed",80+8*3,30+8*2)
  state.current={text="NEW MESSAGE"}
  tick(); assert(state.current); assert(not game.input:wasPressed("a"))
end)
test("queued battle dialogue click cannot cross a CONT boundary",function()
  local state=messageFixture(true)
  state.lineIndex=1; state.msgPrompt=nil; state.msgWaiting=true
  render(); uiPointer("pressed",80+8*3,30+8*2)
  state.msgWaiting=nil; state.msgPrompt=true; state.lineIndex=2
  tick(); assert(state.current); assert(not game.input:wasPressed("a"))
end)
test("hidden and link-owned battle dialogue have no fallback targets",function()
  local state=messageFixture(false)
  hooks:wrap("battle.bottom_ui_visible",function() return false end,1000)
  render(); eq(clickUI(8,8),false); assert(state.current)
  state.kind="link"; render(); eq(clickUI(8,8),false)
end)
test("modern party cards select only the clicked cursor",function()
  local state={modernPartyUI=true,index=1,party={{id="ONE"},{id="TWO"}},
    modernPartyLayoutInfo=function()
      return {width=160,footerY=136,capacity=6,columns=2,rows=3,contentHeight=120}
    end,
    update=function(self) if game.input:wasPressed("a") then self.chosen=self.index end end}
  uiFrame(state); clickUI(120,30); eq(state.chosen,2)
end)
local function partyFixture(style, extra)
  local PartyMenu=require("src.ui.PartyMenu")
  local party={{id="ONE",hp=20,moves={}}, {id="TWO",hp=20,moves={}}}
  local battle={isBattle=true,phase="menu",playerParty=party,player={mon=party[1],name="ONE"}}
  local result={calls=0}
  function battle:playerPartyView() return self.playerParty end
  function battle:ui(create) game.stack:push(create()) end
  function battle:buildScreen(name,opts)
    eq(name,"PartyMenu")
    opts.onCancel=function() result.cancelled=true end
    for key,value in pairs(extra or {}) do opts[key]=value end
    return PartyMenu.new(game,opts)
  end
  function battle:resolveSwitch(mon) result.calls=result.calls+1; result.mon=mon end
  function battle:romText(key,text,...)
    result.refusal=key
    return string.format(text,...)
  end
  game.save.party=party
  game.stack:push(battle)
  Battle.openParty(battle)
  local state=game.stack:top()
  if style=="modern" then
    state.modernPartyUI=true
    state.modernPartyLayoutInfo=function()
      return {width=160,footerY=136,capacity=6,columns=2,rows=3,contentHeight=120}
    end
  elseif style=="wild" then
    state.draw=noop
    state.gen1wildTheme="party"
    registry.gen1_wild_ui={exports={features={gen1party={exports={
      geometry={ROW_H=16,BODY_TOP=24,BODY_BOTTOM=119}}}}}}
  end
  uiFrame()
  return state,result
end
local function openPartyPopup(style,state)
  if style=="modern" then clickUI(120,30)
  else clickUI(40,style=="wild" and 44 or 28) end
  eq(state.index,2); assert(state.submenu); eq(state.subItems[1].action,"battle_switch")
  tick(2)
end
local function popupPoint(style,row)
  return style=="modern" and 60 or 112,
    (style=="modern" and 54 or style=="wild" and 88 or 96)
      +(row-1)*(style=="modern" and 12 or 16)
end
for _,style in ipairs({"native","modern","wild"}) do
  test(style.." battle party popup switches through native A",function()
    local state,result=partyFixture(style)
    openPartyPopup(style,state)
    local x,y=popupPoint(style,1)
    assert(clickUI(x,y)); eq(result.calls,1); eq(result.mon,state.party[2])
    assert(game.stack:top()~=state)
    tick(2); noHold(); eq(result.calls,1)
  end)
  test(style.." battle party popup STATS does not switch",function()
    local state,result=partyFixture(style)
    openPartyPopup(style,state)
    clickUI(popupPoint(style,2))
    eq(game.stack:top().screen,"SummaryMenu")
    eq(game.stack:top().mon,state.party[2]); eq(result.calls,0)
  end)
  test(style.." battle party popup CANCEL does not switch",function()
    local state,result=partyFixture(style)
    openPartyPopup(style,state)
    clickUI(popupPoint(style,3))
    assert(result.cancelled); eq(result.calls,0); assert(game.stack:top()~=state)
  end)
  for _,invalid in ipairs({"active","fainted"}) do
    test(style.." party SWITCH preserves native "..invalid.." refusal",function()
      local state,result=partyFixture(style)
      openPartyPopup(style,state)
      if invalid=="active" then state.index=1 else state.party[2].hp=0 end
      render()
      clickUI(popupPoint(style,1))
      eq(result.calls,0)
      eq(result.refusal,invalid=="active" and "_AlreadyOutText" or "_NoWillText")
      assert(game.stack:top()~=state); eq(state.submenu,nil)
      eq(game.stack.states[#game.stack.states-1],state)
    end)
  end
  local changes={
    selection=function(s) s.index=1 end,
    member=function(s) s.party[2]={id="THREE",hp=20,moves={}} end,
    party=function(s) s.party={s.party[1],s.party[2]} end,
    list=function(s) s.subItems={s.subItems[1],s.subItems[2],s.subItems[3]} end,
    action=function(s) s.subItems[1].action="cancel" end,
    cursor=function(s) s.subIndex=2 end,
    closed=function(s) s.submenu=nil end,
    phase=function(s) s.battle.phase="menu" end,
    callback=function(s) s.onSwitch=function() error("stale callback") end end,
    physical=function() game.input:sourcePress("left","keyboard") end,
    focus=function() uiPointer("cancelled",0,0) end,
  }
  for name,change in pairs(changes) do
    test(style.." pending party switch cancels on changed "..name,function()
      local state,result=partyFixture(style)
      openPartyPopup(style,state)
      local x,y=popupPoint(style,1)
      assert(uiPointer("pressed",80+x*3,30+y*2))
      uiPointer("released",80+x*3,30+y*2)
      change(state); tick(2)
      eq(result.calls,0); assert(not result.cancelled); noHold()
      assert(not game.input:wasPressed("a"))
    end)
  end
  test(style.." party popup blocks clicks on cards behind it",function()
    local state,result=partyFixture(style)
    openPartyPopup(style,state)
    eq(clickUI(40,30),false); eq(state.index,2); eq(result.calls,0)
  end)
  test(style.." forced replacement still selects without a popup",function()
    local state,result=partyFixture(style,{forceSwitch=true})
    if style=="modern" then clickUI(120,30)
    else clickUI(40,style=="wild" and 44 or 28) end
    eq(result.calls,1); eq(result.mon,state.party[2]); assert(not state.submenu)
  end)
end
test("unknown party redraw does not receive guessed native popup targets",function()
  local state,result=partyFixture("native")
  openPartyPopup("native",state)
  state.draw=noop; render()
  eq(clickUI(112,96),false); eq(result.calls,0)
end)
test("Gen1Party carry and unknown geometry get no party click targets",function()
  local state,result=partyFixture("wild")
  state.moveFrom=1; render()
  eq(clickUI(40,44),false); eq(result.calls,0)
  state.moveFrom=nil
  registry.gen1_wild_ui.exports.features.gen1party.exports.geometry.ROW_H=20
  render(); eq(clickUI(40,44),false); eq(result.calls,0)
end)
test("native field submenu follows dynamic height and field-move width",function()
  local state,result=partyFixture("native")
  openPartyPopup("native",state)
  state.subItems={
    {label="SOFTBOILED",action="softboiled"},{label="STATS",action="stats"},
    {label="SWITCH",action="switch"},{label="CANCEL",action="cancel"}}
  render()
  clickUI(72,130)
  assert(result.cancelled); eq(result.calls,0)
end)
test("modern Pokedex visible rows match scrolled items",function()
  game.renderer.uiSize=function() return 160,144 end
  local state={modernPokedexUI=true,index=1,scroll=1,items={{},{},{},{}},
    update=function(self) if game.input:wasPressed("a") then self.chosen=self.index end end}
  uiFrame(state); clickUI(50,49); eq(state.chosen,3)
end)
test("choice that changes before the tick cannot leak A",function()
  local box=ChoiceBox.new(game,function() error("must not answer yet") end)
  uiFrame(box); uiPointer("pressed",80+132*3,30+82*2)
  box.pending=true; box.holdFrames=15; tick()
  assert(not game.input:wasPressed("a")); eq(box.pending,true)
end)
test("G hotkey toggles the steering guide option in the overworld",function()
  eq(options.marker,true)
  game:keypressed("g"); eq(options.marker,false)
  game:keypressed("g"); eq(options.marker,true)
end)
test("G hotkey does nothing when the guide hotkey option is off",function()
  options.guide_hotkey=false
  game:keypressed("g"); eq(options.marker,true)
end)
test("G hotkey is ignored outside the overworld",function()
  game.stack:push({menu=true})
  game:keypressed("g"); eq(options.marker,true)
end)
test("other keys never toggle the steering guide",function()
  game:keypressed("x"); eq(options.marker,true)
end)

local function hasText(fragment)
  for _, text in ipairs(draws.text) do
    if text[1]:find(fragment,1,true) then return true end
  end
  return false
end
test("new gesture and input behaviors are opt-in",function()
  for _, key in ipairs({"click_hold","dialogue_buffer","projected_anchor","four_way"}) do
    eq(options[key],false)
  end
  eq(options.wheel_lists,true,"wheel navigation is enabled by default")
end)
test("guide key can be changed without claiming the old binding",function()
  options.guide_key="h"
  game:keypressed("g"); eq(options.marker,true); eq(previousKeys[1],"g")
  game:keypressed("h"); eq(options.marker,false); eq(#previousKeys,1)
end)
test("guide key yields to native rebound controls and text handlers",function()
  game.input:applyBindings({a={key="g"}})
  game:keypressed("g"); eq(options.marker,true); eq(previousKeys[1],"g")
  game.input:applyBindings(nil)
  ow.onKeyPressed=noop
  game:keypressed("g"); eq(options.marker,true); eq(#previousKeys,2)
end)
test("real engine options without a setter use a visible session override",function()
  mod.options.set=nil
  game:keypressed("g"); eq(options.marker,true)
  pointer("pressed"); tick()
  eq(#draws.lines,0)
  drawDock(); assert(hasText("GUIDE OFF")); assert(hasText("this session"))
  options.marker=false; render()
  game:keypressed("g")
  render(); assert(#draws.lines>0)
end)
for _, mode in ipairs({"throws","returns false","does not persist"}) do
  test("guide setter failure is visible: "..mode,function()
    mod.options.set=function()
      if mode=="throws" then error("fixture setter failure") end
      return mode=="does not persist"
    end
    game:keypressed("g"); eq(#warnings,1); warnings={}
    drawDock(); assert(hasText("Could not update settings")); assert(hasText("GUIDE OFF"))
  end)
end
test("guide persistence accepts nil success and reports failed saves",function()
  game.save.options={}
  game.writeOptions=function() end
  game:keypressed("g"); eq(#warnings,0)
  game.writeOptions=function() error("fixture disk failure") end
  game:keypressed("g"); eq(#warnings,1); warnings={}
  drawDock(); assert(hasText("settings save failed"))
end)
test("guide footer works while a menu owns the keyboard",function()
  game.stack:push({menu=true}); drawDock()
  uiPointer("pressed",900,705,1,true); uiPointer("released",900,705,1,true)
  tick(2); eq(options.marker,false); assert(not game.input:wasPressed("a"))
end)
test("four-way steering never alternates diagonal components",function()
  options.four_way=true
  pointer("pressed",70,60); tick(90)
  assert(#steps>2)
  for _, dir in ipairs(steps) do eq(dir,"right") end
end)
test("precision guide shows a scaled dead zone without suggesting movement",function()
  options.precision_guide=true
  pointer("pressed",1,1); render()
  eq(#draws.lines,0); assert(hasText("PAUSED"))
  local e=draws.ellipses[#draws.ellipses]
  eq(e[4],18); eq(e[5],18)
  tick(20); eq(#steps,0)
end)
test("high-contrast guide draws configured width above a black outline",function()
  options.guide_contrast=true; options.guide_width=3
  pointer("pressed"); render()
  eq(draws.widths[#draws.widths-1],6); eq(draws.widths[#draws.widths],3)
  eq(#draws.lines,4)
end)
local function projectionFixture(mode)
  tilted, projected = mode=="tilt", mode=="voxel"
  options.projected_anchor=true
  projectionCase={mode=mode,x=240,y=300,scale=4,
    canvas={getWidth=function() return 1920 end,getHeight=function() return 2160 end}}
  game.renderer.frameRects=function()
    return {vux=10,vuy=20,vuw=960,vuh=720,dpiX=2,dpiY=3,
      uox=0,uoy=0,Ux=3,Uy=3,uiw=160,uih=144}
  end
end
test("voxel anchor uses actual composite DPI and survives endFrame clearing the canvas",function()
  projectionFixture("voxel")
  render(); assert(projectionCase.fxCalled); eq(game.renderer.worldOverride,nil)
  eq(projectionCase.observed[1],ow.player.px+8); eq(projectionCase.observed[2],ow.player.py+16)
  pointer("pressed",nil,nil,{gameX=400,gameY=120}); render()
  eq(draws.lines[#draws.lines-1][1],130); eq(draws.lines[#draws.lines-1][2],120)
end)
for _, aa in ipairs({1,2,3}) do
  test("voxel projected anchor accounts for antialiasing factor "..aa,function()
    projectionFixture("voxel"); projectionCase.aa=aa
    render()
    pointer("pressed",nil,nil,{gameX=400,gameY=120}); render()
    eq(draws.lines[#draws.lines-1][1],130); eq(draws.lines[#draws.lines-1][2],120)
  end)
end
test("tilt anchor samples native ground projection and actual render origin",function()
  projectionFixture("tilt"); projectionCase.x=60; projectionCase.y=80
  render()
  eq(projectionCase.observed[1],ow.player.px+8-math.floor(ow.camera.x))
  eq(projectionCase.observed[3],160)
  pointer("pressed",nil,nil,{gameX=400,gameY=189}); render()
  eq(draws.lines[#draws.lines-1][1],197); eq(draws.lines[#draws.lines-1][2],189)
end)
for _, mode in ipairs({"missing","rejected","nonfinite","noCanvas"}) do
  test("voxel projection falls back safely when "..mode,function()
    projectionFixture("voxel"); render()
    if mode=="missing" then projectionCase.skipFx=true
    elseif mode=="rejected" then projectionCase.rejected=true
    elseif mode=="noCanvas" then projectionCase.noCanvas=true
    else projectionCase.x=0/0 end
    pointer("pressed",nil,nil,{gameX=700,gameY=360}); render()
    eq(draws.lines[#draws.lines-1][1],480); eq(draws.lines[#draws.lines-1][2],360)
    eq(#warnings,0)
  end)
end
test("projected anchors are not reused across frames or game-ready",function()
  projectionFixture("voxel"); render()
  projectionCase=nil
  pointer("pressed",nil,nil,{gameX=700,gameY=360}); render()
  eq(draws.lines[#draws.lines-1][1],480)
  events["game.ready"]({game=game}); noHold(); tick()
end)
local function deferredFixture()
  projected=true; options.click_hold=true
  local npc,calls=worldFixture(1,0)
  render()
  pointer("pressed",nil,nil,{gameX=700,gameY=360})
  return npc,calls
end
test("short projected click interacts on release, never on press",function()
  local npc,calls=deferredFixture()
  tick(4); eq(#calls,0); eq(#steps,0)
  pointer("released",nil,nil,{gameX=700,gameY=360})
  tick(5); eq(#calls,1); eq(calls[1],npc); eq(#steps,0)
end)
test("projected long hold transfers to steering without talking",function()
  local _,calls=deferredFixture()
  tick(14)
  pointer("moved",nil,nil,{gameX=480,gameY=580}); tick(75)
  assert(#steps>0); eq(#calls,0)
  pointer("released"); noHold()
end)
test("projected drag starts steering before the hold threshold",function()
  local _,calls=deferredFixture()
  pointer("moved",nil,nil,{gameX=480,gameY=580}); tick(2)
  assert(#steps>0); eq(#calls,0)
end)
for _, reason in ipairs({"physical","right","focus","state","map","target","camera","level","leave"}) do
  test("deferred interaction cancels on "..reason,function()
    local npc,calls=deferredFixture()
    if reason=="physical" then game.input:sourcePress("b","keyboard:b")
    elseif reason=="right" then pointer("pressed",nil,nil,{button=2})
    elseif reason=="focus" then pointer("cancelled")
    elseif reason=="state" then game.stack:push({menu=true})
    elseif reason=="map" then ow.map=map("changed")
    elseif reason=="target" then npc.hidden=true
    elseif reason=="camera" then projected=false
    elseif reason=="level" then voxelLevel=4
    else pointer("moved",nil,nil,{insideGame=false}) end
    tick(2)
    pointer("released",nil,nil,{gameX=700,gameY=360}); tick(15)
    eq(#calls,0); eq(#steps,0)
    if reason=="physical" then game.input:sourceRelease("b","keyboard:b") end
    noHold()
  end)
end
local function wheelFixture()
  options.wheel_lists=true
  local menu=Menu.new(game,{{label="ONE"},{label="TWO"},{label="THREE"},{label="FOUR"}},
    {tx=0,ty=0,tw=20})
  uiFrame(menu)
  uiPointer("moved",100,100)
  return menu
end
test("wheel steps native menu rows with neutral polls and never confirms",function()
  local menu=wheelFixture()
  game:wheelmoved(0,-2); tick(4)
  eq(menu.index,3); eq(game.stack:top(),menu); noHold()
  game:wheelmoved(0,1); tick(2); eq(menu.index,2)
  assert(not game.input:wasPressed("a"))
end)
test("wheel fractional events accumulate without changing zoom or confirming",function()
  local menu=wheelFixture()
  game:wheelmoved(0,-0.4); tick(); eq(menu.index,1)
  game:wheelmoved(0,-0.6); tick(2); eq(menu.index,2)
end)
test("separate wheel notches receive distinct native key presses",function()
  local menu=wheelFixture()
  game:wheelmoved(0,-1); tick(); eq(menu.index,2)
  game:wheelmoved(0,-1); tick(); eq(menu.index,2)
  tick(2); eq(menu.index,3); noHold()
end)
test("physical input clears fractional wheel intent as well as whole steps",function()
  local menu=wheelFixture()
  game:wheelmoved(0,-0.5)
  game.input:sourcePress("left","keyboard:left"); tick()
  game.input:sourceRelease("left","keyboard:left"); tick()
  game:wheelmoved(0,-0.5); tick(2); eq(menu.index,1)
end)
test("wheel is opt-in and yields the original return value",function()
  local menu=wheelFixture()
  options.wheel_lists=false
  wheelBehavior=function() return "original" end
  eq(game:wheelmoved(0,-1),"original"); tick(2); eq(menu.index,1)
end)
for _, mode in ipairs({"consumed","cursor","own handler","physical","outside","state","items","reorder","focus","click","disabled"}) do
  test("wheel queue yields or cancels on "..mode,function()
    local menu=wheelFixture()
    if mode=="consumed" then wheelBehavior=function() return true end
    elseif mode=="cursor" then wheelBehavior=function() menu.index=2 end
    elseif mode=="own handler" then menu.onWheelMoved=noop
    elseif mode=="outside" then uiPointer("moved",900,700,1,true)
    end
    game:wheelmoved(0,-3)
    if mode=="physical" then game.input:sourcePress("b","keyboard:b")
    elseif mode=="state" then game.stack:push({menu=true})
    elseif mode=="items" then menu.items={}
    elseif mode=="reorder" then menu.items[2],menu.items[3]=menu.items[3],menu.items[2]
    elseif mode=="focus" then pointer("cancelled")
    elseif mode=="click" then
      hooks:wrap("input.pointer",function() return true end,100)
      uiPointer("pressed",100,100)
    elseif mode=="disabled" then options.wheel_lists=false end
    tick(5)
    eq(menu.index,mode=="cursor" and 2 or 1); noHold()
    if mode=="physical" then game.input:sourceRelease("b","keyboard:b") end
  end)
end
test("unknown or redrawn lists never receive wheel actions",function()
  local menu=wheelFixture()
  menu.draw=noop; render()
  game:wheelmoved(0,-2); tick(4); eq(menu.index,1)
end)
local function bufferedMessage(delay)
  options.dialogue_buffer=true
  local state=messageFixture(false)
  state.msgPromptWait=delay or 4; render()
  assert(clickUI(8,8))
  return state
end
test("early battle click waits for the native prompt and fires once",function()
  local state=bufferedMessage(4)
  assert(state.current); tick(5); eq(state.current,nil)
  tick(3); assert(not game.input:wasPressed("a")); noHold()
end)
test("early click lifetime follows real time under fast-forward",function()
  game.logicSpeed=function() return 4 end
  local state=bufferedMessage(30)
  tick(32); eq(state.current,nil)
end)
test("buffer expires and repeated clicks do not extend the first click",function()
  local state=bufferedMessage(30)
  tick(15); clickUI(8,8)
  tick(16); assert(state.current); assert(not game.input:wasPressed("a"))
  drawDock(); assert(hasText("expired"))
end)
for _, reason in ipairs({"state","message","line","prompt","physical","focus","right","disabled","save"}) do
  test("early battle click cannot cross "..reason,function()
    local state=bufferedMessage(5)
    if reason=="state" then game.stack:push({menu=true})
    elseif reason=="message" then state.current={text="different"}
    elseif reason=="line" then state.lineIndex=1
    elseif reason=="prompt" then state.msgPrompt=nil; state.msgWaiting=true
    elseif reason=="physical" then game.input:sourcePress("left","keyboard:left")
    elseif reason=="focus" then pointer("cancelled")
    elseif reason=="right" then clickUI(8,8,2)
    elseif reason=="disabled" then options.dialogue_buffer=false
    elseif reason=="save" then game.save={} end
    tick(10)
    assert(not game.input:wasPressed("a")); noHold()
    if reason~="right" then assert(state.current) end
    if reason=="physical" then game.input:sourceRelease("left","keyboard:left") end
  end)
end
test("early dialogue click waits out a native text hold",function()
  options.dialogue_buffer=true
  local done=false
  local box=TextBox.new(game,"HELLO",function() done=true end,{instant=true})
  box.holdFrames=4
  uiFrame(box)
  assert(clickUI(8,8)); assert(not done)
  tick(5); assert(done); noHold()
end)
for _, field in ipairs({"pageIndex","lineIndex","choice"}) do
  test("early text click cannot cross a changed "..field,function()
    options.dialogue_buffer=true
    local box=TextBox.new(game,"HELLO",noop,{instant=true})
    box.holdFrames=4; uiFrame(box); assert(clickUI(8,8))
    box[field]=field=="choice" and noop or (box[field] or 1)+1
    tick(5); assert(not game.input:wasPressed("a")); assert(game.stack:top()~=ow); noHold()
  end)
end
test("early clicks never buffer a pending choice or automatic text",function()
  options.dialogue_buffer=true
  local box=TextBox.new(game,"HELLO",noop,{instant=true})
  box.choice=noop; box.holdFrames=4; uiFrame(box)
  eq(clickUI(8,8),false); assert(not game.input:wasPressed("a"))
  box.choice=nil; box.auto={delay=50}; box.holdFrames=4; render()
  eq(clickUI(8,8),false); assert(not game.input:wasPressed("a"))
end)
local function dexFixture()
  local state=setmetatable({game=game,def={},page=1,pageCount=2,
    crySrc={isPlaying=function() return true end}},require("src.ui.DexEntryMenu"))
  uiFrame(state)
  return state
end
test("early Pokedex click waits for cry and advances exactly one native page",function()
  options.dialogue_buffer=true
  local state=dexFixture()
  assert(clickUI(8,8)); eq(state.page,1)
  state.crySrc=nil; tick(3)
  eq(state.page,2); eq(game.stack:top(),state); noHold()
end)
test("Pokedex buffer cannot confirm a changed page or species",function()
  options.dialogue_buffer=true
  local state=dexFixture()
  assert(clickUI(8,8)); state.page=2; state.def={}; state.crySrc=nil
  tick(4); eq(game.stack:top(),state); eq(state.page,2); noHold()
end)
test("Pokedex default still ignores early clicks instead of retaining them",function()
  local state=dexFixture()
  clickUI(8,8); state.crySrc=nil; tick(4); eq(state.page,1)
end)
test("dock controls retain their slots when Wilds is enabled",function()
  drawDock()
  local before={}
  for _, t in ipairs(draws.text) do before[t[1]]={t[2],t[3]} end
  catchingFixture(); drawDock()
  for _, t in ipairs(draws.text) do
    if before[t[1]] then eq(t[2],before[t[1]][1]); eq(t[3],before[t[1]][2]) end
  end
  clickDock(10); clickDock(10,"released"); tick()
  eq(game.stack:top(),ow); drawDock(); assert(hasText("Right-click cancels"))
end)
test("disabled Wilds slots explain requirements without sending game input",function()
  drawDock(); clickDock(11); clickDock(11,"released"); tick(2)
  drawDock(); assert(hasText("requires Wilds")); noHold()
  eq(game.stack:top(),ow)
end)
for _, size in ipairs({"compact","comfortable","large"}) do
  for _, dimensions in ipairs({{960,720},{320,240},{640,480},{240,160}}) do
    test("dock "..size.." remains readable and bounded at "..dimensions[1].."x"..dimensions[2],function()
      options.dock_size=size
      local w,h=dimensions[1],dimensions[2]
      local v=hooks:call("render.viewport",function() return {x=17,y=29,width=w,height=h} end,
        {width=w,height=h})
      hooks:call("render.window",noop,game,{})
      assert(v.height>=h*0.55)
      for _, r in ipairs(draws.rects) do
        assert(r[2]>=17 and r[3]>=29+v.height and r[4]>0 and r[5]>0)
        assert(r[2]+r[4]<=17+w and r[3]+r[5]<=29+h)
      end
      for _, t in ipairs(draws.text) do
        local scale=t[5] or 1
        eq(scale,1,"dock text must not resize an existing font texture")
        assert(t.font:getHeight()>=16,"dock text must remain readable")
        assert(t[2]+t.font:getWidth(t[1])<=17+w+0.001)
        assert(t[3]+t.font:getHeight()<=29+h+0.001)
      end
      if w<300 then assert(hasText("Enlarge")) end
    end)
  end
end
test("small dock pagination exposes all stable controls without gameplay input",function()
  local function smallDock()
    hooks:call("render.viewport",function() return {x=0,y=0,width=320,height=240} end,
      {width=320,height=240})
    hooks:call("render.window",noop,game,{})
  end
  smallDock(); assert(hasText("MORE 1/4"))
  uiPointer("pressed",40,226,1,true); uiPointer("released",40,226,1,true)
  tick(); smallDock(); assert(hasText("MORE 2/4")); assert(hasText("SELECT")); noHold()
end)
test("dock reports waiting and unsupported-screen contexts",function()
  ow.player.inputLocked=true; drawDock(); assert(hasText("Waiting"))
  ow.player.inputLocked=false
  uiFrame({custom=true}); drawDock(); assert(hasText("No direct-click adapter"))
end)
for _, inherited in ipairs({8,12,32,72}) do
  test("dock font is independent of inherited game font size "..inherited,function()
    local font=testFont(inherited)
    currentFont=font
    drawDock()
    eq(currentFont,font,"dock must restore the game's font")
    for _, text in ipairs(draws.text) do
      eq(text[5],nil,"native-size text must not be scaled")
      assert(text.font~=font); assert(text.font.size>=16)
      eq(text[2],math.floor(text[2])); eq(text[3],math.floor(text[3]))
    end
    local count=#fontsCreated
    drawDock(); eq(#fontsCreated,count,"fonts must be cached between frames")
  end)
end
test("dock fonts refresh and align to pixels when display DPI changes",function()
  drawDock()
  local old=fontsCreated[1]
  fontDPI=1.5; draws.text={}
  drawDock(); assert(old.released)
  for _, text in ipairs(draws.text) do
    eq(text.font.dpi,1.5); eq(text.font.hinting,"normal")
    assert(math.abs(text[2]*1.5-math.floor(text[2]*1.5+0.5))<0.0001)
    assert(math.abs(text[3]*1.5-math.floor(text[3]*1.5+0.5))<0.0001)
    eq(text[5],nil)
  end
end)
local function followerFixture(mode, size)
  local npc, calls=worldFixture(1,0)
  npc.px, npc.py=npc.cellX*16,npc.cellY*16
  npc.passable=true
  npc.sprite={def={pokepcFollowerVisualScale=size or 1}}
  ow.follower=npc
  if mode ~= "flat" then
    projectionFixture(mode)
    options.projected_anchor=false
    projectionCase.project=function(x,y)
      if mode=="voxel" then
        return 240+(x-ow.player.px-8)*4,300+(y-ow.player.py-16)*4,0.75
      end
      return x,y
    end
  end
  render()
  local x,y
  if mode=="voxel" then
    x,y=10+304/2,20+(268-8*4*0.75*(size or 1))/3
  elseif mode=="tilt" then
    x=17+(npc.px+8-math.floor(ow.camera.x))*3
    y=29+(npc.py+12-math.floor(ow.camera.y)-8*(size or 1))*2
  else
    x=game.renderer.wipeWox+(npc.px+8-math.floor(ow.camera.x))*game.renderer.wipeSx
    y=game.renderer.wipeWoy+(npc.py+12-math.floor(ow.camera.y)-8*(size or 1))*game.renderer.wipeSy
  end
  return npc,calls,x,y
end
for _, mode in ipairs({"flat","tilt","voxel"}) do
  for _, size in ipairs({0.5,1,2}) do
    test(mode.." follower sprite click interacts at visual scale "..size,function()
      local npc,calls,x,y=followerFixture(mode,size)
      uiPointer("pressed",x,y); uiPointer("released",x,y); tick(5)
      eq(calls[1],npc); eq(#calls,1); eq(ow.player.facing,"right"); eq(#steps,0); noHold()
    end)
  end
  test(mode.." pointing past a follower steers without talking",function()
    local _,calls=followerFixture(mode)
    uiPointer("pressed",850,mode=="flat" and origin.y or 360); tick(24)
    eq(#calls,0); eq(ow.player.facing,"right"); assert(#steps>0)
    uiPointer("released",850,360); tick(); noHold()
  end)
end
for _, change in ipairs({"missing","rejected","moved","hidden","camera","level"}) do
  test("projected follower ignores "..change.." sprite observation",function()
    local npc,calls,x,y=followerFixture("voxel")
    if change=="missing" then projectionCase.skipFx=true; render()
    elseif change=="rejected" then projectionCase.rejected=true; render()
    elseif change=="moved" then npc.px=npc.px+1
    elseif change=="hidden" then npc.hidden=true
    elseif change=="camera" then ow.camera.x=ow.camera.x+1
    else voxelLevel=voxelLevel+1 end
    uiPointer("pressed",x,y); uiPointer("released",x,y); tick(5)
    eq(#calls,0); noHold()
  end)
end
for _, aa in ipairs({2,3}) do
  test("voxel follower hitbox accounts for antialiasing factor "..aa,function()
    local npc,calls,x,y=followerFixture("voxel")
    projectionCase.aa=aa; render()
    uiPointer("pressed",x,y); uiPointer("released",x,y); tick(5)
    eq(calls[1],npc); eq(#calls,1); eq(#steps,0); noHold()
  end)
end
test("queued follower click cancels when its sprite moves",function()
  local npc,calls,x,y=followerFixture("voxel")
  uiPointer("pressed",x,y); uiPointer("released",x,y)
  npc.px=npc.px+1; tick(5); eq(#calls,0); noHold()
end)
test("native Pikachu follower marker uses sprite bounds without an ow.follower alias",function()
  local npc,calls,x,y=followerFixture("voxel")
  ow.follower=nil; npc.pikachuFollower=true
  local follower=require("src.world.PikachuFollower")
  local inner=follower.talk
  follower.talk=function(_,_,target) calls[#calls+1]=target end
  render(); uiPointer("pressed",x,y); uiPointer("released",x,y); tick(5)
  follower.talk=inner
  eq(calls[1],npc); eq(#calls,1); noHold()
end)

local function zoomedChoice(anchor)
  local answer
  local box=ChoiceBox.new(game,function(yes) answer=yes end,
    {box={tx=0,ty=7,tw=6,th=5},anchor=anchor})
  uiFrame(box,anchor and {{x=0,y=56,w=48,h=40,anchor=anchor}} or {})
  frameCase={worldActive=true}
  game.renderer.frameRects=function(self)
    local scale=self.worldActive and 4 or 8
    return {uox=70,uoy=20,Ux=scale/2,Uy=scale/3,uiw=160,uih=144,
      vux=10,vuy=12,vuw=920,vuh=588,dpiX=2,dpiY=3}
  end
  render()
  return box,function() return answer end
end
for _, anchor in ipairs({"center","bottom","topright"}) do
  test("zoomed save CANCEL click and highlight use the displayed "..anchor.." transform",function()
    local box,answer=zoomedChoice(anchor~="center" and anchor or nil)
    eq(game.renderer.worldActive,false)
    local x=(anchor=="topright" and 930-160*2 or 70)+24*2
    local y=(anchor=="bottom" and 600-144*4/3 or anchor=="topright" and 12 or 20)+82*4/3
    uiPointer("moved",x,y); render()
    local found=false
    for _, r in ipairs(draws.rects) do
      if r[1]=="line" and x>=r[2] and x<r[2]+r[4] and y>=r[3] and y<r[3]+r[5] then
        eq(r[4],32*2-2); assert(math.abs(r[5]-(8*4/3-2))<0.0001); found=true
      end
    end
    assert(found,"highlight must cover the drawn CANCEL row")
    uiPointer("pressed",x,y); uiPointer("released",x,y); tick(30)
    eq(answer(),false); noHold()
  end)
end
test("zoomed save click at the old post-endFrame position does not answer",function()
  local _,answer=zoomedChoice()
  uiPointer("pressed",70+24*4,20+82*8/3)
  uiPointer("released",70+24*4,20+82*8/3); tick(30)
  eq(answer(),nil); noHold()
end)
test("UI capture follows zoom changes on the next rendered frame",function()
  local _,answer=zoomedChoice()
  frameCase.worldActive=false; render()
  uiPointer("pressed",70+24*4,20+82*8/3)
  uiPointer("released",70+24*4,20+82*8/3); tick(30)
  eq(answer(),false); noHold()
end)
test("classic choice over a wide battle follows the native horizontal offset",function()
  local answer
  local box=ChoiceBox.new(game,function(yes) answer=yes end)
  local battle={uiSize=function() return 304,144 end}
  game.wideBattleInStack=function() return battle end
  uiFrame(box)
  game.renderer.frameRects=function()
    return {uox=20,uoy=10,Ux=2,Uy=2,uiw=304,uih=144,
      vux=0,vuy=0,vuw=960,vuh=620,dpiX=1,dpiY=1}
  end
  render()
  uiPointer("pressed",20+(132+72)*2,10+82*2)
  uiPointer("released",20+(132+72)*2,10+82*2); tick(30)
  eq(answer,false); noHold()
end)

assert(load(SCREEN_TESTS_SOURCE))()({
  test=test, eq=eq, clickUI=clickUI, uiPointer=uiPointer,
  uiFrame=uiFrame, tick=tick, render=render, noHold=noHold,
  getGame=function() return game end,
  getRegistry=function() return registry end,
  getOptions=function() return options end,
})

print(string.format("%d tests passed", count))
