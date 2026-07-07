import { test } from "node:test";
import assert from "node:assert/strict";
import { agents, agentRoster, type AgentId } from "./index.ts";

const ALL_AGENTS: AgentId[] = [
  "william", "marc", "bolton", "leo", "johnny", "robert",
  "conner", "george", "james", "harris", "cole",
];

test("all 11 agents are defined with consistent ids", () => {
  assert.equal(Object.keys(agents).length, 11);
  for (const id of ALL_AGENTS) {
    assert.ok(agents[id], `missing agent config: ${id}`);
    assert.equal(agents[id].id, id);
  }
});

test("agent roster covers every agent exactly once", () => {
  assert.equal(agentRoster.length, 11);
  assert.equal(new Set(agentRoster).size, 11);
});

test("monograms are two lowercase letters and match logo filenames", () => {
  for (const id of ALL_AGENTS) {
    const { monogram, logoFile, name } = agents[id];
    assert.match(monogram, /^[a-z]{2}$/, `${name} monogram`);
    assert.equal(logoFile, `${id}_${monogram}.svg`, `${name} logo filename`);
  }
});
