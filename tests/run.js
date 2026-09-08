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
      'src.ui.NamingScreen', 'src.render.TextBox', 'src.script.Tokens',
      'src.ui.IntroMovie', 'src.ui.YellowIntro', 'src.ui.TitleState',
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
    for (const method of ['updateQueue', 'beginMsgLine']) {
      const node = battleAst.body.find(node =>
        node.type === 'FunctionDeclaration' && node.identifier.type === 'MemberExpression' &&
        node.identifier.base.name === 'BattleState' && node.identifier.identifier.name === method);
      if (!node) throw new Error('Native battle method not found: ' + method);
      lua.global.set('BATTLE_' + method.toUpperCase() + '_SOURCE', battle.slice(...node.range));
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
    lua.global.set('MOD_SOURCE', fs.readFileSync(
      path.join(modRoot, 'main.lua'), 'utf8'));
    lua.global.set('MOD_FILES', Object.fromEntries(
      ['mouse_ui.lua', 'mouse_targets.lua'].map(name => [name, fs.readFileSync(
        path.join(modRoot, name), 'utf8')])
    ));
    await lua.doString(fs.readFileSync(path.join(__dirname, 'controls.lua'), 'utf8'));
  } finally {
    lua.global.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
