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
import { argv, env, execPath } from "node:process";
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
const fixtureEnv = { ...env };
delete fixtureEnv.GIT_DIR;
delete fixtureEnv.GIT_WORK_TREE;
delete fixtureEnv.GIT_INDEX_FILE;
delete fixtureEnv.GIT_OBJECT_DIRECTORY;
delete fixtureEnv.GIT_ALTERNATE_OBJECT_DIRECTORIES;
delete fixtureEnv.GIT_COMMON_DIR;
const fixtureOptions = (cwd: string) => ({
  cwd,
  encoding: "utf-8" as const,
  env: fixtureEnv
});
const fixtureGit = (cwd: string, ...args: string[]): string =>
  execFileSync("git", args, fixtureOptions(cwd));
const checkerSource =
  checkerRef === undefined
    ? readFileSync(new URL("check-layout.ts", import.meta.url), "utf-8")
    : execFileSync("git", ["show", `${checkerRef}:${checker}`], {
        cwd: new URL("../../../../", import.meta.url),
        encoding: "utf-8"
      });
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
const environmentCase = "isolated-git-environment";
assert.ok(
  selectedCases.length > 0 || selectedCase === environmentCase,
  `Unknown fixture: ${selectedCase}`
);

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
    fixtureGit(cwd, "init", "--quiet");
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
    fixtureGit(cwd, "add", "--", modelDirectory, file);
    const tree = fixtureGit(cwd, "write-tree").trim();
    const indexed = spawnSync(execPath, [checker], fixtureOptions(cwd));
    fixtureGit(cwd, "read-tree", "--empty");
    const fromTree = spawnSync(execPath, [checker, tree], fixtureOptions(cwd));
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

if (selectedCase === undefined || selectedCase === environmentCase) {
  void test(environmentCase, (context) => {
    const cwd = mkdtempSync(path.join(tmpdir(), "observability-git-sentinel-"));
    context.after(() => {
      rmSync(cwd, { force: true, recursive: true });
    });
    fixtureGit(cwd, "init", "--quiet");
    writeFileSync(path.join(cwd, "sentinel.txt"), "Keep this staged.\n");
    fixtureGit(cwd, "add", "--", "sentinel.txt");
    const gitDir = path.join(cwd, ".git");
    const index = path.join(gitDir, "index");
    const config = path.join(gitDir, "config");
    const indexBefore = readFileSync(index);
    const configBefore = readFileSync(config);
    const bareBefore = fixtureGit(
      cwd,
      "config",
      "--local",
      "--get",
      "core.bare"
    ).trim();
    const result = spawnSync(execPath, [import.meta.filename, "node-shebang"], {
      ...fixtureOptions(cwd),
      env: {
        ...fixtureEnv,
        GIT_DIR: gitDir,
        GIT_WORK_TREE: cwd,
        GIT_INDEX_FILE: index,
        GIT_OBJECT_DIRECTORY: path.join(gitDir, "objects"),
        GIT_ALTERNATE_OBJECT_DIRECTORIES: path.join(gitDir, "alternates"),
        GIT_COMMON_DIR: gitDir
      }
    });
    const bareAfter = fixtureGit(
      cwd,
      "config",
      "--local",
      "--get",
      "core.bare"
    ).trim();
    context.diagnostic(`sentinel core.bare: ${bareBefore} -> ${bareAfter}`);
    assert.equal(bareBefore, "false");
    assert.equal(bareAfter, "false");
    assert.deepEqual(readFileSync(config), configBefore);
    assert.deepEqual(readFileSync(index), indexBefore);
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stdout + result.stderr);
  });
}
