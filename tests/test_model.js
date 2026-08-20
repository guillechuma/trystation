const assert = require("node:assert/strict");
const model = require("../TryModel.js");

const sessions = [
  { title: "Shader Lab", name: "2026-08-12-shader-lab", group: "QML", note: "CRT", language: "QML", branch: "main", modified: 20 },
  { title: "Redis Pool", name: "2026-08-11-redis-pool", group: "Backend", note: "", language: "Ruby", branch: "experiment", modified: 10 }
];

assert.equal(model.filtered(sessions, "crt", "").length, 1);
assert.equal(model.filtered(sessions, "", "Backend")[0].title, "Redis Pool");
assert.equal(model.fuzzyFiltered(sessions, "sdr", 5)[0].title, "Shader Lab");
assert.equal(model.fuzzyFiltered(sessions, "redis backend", 5)[0].title, "Redis Pool");
assert.equal(model.fuzzyFiltered(sessions, "missing", 5).length, 0);
assert.equal(model.fuzzyFiltered(sessions, "", 1).length, 1);
assert.deepEqual(model.groups(sessions), ["Backend", "QML"]);
assert.equal(model.statusLabel({ git: true, changes: 3 }), "DIRTY ×3");
assert.equal(model.statusLabel({ graduated: true }), "GRADUATED");
assert.equal(model.pathLabel("/home/test/Work/tries", "/home/test"), "~/Work/tries");
assert.equal(model.parsePayload("not json").path, undefined);
console.log("TryModel tests passed");
