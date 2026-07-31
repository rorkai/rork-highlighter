import assert from "node:assert/strict";
import test from "node:test";
import {
  configurationFor,
  loadFixtures,
  parseArguments,
  percentile,
  runBenchmark,
} from "./benchmark.mjs";

/**
 * Verifies percentile selection at stable distribution boundaries.
 */
test("selects nearest-rank percentiles", () => {
  const samples = [10, 20, 30, 40, 50];
  assert.equal(percentile(samples, 0), 10);
  assert.equal(percentile(samples, 50), 30);
  assert.equal(percentile(samples, 90), 50);
  assert.equal(percentile(samples, 100), 50);
  assert.equal(percentile([10, 20, 30, 40], 50), 20);
});

/**
 * Verifies size-specific sampling limits shared with Swift.
 */
test("selects fixture configurations", () => {
  assert.deepEqual(configurationFor("4KiB"), {
    maximumDurationSeconds: 3,
    maximumIterations: 100,
  });
  assert.deepEqual(configurationFor("64KiB"), {
    maximumDurationSeconds: 5,
    maximumIterations: 50,
  });
  assert.deepEqual(configurationFor("256KiB"), {
    maximumDurationSeconds: 10,
    maximumIterations: 20,
  });
});

/**
 * Verifies filtering and structured-output command options.
 */
test("parses command options", () => {
  const options = parseArguments([
    "--filter",
    "256KiB$",
    "--json",
    ".build/results.json",
  ]);
  assert.equal(options.filter?.source, "256KiB$");
  assert.equal(options.jsonPath, ".build/results.json");
});

/**
 * Verifies both runtimes receive the complete generated corpus.
 */
test("loads verified shared fixtures", () => {
  const fixtures = loadFixtures();
  assert.deepEqual(
    fixtures.map((fixture) => fixture.name),
    ["4KiB", "64KiB", "256KiB"],
  );
  for (const fixture of fixtures) {
    assert.ok(fixture.source.includes("let revisionMarker = 1000"));
    assert.ok(fixture.editedSource.includes("let revisionMarker = 2000"));
    assert.equal(fixture.sha256.length, 64);
  }
});

/**
 * Verifies measured campaigns return ordered distribution summaries.
 */
test("summarizes measured operations", () => {
  const result = runBenchmark(
    "Test/Operation/Small",
    { maximumDurationSeconds: 1, maximumIterations: 5 },
    (iteration) => iteration + 1,
  );
  assert.equal(result.samples, 5);
  assert.ok(result.p0 <= result.p50);
  assert.ok(result.p50 <= result.p100);
});
