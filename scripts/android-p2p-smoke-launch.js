#!/usr/bin/env node
const { spawn, spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const apkPath = path.join(root, 'android/app/build/outputs/apk/p2pSmoke/debug/app-p2pSmoke-debug.apk');
const packageName = 'com.linxmobile.p2psmoke';
const activityName = 'com.linxmobile.MainActivity';

if (require.main === module) {
  main(process.argv.slice(2)).catch(error => {
    console.error(error?.stack || error?.message || String(error));
    process.exit(1);
  });
} else {
  module.exports = {
    tryCaptureResultLine,
  };
}

async function main(argv) {
  const args = parseArgs(argv);
  const device = createDeviceTransport(args);
  const commands = createCommands(args, device);

  if (args.help) {
    usage();
    return;
  }

  if (args.dryRun) {
    printDryRun(args, commands);
    return;
  }

  if (!args.skipBuild) {
    run(commands.build.command, commands.build.args, { cwd: commands.build.cwd });
  }
  if (!fs.existsSync(apkPath)) {
    throw new Error(`APK not found: ${apkPath}`);
  }
  if (!args.skipInstall) {
    run(commands.install.command, commands.install.args, { env: commands.install.env });
  }

  let capture;
  if (args.captureResult) {
    run(commands.clearLogcat.command, commands.clearLogcat.args, { env: commands.clearLogcat.env });
    capture = captureResultFromDeviceLog({
      command: commands.captureLogcat.command,
      args: commands.captureLogcat.args,
      env: commands.captureLogcat.env,
      outputPath: args.captureResult,
      timeoutMs: args.captureTimeoutMs,
      echo: args.logcat,
    });
  }

  run(commands.start.command, commands.start.args, { env: commands.start.env });

  if (capture) {
    await capture;
  } else if (args.logcat) {
    run(commands.logcat.command, commands.logcat.args, { env: commands.logcat.env });
  }
}

function createDeviceTransport(args) {
  if (args.transport === 'adb') {
    const env = { ...process.env };
    if (args.adbServerPort) env.ANDROID_ADB_SERVER_PORT = args.adbServerPort;
    return {
      kind: 'adb',
      command: args.adb || process.env.ADB || 'adb',
      targetArgs: [],
      env,
      logName: 'logcat',
    };
  }
  if (args.transport === 'hdc') {
    const command = args.hdc || process.env.HDC || process.env.OHOS_HDC || 'hdc';
    const env = { ...process.env };
    const libDir = args.hdcLibDir || process.env.HDC_LIB_DIR || process.env.OHOS_HDC_LIB_DIR || inferHdcLibDir(command);
    if (libDir) {
      env.DYLD_LIBRARY_PATH = env.DYLD_LIBRARY_PATH ? `${libDir}:${env.DYLD_LIBRARY_PATH}` : libDir;
    }
    return {
      kind: 'hdc',
      command,
      targetArgs: args.hdcTarget ? ['-t', args.hdcTarget] : [],
      env,
      logName: 'hilog',
    };
  }
  throw new Error(`Unsupported transport: ${args.transport}`);
}

function inferHdcLibDir(command) {
  if (!command || command === 'hdc') return undefined;
  return path.dirname(path.resolve(command));
}

function deviceArgs(device, args) {
  return [...device.targetArgs, ...args];
}

function createCommands(args, device) {
  const launchExtras = [
    ['xpod.p2p.localSpUrl', args.localSpUrl],
    ['xpod.p2p.idpUrl', args.idpUrl],
    ['xpod.p2p.storageUrl', args.storageUrl],
    ['xpod.p2p.apiBaseUrl', args.apiBaseUrl],
    ['xpod.p2p.nodeId', args.nodeId],
    ['xpod.p2p.clientId', args.clientId],
    ['xpod.p2p.resourcePath', args.resourcePath],
    ['xpod.update.manifestUrl', args.updateManifestUrl],
  ].flatMap(([name, value]) => value ? ['--es', name, value] : []);
  return {
    build: { command: './gradlew', args: [':app:assembleP2pSmokeDebug'], cwd: path.join(root, 'android') },
    install: { command: device.command, args: deviceArgs(device, ['install', '-r', apkPath]), env: device.env },
    start: {
      command: device.command,
      args: deviceArgs(device, [
        'shell',
        'am',
        'start',
        '-n',
        `${packageName}/${activityName}`,
        ...launchExtras,
      ]),
      env: device.env,
    },
    logcat: device.kind === 'hdc'
      ? { command: device.command, args: deviceArgs(device, ['hilog', '-T', 'XpodP2PSmoke']), env: device.env }
      : { command: device.command, args: deviceArgs(device, ['logcat', '-s', 'ReactNativeJS', 'XpodP2PSmoke']), env: device.env },
    clearLogcat: device.kind === 'hdc'
      ? { command: device.command, args: deviceArgs(device, ['hilog', '-r']), env: device.env }
      : { command: device.command, args: deviceArgs(device, ['logcat', '-c']), env: device.env },
    captureLogcat: device.kind === 'hdc'
      ? { command: device.command, args: deviceArgs(device, ['hilog', '-T', 'XpodP2PSmoke']), env: device.env }
      : { command: device.command, args: deviceArgs(device, ['logcat', '-v', 'raw', '-s', 'XpodP2PSmoke:I', '*:S']), env: device.env },
  };
}

function parseArgs(argv) {
  const out = {
    localSpUrl: process.env.XPOD_P2P_SMOKE_LOCAL_SP_URL,
    idpUrl: process.env.XPOD_P2P_SMOKE_IDP_URL || 'https://id.undefineds.co/',
    storageUrl: process.env.XPOD_P2P_SMOKE_STORAGE_URL || 'https://node-0000.undefineds.co/',
    apiBaseUrl: process.env.XPOD_P2P_SMOKE_API_BASE_URL,
    nodeId: process.env.XPOD_P2P_SMOKE_NODE_ID,
    updateManifestUrl: process.env.LINX_UPDATE_MANIFEST_URL || process.env.XPOD_LINX_UPDATE_MANIFEST_URL,
    clientId: process.env.XPOD_P2P_SMOKE_CLIENT_ID || `phone-${Math.floor(Date.now() / 1000)}`,
    resourcePath: process.env.XPOD_P2P_SMOKE_RESOURCE_PATH || '.data/linx-mobile-p2p-smoke.txt',
    transport: process.env.XPOD_P2P_ANDROID_TRANSPORT || process.env.XPOD_P2P_DEVICE_TRANSPORT || 'adb',
    adbServerPort: process.env.ANDROID_ADB_SERVER_PORT,
    hdcTarget: process.env.HDC_TARGET || process.env.OHOS_HDC_TARGET || process.env.XPOD_HDC_TARGET,
    hdcLibDir: process.env.HDC_LIB_DIR || process.env.OHOS_HDC_LIB_DIR || process.env.XPOD_HDC_LIB_DIR,
    skipBuild: false,
    skipInstall: false,
    dryRun: false,
    logcat: false,
    captureResult: undefined,
    captureTimeoutMs: 120_000,
    help: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const equalsIndex = arg.indexOf('=');
    const key = equalsIndex === -1 ? arg : arg.slice(0, equalsIndex);
    const inline = equalsIndex === -1 ? undefined : arg.slice(equalsIndex + 1);
    const read = () => {
      const value = inline !== undefined ? inline : argv[++i];
      if (value === undefined) throw new Error(`Missing value for ${arg}`);
      return value;
    };
    switch (key) {
      case '--local-sp-url': out.localSpUrl = read(); break;
      case '--idp-url': out.idpUrl = read(); break;
      case '--storage-url': out.storageUrl = read(); break;
      case '--api-base-url': out.apiBaseUrl = read(); break;
      case '--node-id': out.nodeId = read(); break;
      case '--update-manifest-url': out.updateManifestUrl = read(); break;
      case '--client-id': out.clientId = read(); break;
      case '--resource-path': out.resourcePath = read(); break;
      case '--transport':
      case '--device-transport': out.transport = read(); break;
      case '--adb': out.adb = read(); break;
      case '--adb-server-port': out.adbServerPort = read(); break;
      case '--hdc': out.hdc = read(); break;
      case '--hdc-target': out.hdcTarget = read(); break;
      case '--hdc-lib-dir': out.hdcLibDir = read(); break;
      case '--skip-build': out.skipBuild = true; break;
      case '--skip-install': out.skipInstall = true; break;
      case '--dry-run': out.dryRun = true; break;
      case '--logcat': out.logcat = true; break;
      case '--capture-result': out.captureResult = read(); break;
      case '--capture-timeout-ms': out.captureTimeoutMs = Number.parseInt(read(), 10); break;
      case '--help':
      case '-h': out.help = true; break;
      default: throw new Error(`Unknown argument: ${arg}`);
    }
  }
  for (const key of ['idpUrl', 'storageUrl', 'clientId', 'resourcePath']) {
    if (!out[key] || !String(out[key]).trim()) throw new Error(`${key} is required`);
  }
  if (out.transport !== 'adb' && out.transport !== 'hdc') {
    throw new Error('transport must be adb or hdc');
  }
  if (!Number.isInteger(out.captureTimeoutMs) || out.captureTimeoutMs <= 0) {
    throw new Error('captureTimeoutMs must be a positive integer');
  }
  return out;
}

function printDryRun(options, commands) {
  console.log('DRY RUN: Android LinX P2P Smoke launch plan');
  console.log(`transport=${options.transport}`);
  if (options.adbServerPort) {
    console.log(`ANDROID_ADB_SERVER_PORT=${options.adbServerPort}`);
  }
  if (options.transport === 'hdc' && options.hdcLibDir) {
    console.log(`HDC_LIB_DIR=${options.hdcLibDir}`);
  }
  if (options.skipBuild) {
    console.log('# build skipped by --skip-build');
  } else {
    console.log(`cd ${shellQuote(path.relative(root, commands.build.cwd) || '.')} && ${shellCommand(commands.build.command, commands.build.args)}`);
  }
  if (options.skipInstall) {
    console.log('# install skipped by --skip-install');
  } else {
    console.log(shellCommand(commands.install.command, commands.install.args));
  }
  if (options.captureResult) {
    console.log(shellCommand(commands.clearLogcat.command, commands.clearLogcat.args));
    console.log(`# capture RESULT_JSON from XpodP2PSmoke into ${options.captureResult} within ${options.captureTimeoutMs}ms`);
    console.log(shellCommand(commands.captureLogcat.command, commands.captureLogcat.args));
  }
  console.log(shellCommand(commands.start.command, commands.start.args));
  if (options.logcat) {
    console.log(shellCommand(commands.logcat.command, commands.logcat.args));
  }
}

function shellCommand(command, args) {
  return [command, ...args].map(shellQuote).join(' ');
}

function shellQuote(value) {
  const string = String(value);
  if (/^[A-Za-z0-9_./:=@+-]+$/.test(string)) return string;
  return `'${string.replace(/'/g, `'\\''`)}'`;
}

function run(command, args, options = {}) {
  const result = spawnSync(command, args, {
    stdio: 'inherit',
    cwd: options.cwd || root,
    env: options.env || process.env,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status || 1);
}

function captureResultFromDeviceLog({
  command,
  args: commandArgs,
  env,
  outputPath,
  timeoutMs,
  echo,
}) {
  const marker = 'RESULT_JSON ';
  const resolvedOutputPath = path.resolve(process.cwd(), outputPath);
  return new Promise((resolve, reject) => {
    const child = spawn(command, commandArgs, {
      cwd: root,
      env: env || process.env,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    let settled = false;
    let buffer = '';
    const timer = setTimeout(() => {
      finish(new Error(`Timed out waiting for ${marker.trim()} in device logs after ${timeoutMs}ms`));
    }, timeoutMs);

    child.stdout.setEncoding('utf8');
    child.stdout.on('data', chunk => {
      if (echo) process.stdout.write(chunk);
      buffer += chunk;
      const lines = buffer.split(/\r?\n/);
      buffer = lines.pop() || '';
      for (const line of lines) {
        try {
          if (tryCaptureResultLine(line, resolvedOutputPath)) {
            console.log(`Captured P2P smoke result: ${resolvedOutputPath}`);
            finish(null);
            break;
          }
        } catch (error) {
          finish(new Error(`Invalid ${marker.trim()} payload: ${error.message}`));
        }
      }
    });
    child.stderr.setEncoding('utf8');
    child.stderr.on('data', chunk => {
      if (echo) process.stderr.write(chunk);
    });
    child.on('error', finish);
    child.on('exit', code => {
      if (!settled) {
        finish(new Error(`device log command exited before ${marker.trim()} was captured (code ${code})`));
      }
    });

    function finish(error) {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (!child.killed) child.kill();
      if (error) {
        reject(error);
      } else {
        resolve();
      }
    }
  });
}

function tryCaptureResultLine(line, outputPath) {
  const marker = 'RESULT_JSON ';
  const index = line.indexOf(marker);
  if (index === -1) return false;
  const jsonText = line.slice(index + marker.length).trim();
  const parsed = JSON.parse(jsonText);
  const resolvedOutputPath = path.resolve(process.cwd(), outputPath);
  fs.mkdirSync(path.dirname(resolvedOutputPath), { recursive: true });
  fs.writeFileSync(resolvedOutputPath, `${JSON.stringify(parsed, null, 2)}\n`);
  return true;
}

function usage() {
  console.log(`Usage: npm run p2p:android:launch -- [options]

Builds, installs, and launches the Android LinX P2P Smoke package with verifier fields prefilled.

Options:
  --local-sp-url <url>     Prefill Local SP server root, e.g. https://node-0000.undefineds.co/
  --idp-url <url>          Default: ${'https://id.undefineds.co/'}
  --storage-url <url>      Default: ${'https://node-0000.undefineds.co/'}
  --api-base-url <url>     Optional explicit Xpod API base URL.
  --node-id <id>           Optional explicit node id.
  --client-id <id>         Default: phone-<timestamp>
  --resource-path <path>   Default: .data/linx-mobile-p2p-smoke.txt
  --update-manifest-url <url> Optional update manifest URL for automatic upgrade prompt.
  --transport <adb|hdc>    Device transport. Default: adb.
  --adb <path>             adb executable. Default: adb
  --adb-server-port <port> Set ANDROID_ADB_SERVER_PORT for this run.
  --hdc <path>             hdc executable. Default: hdc
  --hdc-target <id>        Harmony device target passed as hdc -t <id>.
  --hdc-lib-dir <dir>      Directory containing hdc dynamic libraries. Defaults to dirname(--hdc).
  --skip-build             Do not rebuild APK before install.
  --skip-install           Do not install APK before launch.
  --dry-run                Print commands without building, installing, or launching.
  --logcat                 Attach adb logcat for ReactNativeJS/XpodP2PSmoke.
  --capture-result <path>  Wait for XpodP2PSmoke RESULT_JSON and write verifier JSON.
  --capture-timeout-ms <n> Timeout for --capture-result. Default: 120000.
`);
}
