#!/usr/bin/env node
// The lint-markdown hook: markdownlint-cli2 with config/.markdownlint-cli2.jsonc
require('../lib/run-tool.js')('markdownlint-cli2', process.argv.slice(2));
