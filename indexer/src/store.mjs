import fs from "node:fs";
import path from "node:path";

const EMPTY_STATE = { lastBlock: null, tokens: {}, trades: [] };

export function openStore(filePath) {
  const resolved = path.resolve(filePath);
  fs.mkdirSync(path.dirname(resolved), { recursive: true });
  let state = EMPTY_STATE;
  try {
    state = { ...EMPTY_STATE, ...JSON.parse(fs.readFileSync(resolved, "utf8")) };
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  const save = () => {
    const temporary = `${resolved}.tmp`;
    fs.writeFileSync(temporary, JSON.stringify(state, null, 2));
    fs.renameSync(temporary, resolved);
  };
  return { state, save, path: resolved };
}
