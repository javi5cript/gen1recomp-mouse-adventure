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
  local function battleGrid()
    local direct = exports("Gen1BattleUI")
    if direct then return direct end
    local bundle = exports("gen1_wild_ui")
    local handle = bundle and bundle.features and bundle.features.gen1battleui
    return handle and handle.exports
  end
  local function rect(x, y, w, h) return {x=x, y=y, w=w, h=h} end
  local function options(game, id)
    local o = game.save and game.save.options
    return o and o.modOptions and o.modOptions[id] or {}
  end
  local function party(s, game) return s.party or (game.save and game.save.party) or {} end

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
    "modernPartyNamingCommand", "lower", "script"}
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
    local id, value, label, selectFn
    if type(item) == "table" then
      id, value, label, selectFn = item.id, item.value, item.label, item.onSelect
    end
    return function()
      local now = get()
      if now ~= list or #now ~= count or now[index] ~= item then return false end
      return type(item) ~= "table" or
        (item.id == id and item.value == value and item.label == label
          and item.onSelect == selectFn)
    end
  end

  local function collect(game, s)
    local entries = {}
    if not s or not game.stack or game.stack:top() ~= s then return entries, false end
    if game.save and game.save.generation == 2 then return entries, false end
    -- Demo-owned bag and text states are scripted too, not just the battle.
    for _, owner in ipairs(game.stack.states or {}) do
      if owner.isBattle and (owner.demo or owner.kind == "link") then return entries, false end
    end
    local same = context(game, s)
    local function add(r, select, valid, button)
      if not r or r.w <= 0 or r.h <= 0 then return end
      entries[#entries+1] = {rect=r, action={button=button or "a",
        select=select, valid=function() return same() and (not valid or valid()) end}}
    end
    local function rows(get, field, first, count, geometry, extra)
      local list = get()
      if type(list) ~= "table" then return end
      for row = 1, count do
        local index = first + row
        if list[index] == nil then break end
        local valid = identity(get, index)
        add(geometry(row, index), function() s[field] = index end,
          function() return valid() and (not extra or extra()) end)
      end
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
        local chosen = s.index
        local monValid = identity(get, chosen)
        rows(function() return s.subItems end, "subIndex", 0, n,
          function(row) return rect(x+5, y+13+(row-1)*12, w-10, 11) end,
          function() return s.index == chosen and monValid() end)
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

    if s.modernPokedexUI or (s.modernDexOwner and not s.modernDexAreaBridge) then
      local owner = s.modernDexOwner or s
      local w = game.renderer and game.renderer:uiSize() or owner:uiSize()
      w = math.max(160, math.floor(w))
      local wide, listW = w >= 240, w >= 240 and math.max(154, math.floor(w*0.56)) or w-8
      if s.modernDexOwner then
        if getmetatable(s) ~= class("ui.Menu") then return entries, false end
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
      if getmetatable(s) ~= class("battle.BattleState") or s.demo or s.kind == "link" then return entries, false end
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
      local grid = battleGrid()
      -- Kanto Gear may render the choices in a separate device. Its hidden
      -- upper UI must not leave live rectangles over the battle scene.
      local gridOn = grid and grid.geometry and grid.owns and grid.owns(s)
        and underneath[s] == true and not exports("kanto_gear")
      local wide = s:wideLayout()
      if not ready() then
        if visible and s.phase == "messages" and not s.animPlaying
            and ((s.msgWaiting and (s.msgPreWait or 0) <= 0)
              or (s.msgPrompt and (s.msgPromptWait or 0) <= 0)) then
          local current, shown = s.current, s.shown
          add(rect(0, wide and 104 or 96, wide and 304 or 160, wide and 40 or 48), nil,
            function() return s.current == current and s.shown == shown
              and not s.animPlaying and (s.msgWaiting or s.msgPrompt) end)
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
      if ready() and class("battle.UIVisibility").bottomVisible(s, true) then
        local page, waiting, done = s.pageIndex, s.waiting, s.done
        add(rect(s.boxTx*8, s.boxTy*8, s.boxTw*8, s.boxTh*8), nil,
          function() return ready() and s.pageIndex == page and s.waiting == waiting and s.done == done end)
        return entries, entries[#entries].action
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
    elseif s.index and native(s, "ui.PartyMenu") then
      if s.heal or s.swapAnim or s.submenu then return entries, false end
      rows(function() return party(s, game) end, "index", 0, #party(s, game),
        function(row) return rect(0, class("ui.PartyMenu").entryY(row), 160, 16) end,
        function() return not s.submenu and not s.heal and not s.swapAnim end)
    end
    -- Unknown/custom renderers get the universal dock, never guessed rows.
    return entries, false
  end
  return {collect=collect}
end
