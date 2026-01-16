import { readFileSync, writeFileSync } from 'node:fs';

const STATE_FILE = 'state.json';
let stateCache = null;

/**
 * Loads the state from state.json, caching it for subsequent calls.
 * @returns {object} The application state.
 */
export function loadState() {
  if (stateCache) {
    return stateCache;
  }
  try {
    const data = readFileSync(STATE_FILE, 'utf8');
    stateCache = JSON.parse(data);
    return stateCache;
  } catch (error) {
    if (error.code === 'ENOENT') {
      console.log('No state file found, starting fresh.');
      return {}; // Return empty state if file doesn't exist
    }
    console.error('Failed to load state file:', error);
    throw error;
  }
}

/**
 * Saves the provided state to state.json.
 * @param {object} state The application state to save.
 */
export function saveState(state) {
  writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
  stateCache = state; // Update cache
} 