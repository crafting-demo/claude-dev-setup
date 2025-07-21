import 'dotenv/config';
import { readFileSync } from 'node:fs';

export const GITHUB_TOKEN   = process.env.GITHUB_TOKEN;
export const TRIGGER_PHRASE = process.env.TRIGGER_PHRASE ?? '@crafting-code';
export const WATCHLIST      = readFileSync('watchlist.txt','utf8')
                                 .split(/\r?\n/).filter(Boolean); 
export const USE_SANDBOX_POOL = 1;
export const SANDBOX_POOL_NAME = 'claude-dev-pool';