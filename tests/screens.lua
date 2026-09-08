-- Native controllers, with art/constructors replaced by explicit fixtures.
-- Optional replacement controllers are extracted read-only from installed mods.
return function(h)
  local test, eq, click, tick = h.test, h.eq, h.clickUI, h.tick
  local Menu = require("src.ui.Menu")
  local Dex = require("src.ui.PokedexMenu")
  local Summary = require("src.ui.SummaryMenu")
  local Trainer = require("src.ui.TrainerCard")
  local Map = require("src.ui.TownMap")
  local function drawn(path)
    return assert(load("return function() end", "@mods/" .. path))()
  end
  local function dex(yellow)
    local game = h.getGame()
    require("src.core.GameVersion").isYellow = function() return yellow == true end
    require("src.core.GameVersion").generation = function() return 1 end
    game.data.pokemon, game.save.pokedex = {}, {seen={},owned={}}
    for i = 1, 15 do
      local id = "MON" .. i
      game.data.pokemon[id] = {id=id,dex=i,name=id}
      game.save.pokedex.seen[id] = true
    end
    game.renderer.uiSize = function() return 160,144 end
    local state = Dex.new(game)
    h.uiFrame(state)
    return state
  end
  local function over()
    h.uiPointer("moved", 80+60*3, 30+50*2)
  end
  local function map()
    local game = h.getGame()
    require("src.core.GameVersion").generation = function() return 1 end
    return setmetatable({game=game,nestSpecies="MON1",mode="grid",
      blink=0,sel=1,locs={{x=3,y=5},{x=8,y=9}},bg=true},Map)
  end
  local function summary()
    return setmetatable({game=h.getGame(),page=1,whiteHold=0,
      mon={species="MON1",moves={{id="TACKLE"},{id="GROWL"}}}},Summary)
  end
  test("Pokedex wheel moves native list and scroll offset without opening entries",function()
    local state = dex()
    over()
    h.getGame():wheelmoved(0,-6); tick(14)
    eq(state.index,7); eq(state.scroll,0); eq(h.getGame().stack:top(),state)
    h.getGame():wheelmoved(0,-3); tick(8)
    eq(state.index,10); eq(state.scroll,3); h.noHold()
  end)
  test("Pokedex wheel respects disabled option",function()
    local state = dex()
    h.getOptions().wheel_lists=false
    over(); h.getGame():wheelmoved(0,-3); tick(8)
    eq(state.index,1); h.noHold()
  end)
  test("Pokedex wheel cancels on list replacement",function()
    local state = dex()
    over(); h.getGame():wheelmoved(0,-3)
    state.items={state.items[2],state.items[1]}
    tick(8); eq(state.index,1); h.noHold()
  end)
  for _, yellow in ipairs({false,true}) do
    test("Native dex private side menu CRY and AREA "..tostring(yellow),function()
      local list = dex(yellow)
      local game = h.getGame()
      local cry, species
      local Sound = require("src.core.Sound")
      local old = Sound.playCry
      Sound.playCry=function(_, id) cry=id end
      local Screens = require("src.ui.Screens")
      local oldPush = Screens.push
      Screens.push=function(g,id,opts)
        species=opts.nestSpecies
        eq(id,"TownMap")
        local area=map(); area.nestSpecies=species; g.stack:push(area)
      end
      assert(click(40,26))
      local side = game.stack:top()
      eq(getmetatable(side),Menu)
      h.render()
      local function rowY(row) return (side.ty+side.th-2-(#side.items-row)*2)*8+3 end
      assert(click(140,rowY(2)))
      eq(cry,"MON1"); eq(game.stack:top(),side)
      h.render(); assert(click(140,rowY(3)))
      eq(species,"MON1"); eq(game.stack:top().nestSpecies,"MON1")
      h.render(); assert(click(70,60)); eq(game.stack:top(),list)
      Sound.playCry, Screens.push=old,oldPush
      h.noHold()
    end)
  end
  test("Native dex DATA action uses the engine's Screens dispatch",function()
    dex()
    local Screens = require("src.ui.Screens")
    local oldPush, opened, species = Screens.push
    Screens.push=function(_,id,arg) opened,species=id,arg end
    click(40,26); local side=h.getGame().stack:top(); h.render()
    assert(click(140,(side.ty+side.th-2-(#side.items-1)*2)*8+2))
    eq(opened,"DexEntryMenu"); eq(species,"MON1")
    Screens.push=oldPush; h.noHold()
  end)
  test("Custom dex side renderer is not guessed",function()
    dex(); click(40,26)
    local side=h.getGame().stack:top()
    side.draw=function() end; h.render()
    eq(click(140,100),false); eq(h.getGame().stack:top(),side); h.noHold()
  end)
  test("Battle STATS summary advances both native pages and completes its flash",function()
    local state=summary(); h.uiFrame(state)
    assert(click(80,80)); eq(state.page,2)
    h.render(); assert(click(80,80)); assert(state.closing)
    tick(60); assert(h.getGame().stack:top()~=state); h.noHold()
  end)
  test("Summary page change cancels queued click",function()
    local state=summary(); h.uiFrame(state)
    h.uiPointer("pressed",80+80*3,30+80*2)
    h.uiPointer("released",80+80*3,30+80*2)
    state.page=2; tick(3)
    eq(state.closing,nil); eq(h.getGame().stack:top(),state); h.noHold()
  end)
  test("Summary white hold and unknown renderer are not click targets",function()
    local state=summary(); state.whiteHold=5; h.uiFrame(state)
    eq(click(80,80),false); eq(state.page,1)
    state.whiteHold=0; state.draw=function() end; h.render()
    eq(click(80,80),false); eq(state.page,1); h.noHold()
  end)
  test("Trainer badge card click returns via native onCancel exactly once",function()
    local count=0
    local state=setmetatable({game=h.getGame(),onCancel=function() count=count+1 end},Trainer)
    h.uiFrame(state); assert(click(80,112)); eq(count,1)
    assert(h.getGame().stack:top()~=state); h.noHold()
  end)
  test("Unknown trainer renderer does not expose badge targets",function()
    local state=setmetatable({game=h.getGame(),draw=function() end},Trainer)
    h.uiFrame(state); eq(click(80,112),false); eq(h.getGame().stack:top(),state); h.noHold()
  end)
  test("AREA closes natively; changed species cancels stale click",function()
    local state=map(); h.uiFrame(state)
    h.uiPointer("pressed",80+80*3,30+80*2)
    h.uiPointer("released",80+80*3,30+80*2)
    state.nestSpecies="MON2"; tick(3)
    eq(h.getGame().stack:top(),state)
    h.render(); assert(click(80,80)); assert(h.getGame().stack:top()~=state); h.noHold()
  end)
  test("Modern dex area bridge keeps the displayed action menu clickable",function()
    local list=dex()
    click(40,26)
    list.modernPokedexUI=true
    local side=h.getGame().stack:top()
    side.modernDexOwner,side.modernDexAreaBridge=list,true
    side.draw=drawn("modern_pokedex_ui/screen.lua")
    local cry, Sound=nil,require("src.core.Sound")
    local old=Sound.playCry; Sound.playCry=function(_,id) cry=id end
    h.render()
    -- Four rows: height 76, y=32; CRY highlight y=65..77.
    assert(click(70,70)); eq(cry,"MON1"); eq(side.index,2)
    Sound.playCry=old; h.noHold()
  end)
  test("Gen1Dex list wheel and sixth clickable row use native Pokedex input",function()
    local state=dex()
    h.getRegistry().gen1_wild_ui={exports={features={gen1dex={exports={}}}}}
    state.draw=drawn("gen1_wild_ui/modules/Gen1Dex/list.lua")
    state.dexMode=function() return "num" end
    state.__gen1dexChoose=function(item,owner) return Dex.onChoose(item,owner) end
    state.onChoose=state.__gen1dexChoose
    state.rows=function() return math.min(6,#state.items) end
    h.render(); over(); h.getGame():wheelmoved(0,-6); tick(14)
    eq(state.index,7); eq(state.scroll,1)
    h.render(); assert(click(60,111)); eq(state.index,7)
    eq(getmetatable(h.getGame().stack:top()),Menu); h.noHold()
  end)
  if MODERN_SUMMARY_SOURCE then
    local make=assert(load([[
      local summary, downstreamUpdate = ...
      local HEADER_H, FOOTER_Y = 16,136
      local function responsiveWidth() return summary:uiSize() end
      local function setting(_,fallback) return fallback end
      local function faithfulRatioActive() return false end
    ]]..MODERN_SUMMARY_SOURCE.."\nreturn summary","@mods/modern_party_ui/summary.lua"))
    test("Modern battle summary native move detail and footer BACK",function()
      local state=summary()
      state.uiSize=function() return 160,144 end
      state.modernMoveIndex,state.modernMoveDetail=1,false
      state.modernPartySummary,state.modernSummaryLayout=true,"responsive_cards"
      state.draw=drawn("modern_party_ui/summary.lua")
      h.getGame().data.moves={TACKLE={},GROWL={}}
      make(state,Summary.update); h.uiFrame(state)
      assert(click(80,80)); eq(state.page,2)
      h.render(); assert(click(100,84))
      eq(state.modernMoveIndex,2); eq(state.modernMoveDetail,true)
      h.render(); click(80,80); eq(state.modernMoveDetail,false)
      h.render(); assert(click(80,139)); assert(state.closing)
      tick(60); assert(h.getGame().stack:top()~=state); h.noHold()
    end)
  end
  if MODERN_DEX_SOURCE then
    local make=assert(load([[
      local state, nativeUpdate = ...
      local Logger = require("src.core.Logger")
    ]]..MODERN_DEX_SOURCE.."\nreturn state","@mods/modern_pokedex_ui/screen.lua"))
    local function entry()
      local game=h.getGame()
      local state=setmetatable({game=game,page=1,modernDexTabbed=true,modernPokedexEntry=true,
        modernDexPage=1,modernDexClock=0,modernMoveDetail=false,
        modernInfoScroll=0,modernInfoCanScroll=true,modernInfoVisible=2,
        modernInfoLines={"one","two","three","four"},
        modernDexPages={{id="info"},{id="stats"},{id="moves"}},
        def={id="MON1",level1Moves={"TACKLE","GROWL"}},
        uiSize=function() return 160,144 end,
        draw=drawn("modern_pokedex_ui/screen.lua")},require("src.ui.DexEntryMenu"))
      game.renderer.uiSize=function() return 160,144 end
      game.data.moves={TACKLE={},GROWL={}}
      make(state,require("src.ui.DexEntryMenu").update)
      return state
    end
    test("Modern Pokedex INFO wheel scrolls notes through authored update",function()
      local state=entry(); h.uiFrame(state); over()
      h.getGame():wheelmoved(0,-2); tick(6)
      eq(state.modernInfoScroll,2); eq(state.modernDexPage,1)
      h.getGame():wheelmoved(0,1); tick(3)
      eq(state.modernInfoScroll,1); h.noHold()
    end)
    test("Modern Pokedex tab click runs controller reset, not its action",function()
      local state=entry(); state.modernMoveCursor=4; h.uiFrame(state)
      assert(click(80,8)); eq(state.modernDexPage,2)
      eq(state.modernMoveCursor,1); eq(state.modernInfoScroll,0)
      h.render(); assert(click(145,139))
      assert(h.getGame().stack:top()~=state); h.noHold()
    end)
    test("Modern Pokedex moves wheel and detail return stay source-owned",function()
      local state=entry(); state.modernDexPage=3; state.modernMoveCursor=1
      state.modernMoveScroll=0; h.uiFrame(state); over()
      h.getGame():wheelmoved(0,-1); tick(3); eq(state.modernMoveCursor,2)
      h.render(); assert(click(75,57)); eq(state.modernMoveDetail,true)
      h.render(); assert(click(80,70)); eq(state.modernMoveDetail,false); h.noHold()
    end)
    test("Unknown renderer inheriting modern entry marker remains unsupported",function()
      local state=entry(); h.uiFrame(state); state.draw=function() end
      h.render(); eq(click(80,8),false); over()
      h.getGame():wheelmoved(0,-2); tick(6)
      eq(state.modernDexPage,1); eq(state.modernInfoScroll,0); h.noHold()
    end)
    test("Modern dex tab wheel adapter publishes horizontal native inputs",function()
      local state=entry(); state.modernDexPage=2; h.uiFrame(state)
      local targets=assert(load(MOD_FILES["mouse_targets.lua"]))()({
        find=function(id) return h.getRegistry()[id] end,
      })
      local valid,buttons=targets.scroll(h.getGame(),state)
      assert(valid()); eq(buttons.up,"left"); eq(buttons.down,"right")
      state.modernDexPage=3; eq(valid(),false)
    end)
    test("Modern dex horizontal wheel honors fractional notches and cancels at a new page",function()
      local state=entry(); state.modernDexPage=2; h.uiFrame(state); over()
      h.getGame():wheelmoved(0,0.4); tick(2); eq(state.modernDexPage,2)
      h.getGame():wheelmoved(0,0.6); tick(3); eq(state.modernDexPage,1)
      state.modernInfoCanScroll=false; h.render()
      h.getGame():wheelmoved(0,-0.4); tick(2); eq(state.modernDexPage,1)
      h.getGame():wheelmoved(0,-0.6); tick(3); eq(state.modernDexPage,2)
      h.getGame():wheelmoved(0,-6); tick(14)
      eq(state.modernDexPage,3); eq(state.modernMoveCursor,1)
      h.noHold()
    end)
  end
  if WILD_DEX_SOURCE then
    local Entry=assert(load([[
      local Entry={}; Entry.__index=Entry
      Entry.PAGES={"dex","stats","moves"}
      Entry.PAGE_INDEX={dex=1,stats=2,moves=3}
      local NEXT_PAGE={dex="stats",stats="moves",moves="dex"}
      local PREV_PAGE={dex="moves",stats="dex",moves="stats"}
      local LAST_PAGE,MOVE_ROWS="moves",8
      function Entry.new() end
      function Entry:stepCrystal() end
      function Entry:moveList() return self.moves end
      function Entry:draw() end
    ]]..WILD_DEX_SOURCE.."\nreturn Entry","@mods/gen1_wild_ui/modules/Gen1Dex/entry.lua"))()
    test("Gen1Dex entry arrows, description pages, moves and return use authored controller",function()
      local game=h.getGame()
      h.getRegistry().gen1_wild_ui={exports={features={gen1dex={exports={}}}}}
      game.data.screens={DexEntryMenu={new=Entry.new}}
      local moves={}; for i=1,17 do moves[i]={id="MOVE"..i} end
      local state=setmetatable({game=game,page="dex",def={id="MON1"},
        species="MON1",desc={"first","second"},descPage=1,movePage=1,moves=moves},Entry)
      h.uiFrame(state); assert(click(80,90)); eq(state.descPage,2); eq(state.page,"dex")
      h.render(); assert(click(148,10)); eq(state.page,"stats")
      over(); game:wheelmoved(0,1); tick(3); eq(state.page,"dex")
      game:wheelmoved(0,-1); tick(3); eq(state.page,"stats")
      h.render(); assert(click(148,10)); eq(state.page,"moves"); eq(state.movePage,1)
      over(); game:wheelmoved(0,-1); tick(3); eq(state.movePage,2)
      h.render(); assert(click(80,128)); assert(game.stack:top()~=state); h.noHold()
    end)
  end
  if WILD_AREA_SOURCE then
    local make=assert(load([[
      local screen,baseUpdate=...
      local showing=true
      local function pressSound() end
      local function canMove() return false end
      local function pressA() error("unexpected AREA action") end
    ]]..WILD_AREA_SOURCE.."\nreturn screen","@mods/gen1_wild_ui/modules/Gen1Dex/area.lua"))
    test("Gen1Dex AREA first click reads hint; right-click returns without selecting a flight",function()
      h.getRegistry().gen1_wild_ui={exports={features={gen1dex={exports={
        area={caption=function() return {"hint"} end}}}}}}
      local oldNew,oldPristine=Map.new,Map.__gen1dex_pristine_new
      Map.__gen1dex_pristine_new=map
      Map.new=function()
        local state=map()
        state.draw=drawn("gen1_wild_ui/modules/Gen1Dex/area.lua")
        return make(state,Map.update)
      end
      h.uiFrame(map())
      local state=Map.new()
      h.uiFrame(state)
      -- ROM grid (8,9) is displayed at (80,80), not (64,88).
      assert(click(82,82)); eq(state.sel,2); eq(h.getGame().stack:top(),state)
      h.render(); assert(click(80,70,2))
      assert(h.getGame().stack:top()~=state); h.noHold()
      Map.new,Map.__gen1dex_pristine_new=oldNew,oldPristine
    end)
    test("Unknown AREA renderer with a Gen1Dex registry entry is not guessed",function()
      h.getRegistry().gen1_wild_ui={exports={features={gen1dex={exports={
        area={caption=function() return {"hint"} end}}}}}}
      local state=map(); state.draw=drawn("unknown/area.lua")
      h.uiFrame(state); eq(click(80,80),false); eq(h.getGame().stack:top(),state)
      h.noHold()
    end)
  end
end
