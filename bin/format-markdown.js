#!/usr/bin/env node
// The format-markdown hook: Prettier with config/prettierrc.json
require('../lib/run-tool.js')('prettier', process.argv.slice(2));
