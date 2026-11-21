import { execFileSync } from "node:child_process";
import { cpSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

const jar = process.env.TLA2TOOLS;
if (jar === undefined || jar === "") {
  throw new Error("Set TLA2TOOLS to the path of the TLC v1.7.4 jar.");
}

const model = path.resolve(import.meta.dirname, "../../assets/node-textfile");
const root = path.resolve(import.meta.dirname, "../../../../..");
const scratch = mkdtempSync(path.join(tmpdir(), "node-textfile-"));
const holdMinutes = 5;
const samplesPerHistory = holdMinutes + 2;
const evaluationInterval = "1m";
const alert = "NodeTextFileCollectorScrapeError";
const firing = `count by (job, instance) (ALERTS{alertname="${alert}",alertstate="firing"})`;
const expected = [
  { labels: '{instance="fixture",job="node-exporter"}', value: 1 }
];

try {
  const scratchModel = path.join(scratch, "model");
  cpSync(model, scratchModel, { recursive: true });
  const output = path.join(scratch, "rendered");
  mkdirSync(output);
  execFileSync(
    "java",
    [
      "-XX:+UseParallelGC",
      `-Djava.io.tmpdir=${scratch}`,
      "-cp",
      path.resolve(jar),
      "tlc2.TLC",
      "-workers",
      "1",
      "-metadir",
      path.join(scratch, "states"),
      "-config",
      "NodeTextfile.cfg",
      "NodeTextfile.tla"
    ],
    { cwd: scratchModel, stdio: "inherit" }
  );

  execFileSync("go", ["tool", "task", "generate", `OUTPUT_DIR=${output}`], {
    cwd: root,
    stdio: "inherit"
  });

  const renderedInterval = execFileSync(
    "go",
    [
      "tool",
      "jsonnet",
      "-S",
      "-J",
      output,
      "-e",
      `local groups = std.parseYaml(importstr "prometheus-rules.yaml").groups;
      [group.interval for group in groups for rule in group.rules if std.get(rule, "alert") == "${alert}"][0]`
    ],
    { cwd: root, encoding: "utf-8" }
  ).trim();
  if (renderedInterval !== evaluationInterval) {
    throw new Error(
      `Expected ${evaluationInterval} rule interval, got ${renderedInterval}.`
    );
  }

  const tests = [];
  const always = `1x${samplesPerHistory - 1}`;
  const requiredStreak = "1".repeat(holdMinutes + 1);
  for (let pattern = 0; pattern < 2 ** samplesPerHistory; pattern += 1) {
    const history = pattern.toString(2).padStart(samplesPerHistory, "0");
    const series = Array.from({ length: samplesPerHistory }, (_, minute) =>
      history.charAt(minute)
    ).join(" ");
    const assertions = Array.from(
      { length: samplesPerHistory },
      (_, minute) => ({
        eval_time: `${minute}m`,
        exp_samples: history.slice(0, minute + 1).endsWith(requiredStreak)
          ? expected
          : [],
        expr: firing
      })
    );

    for (const [cause, up, collector] of [
      ["reachability", series, always],
      ["collector error", always, series]
    ]) {
      tests.push({
        input_series: [
          { series: 'up{job="node-exporter",instance="fixture"}', values: up },
          {
            series:
              'node_textfile_scrape_error{job="node-exporter",instance="fixture"}',
            values: collector
          },
          { series: 'up{job="node-exporter",instance="other"}', values: always }
        ],
        interval: evaluationInterval,
        name: `${cause} ${history}`,
        promql_expr_test: assertions
      });
    }
  }

  const fixture = path.join(scratch, "node-textfile.json");
  writeFileSync(
    fixture,
    JSON.stringify({
      evaluation_interval: evaluationInterval,
      rule_files: [path.join(output, "prometheus-rules.yaml")],
      tests
    })
  );
  execFileSync("go", ["tool", "promtool", "test", "rules", fixture], {
    cwd: root,
    stdio: "inherit"
  });
} finally {
  rmSync(scratch, { force: true, recursive: true });
}
