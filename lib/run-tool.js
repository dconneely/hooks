// Runs Prettier or markdownlint-cli2 from this package's dependencies, with
// the config file this package ships in config/, for the format-markdown
// and lint-markdown hooks.
//
// A bin script rather than the tools' own bins: npm puts an installed
// package's own bins on the hook's PATH, not its dependencies' (verified on
// Linux with prek 0.5.10, which is why v0.1.0's prettier hook needed
// additional_dependencies). Node.js rather than sh, since npm runs a bin on
// Windows through a shim that needs one.
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const configDir = path.join(__dirname, '..', 'config');

const tools = {
  prettier: {
    pkg: 'prettier',
    bin: 'bin/prettier.cjs',
    args: ['--config', path.join(configDir, 'prettierrc.json'), '--write', '--ignore-unknown'],
  },
  'markdownlint-cli2': {
    pkg: 'markdownlint-cli2',
    bin: 'markdownlint-cli2-bin.mjs',
    // markdownlint-cli2 takes --config only for a file named like one of its
    // own config files
    args: ['--config', path.join(configDir, '.markdownlint-cli2.jsonc')],
  },
};

// The package's directory, from Node's resolution paths for this file.
// Not require.resolve: markdownlint-cli2's "exports" hide its bin file
// (verified with 0.23.2). The paths cover both installs: the package's own
// node_modules when prek installs this repository for a consumer, and the
// environment's when this repository runs its local copies.
function packageDir(pkg) {
  for (const base of require.resolve.paths(pkg) || []) {
    const dir = path.join(base, pkg);
    if (fs.existsSync(path.join(dir, 'package.json'))) return dir;
  }
  return null;
}

module.exports = function runTool(name, argv) {
  const tool = tools[name];
  const dir = packageDir(tool.pkg);
  if (!dir) {
    console.error(`${path.basename(process.argv[1])}: ${tool.pkg} is not installed`);
    process.exit(2);
  }
  const result = spawnSync(process.execPath, [path.join(dir, tool.bin), ...tool.args, ...argv], {
    stdio: 'inherit',
  });
  if (result.error) {
    console.error(`${path.basename(process.argv[1])}: ${result.error.message}`);
    process.exit(2);
  }
  process.exit(result.status === null ? 1 : result.status);
};
