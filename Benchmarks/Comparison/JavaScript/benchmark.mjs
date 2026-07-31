import { createHash } from "node:crypto";
import { cpus, platform, arch, totalmem } from "node:os";
import {
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import hljs from "highlight.js/lib/core";
import swift from "highlight.js/lib/languages/swift";

/**
 * The benchmark file location makes fixture discovery independent of the shell directory.
 */
const benchmarkDirectory = dirname(fileURLToPath(import.meta.url));

/**
 * The generated fixture directory can be overridden by automation.
 */
const fixtureDirectory =
  process.env.RORK_HIGHLIGHTER_COMPARISON_FIXTURES ??
  resolve(benchmarkDirectory, "..", ".build", "fixtures");

/**
 * The generated manifest records the identity of every shared source file.
 */
const manifestPath = resolve(fixtureDirectory, "manifest.json");

/**
 * Two unmeasured calls match the warm-up count in the Swift benchmark suite.
 */
const warmupIterations = 2;

/**
 * Consuming output makes every measured result observable to the runtime.
 */
let consumedOutputLength = 0;

/**
 * The Swift grammar is registered once and remains outside measured work.
 */
hljs.registerLanguage("swift", swift);

/**
 * Describes the generated manifest consumed by both runtime suites.
 *
 * @typedef {object} FixtureManifest
 * @property {number} schemaVersion This identifies the supported manifest format.
 * @property {string} language This names the language represented by each source file.
 * @property {string} revisionMarker This is the marker in the original source.
 * @property {string} replacementMarker This is the marker used by editing workloads.
 * @property {FixtureManifestEntry[]} fixtures This contains the ordered source descriptions.
 */

/**
 * Describes one generated fixture and its integrity metadata.
 *
 * @typedef {object} FixtureManifestEntry
 * @property {string} name This is the stable benchmark size name.
 * @property {string} fileName This is the filename below the fixture directory.
 * @property {number} minimumUTF16Length This is the requested minimum source length.
 * @property {number} byteCount This is the exact encoded byte count.
 * @property {number} utf16Count This is the exact JavaScript string length.
 * @property {number} lineCount This is the line count including a final empty line.
 * @property {string} sha256 This is the lowercase source digest.
 */

/**
 * Holds a verified source file and its fixed-width edited counterpart.
 *
 * @typedef {object} ComparisonFixture
 * @property {string} name This is the stable benchmark size name.
 * @property {string} source This contains the original generated Swift source.
 * @property {string} editedSource This contains the source after its marker changes.
 * @property {number} byteCount This is the exact encoded source size.
 * @property {string} sha256 This is the lowercase source digest.
 */

/**
 * Holds sampling limits shared with the corresponding Swift fixture.
 *
 * @typedef {object} BenchmarkConfiguration
 * @property {number} maximumDurationSeconds This is the longest measured campaign.
 * @property {number} maximumIterations This is the greatest accepted sample count.
 */

/**
 * Holds measured latency percentiles for one JavaScript workload.
 *
 * @typedef {object} BenchmarkResult
 * @property {string} name This is the complete stable workload name.
 * @property {number} p0 This is the minimum latency in microseconds.
 * @property {number} p25 This is the lower-quartile latency in microseconds.
 * @property {number} p50 This is the median latency in microseconds.
 * @property {number} p75 This is the upper-quartile latency in microseconds.
 * @property {number} p90 This is the ninetieth-percentile latency in microseconds.
 * @property {number} p99 This is the ninety-ninth-percentile latency in microseconds.
 * @property {number} p100 This is the maximum latency in microseconds.
 * @property {number} samples This is the measured sample count.
 */

/**
 * Loads the generated manifest and checks its supported identity.
 *
 * @returns {FixtureManifest} The function returns the accepted fixture manifest.
 */
export function loadManifest() {
  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  if (manifest.schemaVersion !== 1) {
    throw new Error(
      `The comparison fixture schema version ${manifest.schemaVersion} is unsupported.`,
    );
  }
  if (manifest.language !== "swift") {
    throw new Error(
      `The comparison fixture language ${manifest.language} is unsupported.`,
    );
  }
  return manifest;
}

/**
 * Loads every shared source and verifies it against the manifest.
 *
 * @returns {ComparisonFixture[]} The function returns the ordered immutable fixture collection.
 */
export function loadFixtures() {
  const manifest = loadManifest();
  return manifest.fixtures.map((entry) => {
    const sourceBuffer = readFileSync(
      resolve(fixtureDirectory, entry.fileName),
    );
    const source = sourceBuffer.toString("utf8");
    const digest = createHash("sha256").update(sourceBuffer).digest("hex");
    const lineCount = source.split("\n").length;
    if (
      sourceBuffer.byteLength !== entry.byteCount ||
      source.length !== entry.utf16Count ||
      source.length < entry.minimumUTF16Length ||
      lineCount !== entry.lineCount ||
      digest !== entry.sha256
    ) {
      throw new Error(
        `The ${entry.name} comparison fixture does not match its manifest.`,
      );
    }

    const markerIndex = source.indexOf(manifest.revisionMarker);
    if (markerIndex < 0) {
      throw new Error(
        `The ${entry.name} comparison fixture has no revision marker.`,
      );
    }
    const editedSource =
      source.slice(0, markerIndex) +
      manifest.replacementMarker +
      source.slice(markerIndex + manifest.revisionMarker.length);
    return Object.freeze({
      name: entry.name,
      source,
      editedSource,
      byteCount: entry.byteCount,
      sha256: entry.sha256,
    });
  });
}

/**
 * Chooses sampling limits that match the Swift benchmark suite.
 *
 * @param {string} fixtureName This is the stable fixture size label.
 * @returns {BenchmarkConfiguration} The function returns the limits for that fixture.
 */
export function configurationFor(fixtureName) {
  switch (fixtureName) {
    case "4KiB":
      return { maximumDurationSeconds: 3, maximumIterations: 100 };
    case "64KiB":
      return { maximumDurationSeconds: 5, maximumIterations: 50 };
    default:
      return { maximumDurationSeconds: 10, maximumIterations: 20 };
  }
}

/**
 * Returns the nearest-rank value for a sorted sample collection.
 *
 * @param {number[]} sortedSamples These samples are ordered from smallest to largest.
 * @param {number} requestedPercentile This is the requested percentile from zero to one hundred.
 * @returns {number} The function returns the selected latency sample.
 */
export function percentile(sortedSamples, requestedPercentile) {
  if (sortedSamples.length === 0) {
    throw new Error("A percentile requires at least one sample.");
  }
  const rank = Math.ceil(
    (requestedPercentile / 100) * sortedSamples.length,
  );
  const index = Math.max(0, rank - 1);
  return sortedSamples[index];
}

/**
 * Runs one warmed duration-bounded JavaScript benchmark.
 *
 * @param {string} name This is the complete stable workload name.
 * @param {BenchmarkConfiguration} configuration This contains the sampling limits.
 * @param {(iteration: number) => number} operation This performs the measured synchronous work.
 * @returns {BenchmarkResult} The function returns the measured latency distribution.
 */
export function runBenchmark(name, configuration, operation) {
  for (let iteration = 0; iteration < warmupIterations; iteration += 1) {
    consumedOutputLength ^= operation(iteration);
  }

  const samples = [];
  const campaignStart = process.hrtime.bigint();
  for (
    let iteration = 0;
    iteration < configuration.maximumIterations;
    iteration += 1
  ) {
    const iterationStart = process.hrtime.bigint();
    consumedOutputLength ^= operation(iteration);
    const iterationEnd = process.hrtime.bigint();
    samples.push(Number(iterationEnd - iterationStart) / 1_000);

    const elapsedSeconds =
      Number(iterationEnd - campaignStart) / 1_000_000_000;
    if (elapsedSeconds >= configuration.maximumDurationSeconds) {
      break;
    }
  }

  const sortedSamples = samples.toSorted((left, right) => left - right);
  return {
    name,
    p0: percentile(sortedSamples, 0),
    p25: percentile(sortedSamples, 25),
    p50: percentile(sortedSamples, 50),
    p75: percentile(sortedSamples, 75),
    p90: percentile(sortedSamples, 90),
    p99: percentile(sortedSamples, 99),
    p100: percentile(sortedSamples, 100),
    samples: sortedSamples.length,
  };
}

/**
 * Parses supported command-line options for filtering and JSON export.
 *
 * @param {string[]} arguments_ These are the command-line arguments after the script path.
 * @returns {{filter: RegExp | null, jsonPath: string | null}} The function returns the requested output behavior.
 */
export function parseArguments(arguments_) {
  let filter = null;
  let jsonPath = null;
  for (let index = 0; index < arguments_.length; index += 1) {
    const argument = arguments_[index];
    if (argument === "--filter") {
      index += 1;
      if (index >= arguments_.length) {
        throw new Error("The --filter option requires a regular expression.");
      }
      filter = new RegExp(arguments_[index]);
      continue;
    }
    if (argument === "--json") {
      index += 1;
      if (index >= arguments_.length) {
        throw new Error("The --json option requires an output path.");
      }
      jsonPath = arguments_[index];
      continue;
    }
    throw new Error(`The option ${argument} is unsupported.`);
  }
  return { filter, jsonPath };
}

/**
 * Formats a microsecond latency without hiding sub-millisecond differences.
 *
 * @param {number} value This is the latency measured in microseconds.
 * @returns {string} The function returns a fixed-width decimal representation.
 */
function formatLatency(value) {
  return value.toFixed(0);
}

/**
 * Prints results as a Markdown table suitable for logs and reports.
 *
 * @param {BenchmarkResult[]} results These are the completed benchmark results.
 */
function printResults(results) {
  const processor = cpus()[0]?.model ?? "Unknown processor";
  console.log(
    `highlight.js ${hljs.versionString} on Node ${process.version}`,
  );
  console.log(`${platform()} ${arch()}`);
  console.log(`${processor} with ${Math.round(totalmem() / 2 ** 30)} GiB RAM`);
  console.log("");
  console.log(
    "| Benchmark | p0 | p25 | p50 | p75 | p90 | p99 | p100 | Samples |",
  );
  console.log(
    "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
  );
  for (const result of results) {
    console.log(
      `| ${result.name} | ${formatLatency(result.p0)} | ${formatLatency(result.p25)} | ${formatLatency(result.p50)} | ${formatLatency(result.p75)} | ${formatLatency(result.p90)} | ${formatLatency(result.p99)} | ${formatLatency(result.p100)} | ${result.samples} |`,
    );
  }
  console.log("");
  console.log("All latency values are microseconds.");
}

/**
 * Writes structured results when automation requests a JSON artifact.
 *
 * @param {string} outputPath This is the requested output path.
 * @param {BenchmarkResult[]} results These are the completed benchmark results.
 * @param {ComparisonFixture[]} fixtures These are the verified shared fixtures.
 */
function writeJSONResults(outputPath, results, fixtures) {
  const absolutePath = resolve(outputPath);
  mkdirSync(dirname(absolutePath), { recursive: true });
  writeFileSync(
    absolutePath,
    `${JSON.stringify(
      {
        runtime: process.version,
        highlightJSVersion: hljs.versionString,
        platform: platform(),
        architecture: arch(),
        fixtureDirectory,
        fixtures: fixtures.map((fixture) => ({
          name: fixture.name,
          byteCount: fixture.byteCount,
          sha256: fixture.sha256,
        })),
        results,
      },
      null,
      2,
    )}\n`,
  );
}

/**
 * Runs every requested highlight.js workload against the shared corpus.
 */
function main() {
  const options = parseArguments(process.argv.slice(2));
  const fixtures = loadFixtures();
  const results = [];
  for (const fixture of fixtures) {
    const name = `HTMLEndToEnd/HighlightJS/${fixture.name}`;
    if (options.filter === null || options.filter.test(name)) {
      const control = hljs.highlight(fixture.source, {
        language: "swift",
        ignoreIllegals: true,
      });
      if (control.value.length === 0) {
        throw new Error(`Highlight.js rejected the ${fixture.name} fixture.`);
      }
      results.push(
        runBenchmark(name, configurationFor(fixture.name), () => {
          const result = hljs.highlight(fixture.source, {
            language: "swift",
            ignoreIllegals: true,
          });
          return result.value.length;
        }),
      );
    }
  }

  const editFixture = fixtures.at(-1);
  if (editFixture === undefined) {
    throw new Error("The comparison fixture collection is empty.");
  }
  const editName = `EditorEdit/HighlightJSFullPass/${editFixture.name}`;
  if (options.filter === null || options.filter.test(editName)) {
    results.push(
      runBenchmark(editName, configurationFor(editFixture.name), (iteration) => {
        const source =
          iteration % 2 === 0
            ? editFixture.editedSource
            : editFixture.source;
        const result = hljs.highlight(source, {
          language: "swift",
          ignoreIllegals: true,
        });
        return result.value.length;
      }),
    );
  }

  printResults(results);
  if (options.jsonPath !== null) {
    writeJSONResults(options.jsonPath, results, fixtures);
  }
  if (consumedOutputLength === Number.MIN_SAFE_INTEGER) {
    throw new Error("The benchmark output consumer entered an invalid state.");
  }
}

/**
 * The direct-execution guard keeps imports side-effect free for tests.
 */
const isDirectExecution =
  process.argv[1] !== undefined &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url);

if (isDirectExecution) {
  main();
}
