const fs = require('fs');
const path = require('path');
const { LuaFactory } = require('wasmoon');
const luaparse = require('luaparse');

(async () => {
  const lua = await new LuaFactory().createEngine();
  try {
    const root = process.env.GEN1RECOMP_SOURCE;
    if (!root) throw new Error('Use scripts\\dev.ps1 -Task Test to prepare the installed engine source.');
    const modules = [
      'src.core.Input', 'src.core.Timing', 'src.world.Player',
      'src.world.Collision', 'src.render.Camera', 'src.render.Transition',
      'src.mods.Hooks',
      'src.ui.Menu', 'src.ui.ListMenu', 'src.ui.ChoiceBox', 'src.ui.MenuRepeat',
      'src.ui.NamingScreen', 'src.ui.PokedexMenu', 'src.render.TextBox', 'src.script.Tokens',
      'src.ui.IntroMovie', 'src.ui.YellowIntro', 'src.ui.TitleState',
      'src.ui.Screens',
    ];
    for (const name of modules) {
      const source = fs.readFileSync(path.join(root, ...name.split('.')) + '.lua', 'utf8');
      lua.global.set('MODULE_SOURCE', source);
      lua.global.set('MODULE_NAME', name);
      await lua.doString('package.preload[MODULE_NAME] = assert(load(MODULE_SOURCE, MODULE_NAME))');
    }
    const controller = fs.readFileSync(
      path.join(root, 'src', 'world', 'OverworldController.lua'), 'utf8');
    const ast = luaparse.parse(controller, { luaVersion: '5.1', ranges: true });
    const wanted = new Set(['handleInput', 'checkEdgeExit', 'dirHeld', 'npcAtCell', 'interact']);
    const methods = ast.body.filter(node =>
      node.type === 'FunctionDeclaration' &&
      node.identifier.type === 'MemberExpression' &&
      node.identifier.base.name === 'OverworldState' &&
      wanted.has(node.identifier.identifier.name));
    if (methods.length !== wanted.size) throw new Error('Engine controller methods not found');
    lua.global.set('CONTROLLER_METHODS', methods.map(node =>
      controller.slice(...node.range)).join('\n'));
    const helpers = ast.body.filter(node => node.type === 'FunctionDeclaration' &&
      node.identifier.type === 'Identifier' &&
      ['vanillaTalk', 'interacted'].includes(node.identifier.name));
    if (helpers.length !== 2) throw new Error('Native interaction helpers not found');
    lua.global.set('INTERACTION_HELPERS', helpers.map(node =>
      controller.slice(...node.range)).join('\n'));
    const battle = fs.readFileSync(path.join(root, 'src', 'battle', 'BattleState.lua'), 'utf8');
    const battleAst = luaparse.parse(battle, {luaVersion: '5.1', ranges: true});
    const battleUpdate = battleAst.body.find(node =>
      node.type === 'FunctionDeclaration' && node.identifier.type === 'MemberExpression' &&
      node.identifier.base.name === 'BattleState' && node.identifier.identifier.name === 'update');
    if (!battleUpdate) throw new Error('Native battle input dispatch not found');
    lua.global.set('BATTLE_UPDATE_SOURCE', battle.slice(...battleUpdate.range));
    for (const method of ['updateQueue', 'beginMsgLine', 'openParty']) {
      const node = battleAst.body.find(node =>
        node.type === 'FunctionDeclaration' && node.identifier.type === 'MemberExpression' &&
        node.identifier.base.name === 'BattleState' && node.identifier.identifier.name === method);
      if (!node) throw new Error('Native battle method not found: ' + method);
      lua.global.set('BATTLE_' + method.toUpperCase() + '_SOURCE', battle.slice(...node.range));
    }
    const dex = fs.readFileSync(path.join(root, 'src', 'ui', 'DexEntryMenu.lua'), 'utf8');
    const dexAst = luaparse.parse(dex, {luaVersion: '5.1', ranges: true});
    const dexMethods = dexAst.body.filter(node => node.type === 'FunctionDeclaration' &&
      node.identifier.type === 'MemberExpression' &&
      node.identifier.base.name === 'DexEntryMenu' &&
      ['crying', 'update'].includes(node.identifier.identifier.name));
    if (dexMethods.length !== 2) throw new Error('Native Pokedex entry methods not found');
    lua.global.set('DEX_METHODS', dexMethods.map(node => dex.slice(...node.range)).join('\n'));
    const party = fs.readFileSync(path.join(root, 'src', 'ui', 'PartyMenu.lua'), 'utf8');
    const partyAst = luaparse.parse(party, {luaVersion: '5.1', ranges: true});
    const partyMethods = partyAst.body.filter(node => node.type === 'FunctionDeclaration' &&
      ((node.identifier.type === 'MemberExpression' &&
        node.identifier.base.name === 'PartyMenu' &&
        ['new', 'update', 'gridNavigation', 'entryY', 'close', 'refuse'].includes(node.identifier.identifier.name)) ||
       (node.identifier.type === 'Identifier' &&
        ['sameItems', 'followerUnavailable', 'refuseUnavailable'].includes(node.identifier.name))));
    if (partyMethods.length !== 9) throw new Error('Native party input methods not found');
    lua.global.set('PARTY_METHODS', partyMethods.map(node => party.slice(...node.range)).join('\n'));
    // Keep native input dispatch intact; constructors/art remain headless fixtures.
    for (const [name, wanted] of [
      ['SummaryMenu', ['update']], ['TrainerCard', ['update']],
      ['TownMap', ['update', 'moveList']],
    ]) {
      const source = fs.readFileSync(path.join(root, 'src', 'ui', name + '.lua'), 'utf8');
      const parsed = luaparse.parse(source, {luaVersion: '5.1', ranges: true});
      const selected = parsed.body.filter(node => node.type === 'FunctionDeclaration' &&
        node.identifier.type === 'MemberExpression' && node.identifier.base.name === name &&
        wanted.includes(node.identifier.identifier.name));
      if (selected.length !== wanted.length) throw new Error('Native screen methods missing: ' + name);
      lua.global.set('SCREEN_MODULE', 'src.ui.' + name);
      lua.global.set('SCREEN_METHOD_SOURCE',
        `local ${name} = {}; ${name}.__index = ${name}\n` +
        'local Sound = require("src.core.Sound")\n' +
        'local GameVersion = require("src.core.GameVersion")\nlocal ARROW_DELAY = 15\n' +
        selected.map(node => source.slice(...node.range)).join('\n') +
        `\nfunction ${name}.draw() end\nreturn ${name}`);
      await lua.doString('package.preload[SCREEN_MODULE] = assert(load(SCREEN_METHOD_SOURCE, SCREEN_MODULE))');
    }
    // Optional installed replacement controller sources. Never load/write their
    // assets or lifecycle hooks; exercise the actual authored input methods.
    const replacementRoot = process.env.APPDATA &&
      path.join(process.env.APPDATA, 'pokemon-love2d', 'mods');
    const replacements = [
      ['MODERN_SUMMARY_SOURCE', ['modern_party_ui', 'summary.lua'], 'summary', 'update',
        ['layoutFor']],
      ['MODERN_DEX_SOURCE', ['modern_pokedex_ui', 'screen.lua'], 'state', 'update',
        ['entryPages', 'entryPage', 'entryLayout', 'moveRows', 'moveListState',
          'selectedMoveRow', 'currentEntryLayout', 'resetMoveSelection',
          'moveMoveSelection', 'moveInfoScroll']],
      ['WILD_DEX_SOURCE', ['gen1_wild_ui', 'modules', 'Gen1Dex', 'entry.lua'], 'Entry',
        ['update', 'goTo', 'turnPage', 'advance', 'close', 'stepMovePage', 'movePages'], []],
      ['WILD_AREA_SOURCE', ['gen1_wild_ui', 'modules', 'Gen1Dex', 'area.lua'], 'screen', 'update', []],
    ];
    for (const [global, parts, owner, method, helpers] of replacements) {
      const filename = replacementRoot && path.join(replacementRoot, ...parts);
      if (!filename || !fs.existsSync(filename)) continue;
      const source = fs.readFileSync(filename, 'utf8');
      const nodes = [];
      const methods = Array.isArray(method) ? method : [method];
      const walk = node => {
        if (!node || typeof node !== 'object') return;
        if (node.type === 'FunctionDeclaration' && node.identifier) {
          const id = node.identifier;
          if (id.type === 'Identifier' && helpers.includes(id.name)) nodes.push(node);
          if (id.type === 'MemberExpression' && id.base.name === owner &&
              methods.includes(id.identifier.name)) nodes.push(node);
        }
        if (node.type === 'AssignmentStatement' && node.variables.length === 1) {
          const id = node.variables[0];
          if (id.type === 'MemberExpression' && id.base.name === owner &&
              methods.includes(id.identifier.name) && node.init[0].type === 'FunctionDeclaration') {
            nodes.push(node);
          }
        }
        for (const value of Object.values(node)) {
          if (Array.isArray(value)) value.forEach(walk);
          else if (value && typeof value === 'object') walk(value);
        }
      };
      walk(luaparse.parse(source, {luaVersion: '5.1', ranges: true}));
      if (nodes.length !== helpers.length + methods.length && global !== 'WILD_AREA_SOURCE') {
        throw new Error('Replacement input contract changed: ' + filename);
      }
      if (global === 'WILD_AREA_SOURCE' && nodes.length !== 2) {
        throw new Error('Replacement area input contract changed: ' + filename);
      }
      lua.global.set(global, (global === 'WILD_AREA_SOURCE' ? nodes.slice(-1) : nodes)
        .map(node => source.slice(...node.range)).join('\n'));
    }
    const modRoot = path.resolve(__dirname, '..');
    const manifest = JSON.parse(fs.readFileSync(path.join(modRoot, 'manifest.json'), 'utf8'));
    if (manifest.id !== 'click_to_move' || manifest.entry !== 'main.lua' || manifest.api !== 2 ||
        !/^\d+\.\d+\.\d+(?:-[a-zA-Z0-9.-]+)?$/.test(manifest.version)) {
      throw new Error('Unexpected mod identity, entry point, API, or version.');
    }
    for (const name of ['main.lua', 'mouse_ui.lua', 'mouse_targets.lua']) {
      luaparse.parse(fs.readFileSync(path.join(modRoot, name), 'utf8'), {luaVersion: '5.1'});
    }
    for (const name of ['driver.lua', 'options.lua']) {
      luaparse.parse(fs.readFileSync(path.join(__dirname, 'opening', name), 'utf8'), {luaVersion: '5.1'});
    }
    lua.global.set('MOD_SOURCE', fs.readFileSync(
      path.join(modRoot, 'main.lua'), 'utf8'));
    lua.global.set('MOD_FILES', Object.fromEntries(
      ['mouse_ui.lua', 'mouse_targets.lua'].map(name => [name, fs.readFileSync(
        path.join(modRoot, name), 'utf8')])
    ));
    lua.global.set('SCREEN_TESTS_SOURCE', fs.readFileSync(path.join(__dirname, 'screens.lua'), 'utf8'));
    await lua.doString(fs.readFileSync(path.join(__dirname, 'controls.lua'), 'utf8'));
  } finally {
    lua.global.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
