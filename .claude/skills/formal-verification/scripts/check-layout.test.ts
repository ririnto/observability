import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  symlinkSync,
  writeFileSync
} from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { argv, execPath } from "node:process";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

const skill = ".claude/skills/formal-verification";
const checker = `${skill}/scripts/check-layout.ts`;
const {
  positionals: [selectedCase],
  values: { "checker-ref": checkerRef }
} = parseArgs({
  args: argv.slice(2),
  allowPositionals: true,
  options: { "checker-ref": { type: "string" } }
});
const git = (cwd: string, ...args: string[]): string =>
  execFileSync("git", args, { cwd, encoding: "utf-8" });
const checkerSource =
  checkerRef === undefined
    ? readFileSync(new URL("check-layout.ts", import.meta.url), "utf-8")
    : git(
        fileURLToPath(new URL("../../../../", import.meta.url)),
        "show",
        `${checkerRef}:${checker}`
      );
const cases = [
  {
    name: "normalized-model",
    path: "probe.ts",
    source: 'export const model = "foo-bar.tla";\n',
    status: 1
  },
  {
    name: "unmatched-model",
    path: "probe.ts",
    source: 'export const model = "other.tla";\n',
    status: 0
  },
  {
    name: "node-shebang",
    path: "probe",
    source: '#!/usr/bin/env node\nconsole.log("Foo_Bar.tla");\n',
    status: 1
  },
  {
    name: "pele-import",
    path: "probe.mjs",
    source: 'import { render } from "pele";\n',
    status: 1
  },
  {
    name: "ruby-script",
    path: "probe.rb",
    source: 'puts "Foo_Bar.tla"\n',
    status: 1
  },
  {
    name: "neutral-mjs",
    path: "neutral.mjs",
    source: 'export const label = "everyday";\n',
    status: 0
  },
  {
    name: "markdown-note",
    path: "note.md",
    source: "See `Foo_Bar.tla`.\n",
    status: 0
  },
  {
    name: "large-config",
    path: "settings.conf",
    source: `model = "Foo_Bar.tla"\n#!${"x".repeat(2 * 1024 * 1024)}\n`,
    status: 0
  }
];

const selectedCases =
  selectedCase === undefined
    ? cases
    : cases.filter(({ name }) => name === selectedCase);
assert.ok(selectedCases.length > 0, `Unknown fixture: ${selectedCase}`);

for (const {
  name,
  path: file,
  source,
  status: expectedStatus
} of selectedCases) {
  void test(name, (context) => {
    const cwd = mkdtempSync(path.join(tmpdir(), "observability-layout-"));
    context.after(() => {
      rmSync(cwd, { force: true, recursive: true });
    });
    const modelDirectory = `${skill}/assets/foo-bar`;
    git(cwd, "init", "--quiet");
    mkdirSync(path.join(cwd, modelDirectory), { recursive: true });
    mkdirSync(path.join(cwd, skill, "scripts"), { recursive: true });
    symlinkSync(
      fileURLToPath(new URL("../node_modules", import.meta.url)),
      path.join(cwd, skill, "node_modules"),
      "junction"
    );
    writeFileSync(path.join(cwd, checker), checkerSource);
    writeFileSync(
      path.join(cwd, modelDirectory, "Foo_Bar.tla"),
      "---- MODULE Foo_Bar ----\n====\n"
    );
    writeFileSync(path.join(cwd, file), source);
    git(cwd, "add", "--", modelDirectory, file);
    const tree = git(cwd, "write-tree").trim();
    const indexed = spawnSync(execPath, [checker], { cwd, encoding: "utf-8" });
    git(cwd, "read-tree", "--empty");
    const fromTree = spawnSync(execPath, [checker, tree], {
      cwd,
      encoding: "utf-8"
    });
    const scriptName = `${path.basename(file, path.extname(file))}.ts`;
    const expectedDiagnostic =
      expectedStatus === 0
        ? ""
        : `${file}: expected ${skill}/scripts/${scriptName} or ${skill}/scripts/<model>/${scriptName}\n`;
    context.diagnostic(
      `checker exit status: index=${indexed.status}, tree=${fromTree.status}`
    );
    for (const result of [indexed, fromTree]) {
      assert.ifError(result.error);
      assert.equal(result.status, expectedStatus);
      assert.equal(result.stderr, expectedDiagnostic);
    }
  });
}
