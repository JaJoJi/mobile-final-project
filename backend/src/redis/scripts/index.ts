import * as fs from 'fs';
import * as path from 'path';

export const LUA_SCRIPTS: Record<string, string> = {
  phase_flip: fs.readFileSync(path.join(__dirname, 'phase_flip.lua'), 'utf8'),
  combat_done: fs.readFileSync(path.join(__dirname, 'combat_done.lua'), 'utf8'),
  action_log: fs.readFileSync(path.join(__dirname, 'action_log.lua'), 'utf8'),
  match_pair: fs.readFileSync(path.join(__dirname, 'match_pair.lua'), 'utf8'),
  ws_rate_limit: fs.readFileSync(path.join(__dirname, 'ws_rate_limit.lua'), 'utf8'),
};
