const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawn } = require('child_process');
const luaparse = require('luaparse');

const root = path.resolve(__dirname, '..', '..');
const runtimeFiles = ['manifest.json', 'main.lua', 'mouse_ui.lua', 'mouse_targets.lua',
  'README.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md'];
const sha256 = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');

async function runGame(exe, game, runRoot) {
  const identity = `mouse-adventure-smoke-${game}-${crypto.randomUUID()}`;
  const isolated = path.join(process.env.APPDATA, identity);
  const output = path.join(runRoot, game);
  const sourceCache = path.join(process.env.APPDATA, 'pokemon-love2d', game);
  if (!fs.existsSync(path.join(sourceCache, 'rom-cache.complete'))) {
    throw new Error(`Import your ${game} game in Gen1Recomp first; its cache is missing.`);
  }
  // A fresh identity contains no real saves, settings, other mods or links
  // back to live data. Copy cache data, never share a writable junction.
  fs.mkdirSync(isolated);
  fs.mkdirSync(output);
  const cache = path.join(isolated, game);
  fs.mkdirSync(cache);
  for (const name of ['data', 'assets', 'rom-cache.complete']) {
    fs.cpSync(path.join(sourceCache, name), path.join(cache, name), {
      recursive: true, errorOnExist: true, force: false,
      filter: source => {
        if (fs.lstatSync(source).isSymbolicLink()) {
          throw new Error(`Refusing linked cache content: ${source}`);
        }
        return true;
      },
    });
  }
  const mod = path.join(isolated, 'mods', 'click_to_move');
  fs.mkdirSync(mod, { recursive: true });
  for (const name of runtimeFiles) fs.copyFileSync(path.join(root, name), path.join(mod, name));
  fs.copyFileSync(path.join(__dirname, 'options.lua'), path.join(isolated, 'options.lua'));
  const metadata = {
    game, identity, isolated, startedAt: new Date().toISOString(),
    engineSha256: sha256(exe),
    files: Object.fromEntries(runtimeFiles.map(name => [name, sha256(path.join(mod, name))])),
    cacheMarkerSha256: sha256(path.join(cache, 'rom-cache.complete')),
    input: 'LOVE mouse callbacks; native POKEPORT_DRIVER; no gameplay-state writes',
  };
  fs.writeFileSync(path.join(output, 'environment.json'), JSON.stringify(metadata, null, 2));
  const env = { ...process.env };
  // Inherited developer shortcuts must not skip startup or select real saves.
  for (const key of Object.keys(env)) if (/^POKEPORT_/i.test(key)) delete env[key];
  Object.assign(env, {
    POKEPORT_DRIVER: path.join(__dirname, 'driver.lua'),
    POKEPORT_IDENTITY: identity,
    POKEPORT_VERSION: game,
    POKEPORT_SPEED: '1',
    MOUSE_ADVENTURE_REPORT: path.join(output, 'result.json'),
  });
  console.log(`SMOKE ${game}: isolated profile ${isolated}`);
  const log = fs.openSync(path.join(output, 'engine.log'), 'w');
  let code;
  try {
    code = await new Promise((resolve, reject) => {
      const child = spawn(exe, [`--game=${game}`], {
        cwd: path.dirname(exe), env, stdio: ['ignore', log, log], windowsHide: false,
      });
      let timedOut = false;
      const timer = setTimeout(() => {
        timedOut = true;
        child.kill();
      }, 600000);
      child.once('error', error => { clearTimeout(timer); reject(error); });
      child.once('exit', status => {
        clearTimeout(timer);
        if (timedOut) reject(new Error(`${game} exceeded 10 minutes; its isolated test process was stopped.`));
        else resolve(status);
      });
    });
  } finally {
    fs.closeSync(log);
    const screenshots = path.join(isolated, 'smoke');
    if (fs.existsSync(screenshots)) fs.cpSync(screenshots, path.join(output, 'screenshots'), { recursive: true });
  }
  const reportFile = path.join(output, 'result.json');
  if (!fs.existsSync(reportFile)) {
    throw new Error(`${game} exited (${code}) without a report. Inspect ${path.join(output, 'engine.log')}`);
  }
  const result = JSON.parse(fs.readFileSync(reportFile, 'utf8'));
  if (code !== 0 || result.status !== 'passed') {
    throw new Error(`${game}: ${result.error || result.status}; report: ${reportFile}`);
  }
  console.log(`SMOKE ${game}: PASS (${result.milestones.length} milestones); ${reportFile}`);
  return result;
}

(async () => {
  if (process.platform !== 'win32' || !process.env.APPDATA) throw new Error('Windows with APPDATA is required.');
  const [exeArg, game = 'all'] = process.argv.slice(2);
  if (!exeArg || !['all', 'red', 'blue', 'yellow'].includes(game)) {
    throw new Error('Use scripts\\dev.ps1 -Task Smoke -AllGames (or -Game red|blue|yellow).');
  }
  const exe = fs.realpathSync(exeArg);
  for (const directory of [path.dirname(exe), process.cwd()]) {
    if (fs.existsSync(path.join(directory, 'portable.txt'))) {
      throw new Error('Portable mode bypasses save identity isolation. Use a non-portable game installation.');
    }
  }
  for (const name of ['driver.lua', 'options.lua']) {
    luaparse.parse(fs.readFileSync(path.join(__dirname, name), 'utf8'), { luaVersion: '5.1' });
  }
  const runRoot = path.join(root, '.dev-cache', 'smoke',
    new Date().toISOString().replace(/[:.]/g, '-') + '-' + crypto.randomUUID().slice(0, 8));
  fs.mkdirSync(runRoot, { recursive: true });
  console.log(`SMOKE reports: ${runRoot}`);
  const results = [];
  for (const version of game === 'all' ? ['red', 'blue', 'yellow'] : [game]) {
    try {
      results.push(await runGame(exe, version, runRoot));
    } catch (error) {
      console.error(`SMOKE ${version}: FAIL: ${error.message}`);
      results.push({ game: version, status: 'failed', error: error.message });
    }
    fs.writeFileSync(path.join(runRoot, 'summary.json'), JSON.stringify(results, null, 2));
  }
  if (results.some(result => result.status !== 'passed')) process.exitCode = 1;
})().catch(error => { console.error(error.stack); process.exitCode = 1; });
