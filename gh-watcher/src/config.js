import 'dotenv/config';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

export const GITHUB_TOKEN   = process.env.GITHUB_TOKEN || process.env.GH_TOKEN;
export const TRIGGER_PHRASE = process.env.TRIGGER_PHRASE ?? '@crafting-code';
export const WATCHLIST      = readFileSync('watchlist.txt','utf8')
                                 .split(/\r?\n/).filter(Boolean); 
export const USE_SANDBOX_POOL = process.env.USE_SANDBOX_POOL === '1';
export const SANDBOX_POOL_NAME = process.env.SANDBOX_POOL_NAME || 'claude-dev-pool';
export const CMD_DIR = process.env.CMD_DIR || '/home/owner/cmd';
export const PROCESS_EXISTING_PRS = process.env.PROCESS_EXISTING_PRS === 'true';
export const PR_LABELS = (process.env.PR_LABELS || '')
  .split(',')
  .map((label) => label.trim())
  .filter(Boolean);
export const SANDBOX_TEMPLATE_NAME = process.env.SANDBOX_TEMPLATE_NAME || '';
export const SANDBOX_DEF_PATH = process.env.SANDBOX_DEF_PATH
  || resolve(process.cwd(), '..', 'claude-code-automation', 'template.yaml');
export const TOOL_WHITELIST_JSON = process.env.TOOL_WHITELIST_JSON
  || JSON.stringify([
    'Bash',
    'Read',
    'Write',
    'Edit',
    'LS',
    'Grep',
  ]);