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
local tilted, projected = false, false
package.preload["src.render.Tilt"] = function()
  return { active = function() return tilted end }
end
package.preload["src.render.Pipelines"] = function()
  return { worldPipeline = function() return projected and "voxel" or nil end }
end
love = { graphics = {
  getColor = function() return 1, 1, 1, 1 end,
  setColor = function() end, line = function() end,
  push=function() end, pop=function() end, origin=function() end,
  setCanvas=function() end, setShader=function() end, setScissor=function() end,
  rectangle=function() end, print=function() end, getDimensions=function() return 960,720 end,
  getFont=function() return {
    getWidth=function(_,text) return #text*7 end, getHeight=function() return 12 end,
  } end,
} }

local Player = require("src.world.Player")
local Input = require("src.core.Input")
local Collision = require("src.world.Collision")
local Camera = require("src.render.Camera")
local Transition = require("src.render.Transition")
local Hooks = require("src.mods.Hooks")
local game, ow, hooks, options, events, holds, steps, rect, origin, registry
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
  hooks:call("render.hud", noop, game, rect)
end
local function setup()
  warnings, tilted, projected = {}, false, false
  holds, options, events, steps, registry = {}, {}, {}, {}, {}
  hooks = Hooks.new()
  game = { data = { sprites = { player = {} }, field = {} }, save = {},
    options = {textSpeed=1},
    input = setmetatable({}, { __index = Input }),
    renderer = { wipeWox = 0, wipeWoy = 0, wipeSx = 3, wipeSy = 3 } }
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
  local mod = { hooks = hooks, options = {}, events = {}, input = {}, world = {},
    log = { info = noop, warn = function(...) warnings[#warnings + 1] = {...} end } }
  function mod.options:define(rows)
    for _, row in ipairs(rows) do options[row.key] = row.default end
  end
  function mod.options:get(key) return options[key] end
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
test("projected view rejects input and explains why", function()
  projected = true
  eq(pointer("pressed"), false)
  eq(#warnings, 1)
  warnings = {}
  tick(40); eq(#steps, 0)
end)
test("enabling perspective during steering cancels hold", function()
  pointer("pressed"); tick(10)
  tilted = true
  hooks:call("input.step", noop, game, 1/60)
  noHold(); eq(#warnings, 1); warnings = {}
  tilted = false; tick(50); eq(ow.player.cellX, 51)
end)
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
local function clickDock(index, phase, count)
  local cols=math.ceil((count or 10)/2)
  local x=((index-1)%cols+0.5)*960/cols
  local y=620+math.floor((index-1)/cols)*39+18
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
  eq(result.x,17); eq(result.y,29); eq(result.height,560); assert(result.capture)
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
  drawDock(); clickDock(10,nil,12)
  assert(game.input:isDown("select")); assert(game.input:isDown("a"))
  clickDock(10,"released",12)
  noHold(); eq(c.cancelled,0)
end)
test("right-click cancels Wilds charge without releasing a throw",function()
  local c=catchingFixture()
  drawDock(); clickDock(10,nil,12)
  uiPointer("pressed",560,677,2,true)
  noHold(); eq(c.cancelled,1)
end)
test("dragging out of dock cancels Wilds charge",function()
  local c=catchingFixture()
  drawDock(); clickDock(10,nil,12)
  uiPointer("moved",560,600,1,true)
  noHold(); eq(c.cancelled,1)
end)
test("Wilds next ball invokes owned exported cycler",function()
  local c=catchingFixture()
  drawDock(); clickDock(11,nil,12); clickDock(11,"released",12); tick(2)
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
  ..BATTLE_BEGINMSGLINE_SOURCE.."\nreturn BattleState"))(
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
print(string.format("%d tests passed", count))
