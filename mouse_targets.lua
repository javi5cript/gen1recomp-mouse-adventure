-- Presentation adapters only: selection moves a cursor; the next native A
-- press still owns validation, sound, transitions, and gameplay.
return function(mod)
  local classes = {}
  local function class(name)
    if not classes[name] then classes[name] = require("src." .. name) end
    return classes[name]
  end
  local function native(s, name)
    local c = class(name)
    return getmetatable(s) == c and s.draw == c.draw
  end
  local function exports(id)
    local found = mod.find(id)
    return found and found.exports
  end
  local function featureExports(id)
    local direct = exports(id)
    if direct then return direct end
    local bundle = exports("gen1_wild_ui")
    local handle = bundle and bundle.features and bundle.features[id:lower()]
    return handle and handle.exports
  end
  local function rect(x, y, w, h) return {x=x, y=y, w=w, h=h} end
  local function options(game, id)
    local o = game.save and game.save.options
    return o and o.modOptions and o.modOptions[id] or {}
  end
  local function party(s, game) return s.party or (game.save and game.save.party) or {} end
  local presentations = setmetatable({}, {__mode="k"})
  local nativeSides = setmetatable({}, {__mode="k"})
  local observedDex = setmetatable({}, {__mode="k"})
  local wildMaps = setmetatable({}, {__mode="k"})
  local observedMaps = setmetatable({}, {__mode="k"})
  local function presentation(s)
    if type(s.draw) ~= "function" then return false end
    local first = presentations[s]
    if not first then
      presentations[s] = {draw=s.draw, update=s.update}
      return true
    end
    return first.draw == s.draw and first.update == s.update
  end
  local function observeDex(s)
    local Dex = class("ui.PokedexMenu")
    if observedDex[s] or getmetatable(s) ~= Dex or s.onChoose ~= Dex.onChoose then return end
    observedDex[s] = true
    local choose = s.onChoose
    -- The engine calls this continuation, not a mouse action. Observe its
    -- private side renderer after normal dispatch; no debug API is exposed
    -- in the mod sandbox and no callback is invoked to discover geometry.
    s.onChoose = function(item, owner)
      local result = choose(item, owner)
      local side = owner.game.stack:top()
      if side ~= owner and getmetatable(side) == class("ui.Menu")
          and side.tx == 14 and side.tw == 6 then
        nativeSides[side] = {draw=side.draw, update=side.update, owner=owner,
          item=item, index=owner.index, items=owner.items}
      end
      return result
    end
  end
  local function nativeSide(s)
    local record = nativeSides[s]
    return record and record.draw == s.draw and record.update == s.update
      and record.owner.items == record.items and record.owner.index == record.index
      and record.items[record.index] == record.item
  end
  local function observeWildMaps()
    local wild, Map = featureExports("Gen1Dex"), class("ui.TownMap")
    if not wild or type(wild.area) ~= "table"
        or type(Map.__gen1dex_pristine_new) ~= "function"
        or type(Map.new) ~= "function" or Map.new == Map.__gen1dex_pristine_new
        or observedMaps[Map] then return end
    observedMaps[Map] = true
    local make = Map.new
    Map.new = function(...)
      local screen = make(...)
      if type(screen) == "table" and getmetatable(screen) == Map then
        wildMaps[screen] = {draw=screen.draw, update=screen.update}
      end
      return screen
    end
  end
  local function modernEntry(s)
    return s.modernPokedexEntry and getmetatable(s) == class("ui.DexEntryMenu")
      and type(s.modernDexPages) == "table" and type(s.uiSize) == "function"
      and presentation(s)
  end
  local function wildScreen(s, file)
    local wild = featureExports("Gen1Dex")
    if not wild then return false end
    if file == "list.lua" then
      return getmetatable(s) == class("ui.PokedexMenu")
        and type(s.dexMode) == "function" and s.onChoose == s.__gen1dexChoose
        and type(s.__gen1dexChoose) == "function" and presentation(s)
    elseif file == "entry.lua" then
      local c = getmetatable(s)
      local factory = s.game and s.game.data and s.game.data.screens
        and s.game.data.screens.DexEntryMenu
      return type(c) == "table" and type(factory) == "table" and c.new == factory.new
        and type(c.PAGES) == "table" and c.PAGE_INDEX and s.draw == c.draw
        and s.update == c.update and presentation(s)
    end
    local record = wildMaps[s]
    return record and record.draw == s.draw and record.update == s.update
      and getmetatable(s) == class("ui.TownMap") and type(wild.area) == "table"
      and type(wild.area.caption) == "function" and s.nestSpecies
      and type(s.locs) == "table" and presentation(s)
  end
  local function width(game, s)
    local w = s.modernPartySummary and s.uiSize and s:uiSize()
    if not w then w = game.renderer and game.renderer.uiSize and game.renderer:uiSize() end
    if not w and s.uiSize then w = s:uiSize() end
    return math.max(160, math.floor(tonumber(w) or 160))
  end

  -- Record the answer underneath the known grid's visibility wrapper. Never
  -- turn a hidden native menu back on just to make it clickable.
  local underneath = setmetatable({}, {__mode="k"})
  if mod.hooks and mod.hooks.wrap then
    mod.hooks:wrap("battle.bottom_ui_visible", function(next, s)
      local visible = next(s)
      if type(s) == "table" then underneath[s] = visible ~= false end
      return visible
    end, -100000)
  end

  local tokens = {"mode", "phase", "submenu", "subItems", "subIndex", "heal",
    "swapAnim", "swapFrom", "softboiledFrom", "actions", "held", "boxSwitching",
    "boxPicker", "current", "choosing", "selecting", "pending", "choicePushed",
    "moveSwapIndex", "mimicCtx", "player", "modernDexSearchOpen",
    "scene", "pre", "finished", "exiting", "menuOpen",
    "modernPartyNamingCommand", "lower", "script", "battle", "onSwitch",
    "onCancel", "forceSwitch", "pickOnly", "keepOpen", "moveFrom",
    "gen1wildTheme", "modernPartyUI", "page", "pageCount", "def", "mon",
    "closing", "modernPartySummary", "modernMoveDetail", "modernDexTabbed",
    "modernDexPage", "modernDexPages", "modernDexSource", "modernDexOwner",
    "modernDexAreaBridge", "nestSpecies", "fly", "locs", "flyMapIds",
    "species", "descPage", "movePage", "modernInfoLines"}
  local function context(game, s)
    local values, draw, update = {}, s.draw, s.update
    for i, key in ipairs(tokens) do values[i] = s[key] end
    local save = game.save
    local box = save and save.currentBox
    return function()
      if not game.stack or game.stack:top() ~= s or game.save ~= save
          or (save and save.currentBox ~= box)
          or s.draw ~= draw or s.update ~= update then return false end
      for i, key in ipairs(tokens) do
        if s[key] ~= values[i] then return false end
      end
      return true
    end
  end
  local function identity(get, index)
    local list = get()
    if type(list) ~= "table" then return function() return false end end
    local item, count = list[index], #list
    local id, value, label, selectFn, action, move
    if type(item) == "table" then
      id, value, label, selectFn = item.id, item.value, item.label, item.onSelect
      action, move = item.action, item.move
    end
    return function()
      local now = get()
      if now ~= list or #now ~= count or now[index] ~= item then return false end
      return type(item) ~= "table" or
        (item.id == id and item.value == value and item.label == label
          and item.onSelect == selectFn and item.action == action and item.move == move)
    end
  end

  local function collect(game, s)
    local entries = {}
    if not s or not game.stack or game.stack:top() ~= s then return entries, false end
    if game.save and game.save.generation == 2 then return entries, false end
    -- Demonstrations own their menu choices, but their dialogue still waits
    -- for the player's normal A/B input (including Oak's Yellow capture).
    local demo = false
    for _, owner in ipairs(game.stack.states or {}) do
      if owner.isBattle then
        if owner.kind == "link" then return entries, false end
        demo = demo or owner.demo
      end
    end
    if demo and not ((s.isBattle and s.phase == "messages")
        or (s.boxTx and native(s, "render.TextBox"))) then return entries, false end
    local same = context(game, s)
    observeWildMaps()
    observeDex(s)
    local function add(r, select, valid, button)
      if not r or r.w <= 0 or r.h <= 0 then return end
      entries[#entries+1] = {rect=r, action={button=button or "a",
        select=select, valid=function() return same() and (not valid or valid()) end}}
      return entries[#entries].action
    end
    local function rows(get, field, first, count, geometry, extra)
      local list = get()
      if type(list) ~= "table" then return end
      for row = 1, count do
        local index = first + row
        if list[index] == nil then break end
        local valid = identity(get, index)
        local action = add(geometry(row, index), function() s[field] = index end,
          function() return valid() and (not extra or extra()) end)
        local item = list[index]
        if action then action.hint = "Choose " .. tostring(type(item) == "table"
          and (item.label or item.name or "item") or item) end
      end
    end
    local function waitAction(ready, valid)
      entries.waitAction = {button="a", buffered=true, ready=ready,
        valid=function() return same() and valid() end}
    end
    local function partySubmenu(get, geometry)
      local chosen, battle = s.index, s.battle
      local phase, player = battle and battle.phase, battle and battle.player
      local monValid = identity(get, chosen)
      local unchanged = {}
      for i = 1, #(s.subItems or {}) do
        unchanged[i] = identity(function() return s.subItems end, i)
      end
      rows(function() return s.subItems end, "subIndex", 0, #unchanged, geometry,
        function()
          if s.index ~= chosen or not monValid()
              or (battle and (battle.phase ~= phase or battle.player ~= player)) then return false end
          for _, valid in ipairs(unchanged) do if not valid() then return false end end
          return true
        end)
      entries.hint = "Choose a party action."
    end

    if native(s, "ui.SummaryMenu") or (s.modernPartySummary
        and s.modernSummaryLayout == "responsive_cards"
        and getmetatable(s) == class("ui.SummaryMenu") and presentation(s)) then
      local function ready() return not s.closing and (s.whiteHold or 0) <= 0 end
      if not ready() then return entries, false end
      local w = s.modernPartySummary and width(game, s) or 160
      if s.modernPartySummary and s.page == 2 and not s.modernMoveDetail then
        local rail = math.min(88, math.max(64, math.floor(w * 0.31)))
        local x, mainW = rail + 4, w - rail - 6
        local columns = mainW >= 144 and 2 or 1
        local count = math.ceil(4 / columns)
        rows(function() return s.mon.moves end, "modernMoveIndex", 0, 4, function(_, i)
          local col, row = (i-1)%columns, math.floor((i-1)/columns)
          local x1, y1 = x+math.floor(col*mainW/columns), 58+math.floor(row*76/count)
          return rect(x1, y1, x+math.floor((col+1)*mainW/columns)-x1,
            58+math.floor((row+1)*76/count)-y1)
        end, ready)
        -- B, not A, belongs to the downstream summary page/close handler.
        add(rect(0, 136, w, 8), nil, ready, "b")
        entries.hint = "Choose a move. Click the footer to continue or return."
      else
        entries.hint = "Continue: click to advance or close the summary."
        add(rect(0, 0, w, 144), nil, ready)
        return entries, entries[#entries].action
      end
      return entries, false
    end

    if native(s, "ui.TrainerCard") then
      entries.hint = "Trainer card: click to return. Badges are display-only."
      add(rect(0, 0, 160, 144), nil)
      return entries, entries[#entries].action
    end

    local wildMap = getmetatable(s) == class("ui.TownMap") and wildScreen(s, "area.lua")
    if native(s, "ui.TownMap") or wildMap then
      local function unchanged() return not wildMap or presentation(s) end
      if s.nestSpecies then
        entries.hint = wildMap and "Click to read the area hint or use the selected map location. Right-click to return."
          or "Area map: click to return."
        -- AREA's first A hides the hint; its next A is owned by Gen1Dex
        -- (possibly INSPECT/FLY). Never bypass that source-owned dispatch.
        if wildMap and s.mode == "grid" and s.bg then
          for i, loc in ipairs(s.locs or {}) do
            if type(loc.x) == "number" and type(loc.y) == "number" then
              local valid = identity(function() return s.locs end, i)
              local x, y = loc.x, loc.y
              add(rect(x*8+16, y*8+8, 8, 8), function() s.sel = i end,
                function() return unchanged() and valid() and loc.x == x and loc.y == y end)
            end
          end
        end
        add(rect(0, 0, 160, 144), nil, unchanged)
        return entries, entries[#entries].action
      end
      -- The ordinary map is a viewer, not an A-to-confirm destination
      -- picker. Only FLY exposes selectable destinations.
      if s.fly then
        for i, loc in ipairs(s.locs or {}) do
          local r
          if s.mode == "grid" and s.bg and loc.x and loc.y then
            r = rect(loc.x*8+16, loc.y*8+8, 8, 8)
          end
          if r then
            local valid = identity(function() return s.locs end, i)
            local ids, id = s.flyMapIds, s.flyMapIds and s.flyMapIds[i]
            add(r, function() s.sel = i end,
              function() return valid() and ids and s.flyMapIds == ids and ids[i] == id end)
          end
        end
      end
      add(rect(0, 0, 160, 16), nil, nil, "b")
      return entries, false
    end

    if modernEntry(s) then
      local w = width(game, s)
      local function ready() return not s.crying or not s:crying() end
      if not s.modernDexTabbed then
        local infoScroll = s.modernInfoScroll
        local function valid() return s.modernInfoScroll == infoScroll end
        if not ready() then waitAction(ready, valid) end
        add(rect(0, 0, w, 144), nil, valid)
        return entries, entries[#entries].action
      end
      if s.modernMoveDetail then
        add(rect(0, 0, w, 144), nil, nil, "b")
        return entries, entries[#entries].action
      end
      local pages = s.modernDexPages or {}
      local visible = math.min(#pages, math.max(3, math.floor(w/40)))
      local current = s.modernDexPage or 1
      local first = math.max(1, math.min(#pages-visible+1, current-math.floor(visible/2)))
      if visible > 0 then
        local tabW = math.floor(w/visible)
        for slot = 1, visible do
          local index = first+slot-1
          if index ~= current then
            local valid = identity(function() return s.modernDexPages end, index)
            -- Stage only the presentation cursor immediately before native
            -- RIGHT. The controller performs page entry/reset and callbacks.
            add(rect((slot-1)*tabW+1, 1, tabW-2, 15),
              function() s.modernDexPage = index == 1 and #pages or index-1 end, valid, "right")
          end
        end
      end
      local page = pages[current]
      if page and page.id == "moves" then
        local offset = s.modernMoveScroll or 0
        rows(function() return s.modernMoveRows end, "modernMoveCursor", offset, w >= 240 and 7 or 6,
          function(row) return rect(9, 39+(row-1)*14, w-18, 12) end,
          function() return s.modernMoveScroll == offset end)
      elseif page and page.id == "family" then
        local family = s.modernDexFamily or {}
        local columns = math.min(w >= 240 and 5 or 3, math.max(2, #family))
        local count = math.max(1, math.ceil(#family/columns))
        local cellW, cellH = math.floor((w-18)/columns), math.floor(68/count)
        local cardW, cardH = math.min(w >= 240 and 72 or 48, cellW-3), math.min(60, cellH-3)
        rows(function() return s.modernDexFamily end, "modernFamilyCursor", 0, #family,
          function(_, i)
            return rect(4+math.floor((w-8-cellW*columns)/2)+(i-1)%columns*cellW+math.floor((cellW-cardW)/2),
              41+math.floor((i-1)/columns)*cellH+math.floor((cellH-cardH)/2), cardW, cardH)
          end)
      elseif page and (page.id == "info" or page.id == "stats") then
        add(rect(4, 21, w-8, 109), nil)
      end
      if page and not page.footer and
          (page.id == "info" or page.id == "stats" or page.id == "moves" or page.id == "family") then
        local back = w < 240 and (page.id == "moves" or page.id == "family") and "B" or "B BACK"
        local backW = class("render.Font").width(back)
        add(rect(w-5-backW, 134, backW, 10), nil, nil, "b")
      end
      entries.hint = "Click a tab; click content for its native action. Right-click to return."
      return entries, false
    end

    if wildScreen(s, "entry.lua") and s.def and
        (s.page == "dex" or s.page == "stats" or s.page == "moves") then
      add(rect(4, 4, 16, 16), nil, nil, "left")
      add(rect(140, 4, 16, 16), nil, nil, "right")
      add(rect(0, 24, 160, 96), nil)
      add(rect(0, 120, 160, 24), nil, nil, "b")
      entries.hint = "Use the header arrows to change pages. Click content to continue; right-click to return."
      return entries, false
    end

    -- Level-up stats window (BattleState.StatBox / PrintStatsBox): a small
    -- state pushed over the battle that vanilla dismisses with A/B. It is not
    -- the battle state itself, so the isBattle branch never sees it; without
    -- this a click cannot advance the "grew to level" stat card. Any click
    -- sends A, matching the box's own dismissal.
    do
      local ok, battle = pcall(class, "battle.BattleState")
      if ok and battle and battle.StatBox and getmetatable(s) == battle.StatBox then
        entries.hint = "Continue: click to close the level-up stats."
        add(rect(0, 0, 160, 144), nil, nil, "a")
        return entries, entries[#entries].action
      end
    end

    -- Pokedex data page (ui.DexEntryMenu): pushed over the battle after a new
    -- species is caught. Vanilla advances each page -- and finally pops -- on
    -- A/B; it is its own state, so the isBattle branch never sees it. Without
    -- this a click cannot dismiss the "New POKeDEX data" screen. Any click
    -- sends A, matching the page's own advance/close. (Input is ignored while
    -- the cry plays, exactly as with the keyboard, so a click then is a no-op.)
    if native(s, "ui.DexEntryMenu") then
      local page, def, pageCount = s.page, s.def, s.pageCount
      local function valid() return s.page == page and s.def == def and s.pageCount == pageCount end
      local function ready() return not s.crying or not s:crying() end
      entries.hint = ready() and "Continue: click for the next Pokedex page." or "Waiting for the Pokemon cry."
      if not ready() then waitAction(ready, valid) end
      add(rect(0, 0, 160, 144), nil, valid, "a")
      return entries, entries[#entries].action
    end

    if native(s, "ui.TitleState") then
      if s.phase == "loop" and not s.menuOpen then
        add(rect(0, 0, 160, 144), nil)
        return entries, entries[#entries].action
      end
      return entries, false
    end
    if native(s, "ui.IntroMovie") or native(s, "ui.YellowIntro") then
      local pre, prePhase = s.pre, s.pre and s.pre.phase
      local function ready()
        return not s.finished and not s.exiting and s.phase ~= 4
          and (s.pendingDelay or 0) <= 0
          and s.pre == pre and (not pre or pre.phase == prePhase)
      end
      if ready() then
        -- A skips only where the native intro permits it; copyright cards
        -- and mandatory fades keep their normal timing.
        add(rect(0, 0, 160, 144), nil, ready)
        return entries, entries[#entries].action
      end
      return entries, false
    end
    -- ContinueInfo is private to TitleState. Its native parent and fixed
    -- info-box contract distinguish it from arbitrary confirmation menus.
    if s.title and native(s.title, "ui.TitleState") and type(s.save) == "table"
        and s.title.menuOpen and type(s.titleUiBox) == "table" then
      local b = s.titleUiBox
      if b[1] == 4 and b[2] == 7 and b[3] == 19 and b[4] == 16 then
        local title, save = s.title, s.save
        add(rect(32, 56, 128, 80), nil,
          function() return s.title == title and s.save == save and title.menuOpen end)
      end
      return entries, false
    end

    if s.modernPCUI and type(s.modernPCLayoutInfo) == "function" then
      local l = s:modernPCLayoutInfo()
      local Boxes = class("core.Boxes")
      if s.actions then
        local w = math.min(112, math.max(88, math.floor(l.width * 0.42)))
        local x, y = l.width-w-4, l.footerY-#s.actions*12-8
        local region, index = s.region, s.region == "party" and s.partyIndex or s.boxIndex
        local get = function() return region == "party" and game.save.party or Boxes.active(game.save) end
        local monValid = identity(get, index)
        rows(function() return s.actions end, "actionIndex", 0, #s.actions,
          function(row) return rect(x+3, y+3+(row-1)*12, w-6, 11) end,
          function() return monValid() and s.region == region
            and (region == "party" and s.partyIndex or s.boxIndex) == index end)
      elseif s.boxSwitching then
        if s.boxPicker then
          local p, n = l.box, Boxes.COUNT
          local rowCount = math.ceil(n/4)
          for i = 1, n do
            local col, row = (i-1)%4, math.floor((i-1)/4)
            local x = p.x+2+math.floor(col*(p.w-4)/4)
            local y = p.y+2+math.floor(row*(p.h-4)/rowCount)
            add(rect(x, y, math.floor((col+1)*(p.w-4)/4)-math.floor(col*(p.w-4)/4),
              math.floor((row+1)*(p.h-4)/rowCount)-math.floor(row*(p.h-4)/rowCount)),
              function() s.boxPickerIndex = i end)
          end
        else
          add(rect(l.box.x+2, 2, l.box.w-4, 12), nil)
        end
      else
        for _, region in ipairs({"party", "box"}) do
          local p = l[region]
          local count = region == "party" and class("core.Party").MAX or Boxes.CAPACITY
          for i = 1, count do
            local col, row = (i-1)%p.cols, math.floor((i-1)/p.cols)
            local x = p.x+2+math.floor(col*(p.w-4)/p.cols)
            local y = p.y+2+math.floor(row*(p.h-4)/p.rows)
            local get = function() return region == "party" and game.save.party or Boxes.active(game.save) end
            local valid = identity(get, i)
            -- Empty slots are real native drop targets, including refused
            -- drops: the PC controller must enforce all party/box rules.
            add(rect(x, y, math.floor((col+1)*(p.w-4)/p.cols)-math.floor(col*(p.w-4)/p.cols),
              math.floor((row+1)*(p.h-4)/p.rows)-math.floor(row*(p.h-4)/p.rows)),
              function()
                s.region = region
                if region == "party" then s.partyIndex = i else s.boxIndex = i end
              end, valid)
          end
        end
        add(rect(l.box.x+2, 2, l.box.w-4, 12), nil, nil, "select")
      end
      return entries, false
    end

    if s.modernPartyUI and type(s.modernPartyLayoutInfo) == "function" then
      if s.heal or s.swapAnim then return entries, false end
      local l = s:modernPartyLayoutInfo()
      local get = function() return party(s, game) end
      if s.submenu then
        local n = #(s.subItems or {})
        local w, h = math.min(120, l.width-16), 16+n*12
        local x, y = math.floor((l.width-w)/2), math.floor((l.footerY-h)/16)*8
        partySubmenu(get,
          function(row) return rect(x+5, y+13+(row-1)*12, w-10, 11) end)
      else
        rows(get, "index", 0, math.min(#get(), l.capacity), function(_, i)
          local col, row = (i-1)%l.columns, math.floor((i-1)/l.columns)
          local x, y = math.floor(col*l.width/l.columns), 16+math.floor(row*l.contentHeight/l.rows)
          return rect(x, y, math.floor((col+1)*l.width/l.columns)-x,
            16+math.floor((row+1)*l.contentHeight/l.rows)-y)
        end, function() return not s.heal and not s.swapAnim end)
      end
      return entries, false
    end

    if s.modernPokedexUI or s.modernDexOwner then
      local owner = s.modernDexOwner or s
      local w = game.renderer and game.renderer:uiSize() or owner:uiSize()
      w = math.max(160, math.floor(w))
      local wide, listW = w >= 240, w >= 240 and math.max(154, math.floor(w*0.56)) or w-8
      if s.modernDexOwner then
        if getmetatable(s) ~= class("ui.Menu")
            or not owner.modernPokedexUI or not presentation(s) then return entries, false end
        local previewW = w-listW-12
        local width = math.max(72, math.min(126, wide and previewW-12 or w-36))
        local x = wide and listW+8+math.floor((previewW-width)/2) or math.floor((w-width)/2)
        local y = math.floor((132-(#s.items*14+20))/2)+4
        rows(function() return s.items end, "index", 0, #s.items,
          function(row) return rect(x+5, y+5+row*14, width-10, 12) end)
      elseif s.modernDexSearchOpen then
        -- These fields change with L/R, not A (which applies the filter).
        local width = math.min(152, w-16)
        local x = math.floor((w-width)/2)
        for field = 1, 2 do
          for side, button in ipairs({"left", "right"}) do
            add(rect(x+6+(side-1)*(width-12)/2, 49+(field-1)*25, (width-12)/2, 20),
              function() s.modernDexSearchCursor = field end, nil, button)
          end
        end
      else
        local scroll = s.scroll or 0
        rows(function() return s.items end, "index", scroll, 5, function(row)
          return rect(4, 21+(row-1)*21, listW, 19)
        end, function() return s.scroll == scroll and not s.modernDexSearchOpen end)
      end
      return entries, false
    end

    if s.items and getmetatable(s) == class("ui.PokedexMenu") and wildScreen(s, "list.lua") then
      local offset = s.scroll or 0
      rows(function() return s.items end, "index", offset, 6,
        function(row) return rect(0, 24+(row-1)*16, 160, 16) end,
        function() return s.scroll == offset end)
      return entries, false
    end

    -- Native Pokedex's observed private renderer is deliberately not Menu.draw.
    if s.items and s.draw ~= nil and getmetatable(s) == class("ui.Menu")
        and nativeSide(s) then
      rows(function() return s.items end, "index", 0, #s.items, function(row)
        return rect((s.tx+1)*8, (s.ty+s.th-2-(#s.items-row)*2)*8, (s.tw-1)*8, 8)
      end, function() return nativeSide(s) end)
      return entries, false
    end

    if s.modernPartyNaming or (s.glyphs and s.grid and native(s, "ui.NamingScreen")) then
      if s.choosing then return entries, false end
      local grid = s:grid()
      local lower, name = s.lower, table.concat(s.glyphs)
      local modern = s.modernPartyNaming
      local style = options(game, "modern_party_ui").rename_style or "classic"
      local w, h = 160, 144
      if modern then w, h = s:uiSize() end
      local panelX, panelY = math.floor((w-160)/2), math.floor((h-144)/2)
      local keyW = math.max(12, math.floor((w-16)/9))
      local gridX = math.floor((w-(keyW*9+8))/2)
      local gridY = math.max(19, math.floor((h-122)/2))+25
      local function namingValid()
        return s.lower == lower and table.concat(s.glyphs) == name and not s.choosing
          and (not modern or (options(game, "modern_party_ui").rename_style or "classic") == style)
      end
      for r, cells in ipairs(grid) do
        for c, glyph in ipairs(cells) do
          if not modern or (r <= 5 and glyph ~= "ED") then
            local box
            if not modern then box = rect(c*16-8, 24+r*16, #cells == 1 and 144 or 16, 8)
            elseif style == "modern" then box = rect(gridX+(c-1)*(keyW+1), gridY+(r-1)*14, keyW, 13)
            else box = rect(panelX+6+(c-1)*16, panelY+48+(r-1)*13, 12, 12) end
            add(box, function()
              s.row, s.col = r, c
              if modern then s.modernPartyNamingCommand = nil end
            end, function()
              local current = s:grid()
              return namingValid() and current[r] and current[r][c] == glyph
            end)
          end
        end
      end
      if modern then
        local widths = {48, 28, 38}
        local xs, y = {panelX+8, panelX+66, panelX+112}, panelY+124
        if style == "modern" then
          local usable = w-14
          widths = {math.floor(usable*0.44), math.floor(usable*0.23)}
          widths[3] = usable-widths[1]-widths[2]
          xs, y = {5, 7+widths[1], 9+widths[1]+widths[2]}, gridY+71
        end
        for i, command in ipairs({"case", "delete", "end"}) do
          add(rect(xs[i], y, widths[i], style == "modern" and 16 or 12),
            function() s.modernPartyNamingCommand = command end, namingValid)
        end
      end
      return entries, false
    end

    if s.isBattle then
      -- Load the large battle module only when a battle is already present.
      if getmetatable(s) ~= class("battle.BattleState") or s.kind == "link" then return entries, false end
      local function ready()
        if s.demo or s.kind == "link" or s.animPlaying or s.waitingUI then return false end
        if s.phase == "menu" then
          if s.safari then return (s.safari.balls or 0) > 0 end
          return s.player and s.player.mon and s.player.mon.hp > 0
            and not s:menuLockedAction(s.player)
        end
        return s.phase == "moveSelect" or s.phase == "mimicSelect"
      end
      underneath[s] = nil
      local visible = s:bottomUIVisible()
      local grid = featureExports("Gen1BattleUI")
      -- Kanto Gear may render the choices in a separate device. Its hidden
      -- upper UI must not leave live rectangles over the battle scene.
      local gridOn = grid and grid.geometry and grid.owns and grid.owns(s)
        and underneath[s] == true and not exports("kanto_gear")
      local wide = s:wideLayout()
      if not ready() then
        local function dialogueReady()
          return s.phase == "messages" and s.current and not s.animPlaying
            and not s.waitingUI and not s.waitingSound and not s.draining
            and (s.waitFrames or 0) <= 0 and (s.introSlide or 0) <= 0
            and ((s.msgWaiting and (s.msgPreWait or 0) <= 0)
              or (s.msgPrompt and (s.msgPromptWait or 0) <= 0))
        end
        entries.hint = "Waiting for battle animation / text."
        if visible and s.phase == "messages" and s.current then
          local current, shown, line = s.current, s.shown, s.lineIndex
          local waiting, prompt = s.msgWaiting, s.msgPrompt
          local function valid()
            return s:bottomUIVisible() and s.current == current and s.shown == shown
              and s.lineIndex == line and s.msgWaiting == waiting and s.msgPrompt == prompt
          end
          if dialogueReady() then
            entries.hint = "Continue: click to advance battle text."
            add(rect(0, wide and 104 or 96, wide and 304 or 160, wide and 40 or 48), nil,
              function() return dialogueReady() and valid() end)
            return entries, entries[#entries].action
          elseif (waiting or prompt) and not s.animPlaying and not s.waitingUI and not s.draining then
            waitAction(dialogueReady, valid)
          end
        end
        return entries, false
      end
      if not visible and not gridOn then return entries, false end
      local phase, player, mimic = s.phase, s.player, s.mimicMoves
      local function targetRect(i)
        local col, row = (i-1)%2, math.floor((i-1)/2)
        if gridOn then
          local geometry = grid.geometry
          if not wide then
            local b = geometry.classic.boxes[i]
            return rect(b[1]*8, b[2]*8, geometry.classic.boxW*8, geometry.classic.boxH*8)
          end
          local g = geometry.wide
          local spec = phase == "menu" and (s.safari and g.safari or g.command)
            or (grid.panelRect and grid.panelRect(s) and g.moves or g.movesFull)
          local left = col == 0 and spec.tx+1 or spec.divider+1
          local right = col == 0 and spec.divider or spec.tx+spec.tw-1
          return rect(left*8, (g.row+1+row*2)*8, (right-left)*8, 8)
        end
        if phase == "menu" then
          local x = wide and (s.safari and (col == 0 and 8 or 160) or (168+col*64))
            or (s.safari and (col == 0 and 8 or 104) or (72+col*48))
          local width = wide and (s.safari and (col == 0 and 152 or 136) or 64)
            or (s.safari and (col == 0 and 96 or 48) or (col == 0 and 48 or 32))
          return rect(x, 112+row*16, width, 8)
        elseif wide then return rect(8+col*104, 112+row*16, 104, 8)
        elseif phase == "mimicSelect" then return rect(8, (7+i)*8, 136, 8)
        else return rect(40, 96+i*8, 112, 8) end
      end
      local function battleValid()
        return ready() and s.phase == phase and s.player == player and s.mimicMoves == mimic
          and s:wideLayout() == wide
      end
      if phase == "menu" then
        for i = 1, 4 do add(targetRect(i), function() s.menuIndex = i end, battleValid) end
      else
        local get = function() return phase == "mimicSelect" and s.mimicMoves or (s.player and s.player.curMoves) end
        rows(get, phase == "mimicSelect" and "mimicIndex" or "moveIndex", 0, math.min(4, #(get() or {})),
          function(_, i) return targetRect(i) end, battleValid)
      end
      return entries, false
    end

    if s.pending ~= nil then return entries, false end
    if s.tx and s.labels and native(s, "ui.ChoiceBox") then
      if not class("battle.UIVisibility").bottomVisible(s, false) then return entries, false end
      for i = 1, 2 do
        local labels, label = s.labels, s.labels[i]
        add(rect((s.tx+1)*8, (s.ty+s.firstItem+(i-1)*2)*8, (s.tw-2)*8, 8),
          function() s.index = i end,
          function() return s.pending == nil and s.labels == labels and labels[i] == label end)
      end
    elseif s.boxTx and native(s, "render.TextBox") then
      local function ready()
        return not s.choicePushed and not s.preSound and not s.sfxWait
          and (s.holdFrames or 0) <= 0 and (s.pauseFrames or 0) <= 0 and (s.preWait or 0) <= 0
          and ((s.waiting and not s:sfxHeld()) or (s.done and not s.choice
            and not s:sfxHeld() and (not s.stay or (s.stay.prompt and not s.stayShown))
            and (not s.auto or (s.auto.promptFirst and not s.autoPrompted))))
      end
      entries.hint = "Waiting for dialogue / sound."
      if ready() and class("battle.UIVisibility").bottomVisible(s, true) then
        entries.hint = "Continue: click to advance dialogue."
        local page, waiting, done, line, shown = s.pageIndex, s.waiting, s.done, s.lineIndex, s.shown
        add(rect(s.boxTx*8, s.boxTy*8, s.boxTw*8, s.boxTh*8), nil,
          function() return ready() and s.pageIndex == page and s.waiting == waiting and s.done == done
            and s.lineIndex == line and s.shown == shown end)
        return entries, entries[#entries].action
      elseif (s.waiting or s.done) and not s.choice and not s.auto and not s.stay
          and class("battle.UIVisibility").bottomVisible(s, true) then
        local page, line, shown, waiting, done = s.pageIndex, s.lineIndex, s.shown, s.waiting, s.done
        waitAction(ready, function()
          return s.pageIndex == page and s.lineIndex == line and s.shown == shown
            and s.waiting == waiting and s.done == done and not s.choice and not s.auto and not s.stay
            and class("battle.UIVisibility").bottomVisible(s, true)
        end)
      end
    elseif s.items and s.tx and native(s, "ui.Menu") then
      local scroll, n = s.scroll or 0, math.min(s.maxVisible or #s.items, #s.items)
      rows(function() return s.items end, "index", scroll, n, function(row)
        local y = s.itemY and (s.ty+s.itemY+(row-1)*s.rowStep)*8
          or (s.ty+s.th-2-(n-row)*s.rowStep)*8
        return rect((s.tx+1)*8, y, (s.tw-2)*8, 8)
      end, function() return s.scroll == scroll end)
    elseif s.items and type(s.rows) == "number" and getmetatable(s) == class("ui.ListMenu") then
      local bag = s.modernBag
      local bagId = bag and bag.mod and bag.mod.id
      local knownBag = (bagId == "modern_bag" or bagId == "gen1_wild_ui")
        and not exports("gen1_modern_ui") and not exports("modern_bag_ui")
      if s.script or (not native(s, "ui.ListMenu") and not knownBag)
          or (bag and bag.swapId) then return entries, false end
      local scroll, pocket = s.scroll or 0, bag and bag.pocket
      local count = s.itemBox and math.min(s.rows, s.cursorRows or 3) or s.rows
      local x = s.itemBox and 40 or 8
      if knownBag and bag.icons and bag.mod.options:get("item_icons") ~= false then x = 24 end
      rows(function() return s.items end, "index", scroll, count, function(row)
        return rect(x, s.itemBox and (32+(row-1)*16) or (8+row*16), 152-x, s.itemBox and 16 or 8)
      end, function() return not s.script and s.scroll == scroll
        and s.modernBag == bag and (not bag or (bag.pocket == pocket and not bag.swapId)) end)
    elseif s.mon and s.mon.moves and
        (native(s, "ui.MoveSelectMenu") or native(s, "ui.MoveLearnMenu")) then
      if s.selecting == false then return entries, false end
      local mon = s.mon
      rows(function() return s.mon and s.mon.moves end, "index", 0, #mon.moves,
        function(row) return rect(40, (7+row)*8, 112, 8) end,
        function() return s.mon == mon and s.selecting ~= false end)
    elseif s.items and native(s, "ui.PokedexMenu") then
      local scroll = s.scroll or 0
      rows(function() return s.items end, "index", scroll, s:rows(),
        function(row) return rect(0, 24+(row-1)*16, 112, 8) end,
        function() return s.scroll == scroll end)
    elseif s.index and getmetatable(s) == class("ui.PartyMenu") then
      if s.heal or s.swapAnim or s.moveFrom then return entries, false end
      local wild = s.gen1wildTheme == "party" and featureExports("Gen1Party")
      local g = wild and wild.geometry
      local knownWild = g and g.ROW_H == 16 and g.BODY_TOP == 24 and g.BODY_BOTTOM == 119
      if not native(s, "ui.PartyMenu") and not knownWild then return entries, false end
      local get = function() return party(s, game) end
      if s.submenu then
        local n, x = #(s.subItems or {}), knownWild and 80 or 96
        if not knownWild then
          local fieldX = {strength=80, TELEPORT=80, softboiled=64}
          for _, item in ipairs(s.subItems or {}) do
            x = math.min(x, fieldX[item.move or item.action] or 96)
          end
        end
        local y = ((knownWild and 17 or 18)-n*2)*8
        partySubmenu(get, function(row) return rect(x, y+(row-1)*16, 152-x, 16) end)
      else
        rows(get, "index", 0, #get(), function(row)
          return rect(0, knownWild and (24+(row-1)*16) or class("ui.PartyMenu").entryY(row), 160, 16)
        end, function() return not s.submenu and not s.heal and not s.swapAnim and not s.moveFrom end)
      end
    end
    -- Unknown/custom renderers get the universal dock, never guessed rows.
    return entries, false
  end
  local function scroll(game, s)
    if not s or s.onWheelMoved or s.wheelmoved then return end
    if modernEntry(s) and s.modernDexTabbed and not s.modernMoveDetail then
      local same = context(game, s)
      local page = (s.modernDexPages or {})[s.modernDexPage or 1]
      if not page then return end
      local entries = collect(game, s)
      if #entries == 0 then return end
      local vertical = page.id == "moves" or page.id == "family"
        or (page.id == "info" and s.modernInfoCanScroll)
      -- Extra pages own their controls; their update hooks are not assumed to
      -- be lists. LEFT/RIGHT remains the source controller's tab navigation.
      return function() return same() and not s.modernMoveDetail end,
        {up=vertical and "up" or "left", down=vertical and "down" or "right"}
    end
    if wildScreen(s, "entry.lua") then
      local same = context(game, s)
      local entries = collect(game, s)
      if #entries == 0 then return end
      return same, {up=s.page == "moves" and "up" or "left",
        down=s.page == "moves" and "down" or "right"}
    end
    if type(s.items) ~= "table" then return end
    local recognized = s.modernPokedexUI or s.modernBag
      or s.modernDexOwner or wildScreen(s, "list.lua")
      or nativeSide(s)
      or native(s, "ui.Menu") or native(s, "ui.ListMenu") or native(s, "ui.PokedexMenu")
    if not recognized or s.modernDexSearchOpen or s.actions or s.script then return end
    local entries = collect(game, s)
    if #entries == 0 then return end
    local same, items, count = context(game, s), s.items, #s.items
    local bag, pocket = s.modernBag, s.modernBag and s.modernBag.pocket
    local unchanged = {}
    for i = 1, count do unchanged[i] = identity(function() return s.items end, i) end
    return function()
      if not same() or s.items ~= items or #items ~= count or s.script
          or s.modernDexSearchOpen or s.actions or s.modernBag ~= bag
          or (bag and (bag.pocket ~= pocket or bag.swapId)) then return false end
      for _, valid in ipairs(unchanged) do if not valid() then return false end end
      return true
    end
  end
  return {collect=collect, scroll=scroll}
end
