import { execFileSync, spawnSync } from "node:child_process";
import { basename, dirname, extname, isAbsolute } from "node:path/posix";
import { argv, stderr } from "node:process";

import { isAlias, isScalar, parseDocument } from "yaml";

const root = ".claude/skills/formal-verification";
const modelName = "[a-z0-9]+(?:-[a-z0-9]+)*";
const assets = new RegExp(
  `^${root.replaceAll(".", "\\.")}/assets/${modelName}$`,
  "u"
);
const references = new RegExp(
  `^${root.replaceAll(".", "\\.")}/references/${modelName}$`,
  "u"
);
const scripts = new RegExp(
  `^${root.replaceAll(".", "\\.")}/scripts(?:/${modelName})?$`,
  "u"
);
const [commit] = argv.slice(2);
const gitOptions = {
  cwd: new URL("../../../../", import.meta.url),
  encoding: "utf-8" as const
};
const modes = new Map<string, string>();
const records = execFileSync(
  "git",
  commit === undefined
    ? ["ls-files", "--stage", "-z"]
    : ["ls-tree", "-r", "-z", commit],
  gitOptions
);
for (const { groups } of records.matchAll(
  /(?<mode>[0-7]{6}) [^\t\0]+\t(?<file>[^\0]+)\0/gu
)) {
  if (groups?.mode !== undefined && groups.file !== undefined) {
    modes.set(groups.file, groups.mode);
  }
}
const paths = [...modes.keys()];
const readSource = (file: string): string =>
  execFileSync("git", ["show", `${commit ?? ""}:${file}`], gitOptions);

const directories = new Set(["."]);
for (const file of paths) {
  let directory = dirname(file);
  while (!directories.has(directory)) {
    directories.add(directory);
    directory = dirname(directory);
  }
}

const isRegular = (file: string): boolean => {
  const mode = modes.get(file);
  return mode === "100644" || mode === "100755";
};

const scriptSource = (file: string): string | undefined => {
  if (modes.get(file) !== "120000") {
    return isRegular(file) ? file : undefined;
  }
  const target = readSource(file);
  if (target === "" || isAbsolute(target) || target.includes("\0")) {
    return undefined;
  }
  const parent = dirname(file);
  const resolved = parent === "." ? [] : parent.split("/");
  const parts = target.split("/");
  for (const [index, part] of parts.entries()) {
    if (part === "..") {
      if (resolved.pop() === undefined) {
        return undefined;
      }
    } else if (part.toLowerCase() === ".git") {
      return undefined;
    } else if (part !== "" && part !== ".") {
      resolved.push(part);
      if (index < parts.length - 1 && !directories.has(resolved.join("/"))) {
        return undefined;
      }
    }
  }
  const path = resolved.join("/");
  return isRegular(path) ? path : undefined;
};
const inSkill = (file: string): boolean => file.startsWith(`${root}/`);
const models = paths.filter((file) => extname(file) === ".tla");
const modelDirectories = new Set(models.map((file) => dirname(file)));
const normalizeName = (name: string): string =>
  name.toLowerCase().replaceAll(/[-_]/gu, "");
const normalizedStem = (file: string): string =>
  normalizeName(basename(file, extname(file)));
const normalizedModelNames = new Set(models.map(normalizedStem));
const associatedWithModel = (file: string): boolean =>
  modelDirectories.has(dirname(file)) ||
  normalizedModelNames.has(normalizedStem(file));
const chartExtensions = new Set([".mmd", ".mnd"]);
const frontMatter =
  /^(?:\uFEFF)?---[ \t]*\r?\n(?<fields>[\s\S]*?)(?<=\n)(?:---|\.\.\.)[ \t]*(?:\r?\n|$)/u;
const chartTitle = (source: string): string | undefined => {
  const fields = frontMatter.exec(source)?.groups?.fields;
  if (fields === undefined) {
    return undefined;
  }
  const document = parseDocument(fields);
  if (document.errors.length > 0) {
    return undefined;
  }
  const title = document.get("title", true);
  const resolved = isAlias(title) ? title.resolve(document) : title;
  return isScalar(resolved) && typeof resolved.value === "string"
    ? resolved.value
    : undefined;
};
const formalCharts = new Set(
  paths.filter((file) => {
    if (!chartExtensions.has(extname(file))) {
      return false;
    }
    if (inSkill(file) || associatedWithModel(file)) {
      return true;
    }
    const title = chartTitle(readSource(file));
    return (
      title !== undefined && normalizedModelNames.has(normalizeName(title))
    );
  })
);
const chartKey = (file: string): string =>
  `${dirname(file)}/${normalizedStem(file)}`;
const formalChartKeys = new Set([...formalCharts].map(chartKey));
const scriptExtensions = new Set([
  ".sh",
  ".bash",
  ".zsh",
  ".ksh",
  ".fish",
  ".py",
  ".rb",
  ".pl",
  ".php",
  ".lua",
  ".ps1",
  ".bat",
  ".cmd",
  ".r",
  ".jl",
  ".kts",
  ".gradle",
  ".groovy",
  ".js",
  ".mjs",
  ".cjs",
  ".jsx",
  ".ts",
  ".mts",
  ".cts",
  ".tsx"
]);
const shebangPaths = (): Set<string> => {
  // Limit each blob's output to a line number and the two matched bytes.
  const result = spawnSync(
    "git",
    [
      "grep",
      "--no-color",
      "--no-heading",
      "--no-break",
      "--no-column",
      "--no-textconv",
      "--text",
      "--basic-regexp",
      "--line-number",
      "--null",
      "--only-matching",
      "--max-count=1",
      "-e",
      "^#!",
      commit ?? "--cached",
      "--"
    ],
    gitOptions
  );
  if (result.error !== undefined) {
    throw result.error;
  }
  if (result.status !== 0 && result.status !== 1) {
    throw new Error(`git grep could not check shebangs: ${result.stderr}`);
  }
  const prefixLength = commit === undefined ? 0 : commit.length + 1;
  const firstLines = new Set<string>();
  for (const { groups } of result.stdout.matchAll(
    /(?<file>[^\0]+)\0(?<line>\d+)\0#!\n/gu
  )) {
    if (groups?.line === "1" && groups.file !== undefined) {
      firstLines.add(groups.file.slice(prefixLength));
    }
  }
  return firstLines;
};
const scriptsWithShebang = shebangPaths();
const tlcTool =
  /(?<![\w.-])(?:tlc2\.TLC|tla2tools(?:-[\w.-]+)?\.jar)(?![\w.-])/u;
const peleImport =
  /^\s*import\b(?:[^"'();]*?\bfrom)?\s*(?<quote>["'])pele\k<quote>/mu;
const peleImportCall =
  /(?<![\w$.])(?:import|require)\s*\(\s*(?<quote>["'`])pele\k<quote>\s*\)/u;
const modelReference =
  /(?<quote>["'`])(?<literal>[^"'`\r\n]+\.tla)\k<quote>|(?<![\w./-])(?<token>[\w./-]+\.tla)(?![\w./-])/gu;
const hasFormalSource = (source: string): boolean =>
  tlcTool.test(source) ||
  peleImport.test(source) ||
  peleImportCall.test(source) ||
  source.matchAll(modelReference).some(({ groups }) => {
    const reference = groups?.literal ?? groups?.token;
    return (
      reference !== undefined &&
      (reference.includes("/") ||
        normalizedModelNames.has(normalizedStem(reference)))
    );
  });

let invalid = false;
const report = (path: string, expected: string): void => {
  stderr.write(`${path}: expected ${expected}\n`);
  invalid = true;
};

for (const path of paths) {
  const directory = dirname(path);
  const extension = extname(path);
  const name = basename(path, extension);
  const inside = inSkill(path);
  const source = scriptSource(path);
  if (
    extension === ".tla" ||
    (extension === ".cfg" && (inside || associatedWithModel(path)))
  ) {
    if (!assets.test(directory)) {
      report(path, `${root}/assets/<model>/${basename(path)}`);
    }
  } else if (
    formalCharts.has(path) ||
    (extension === ".svg" &&
      (inside ||
        modelDirectories.has(directory) ||
        formalChartKeys.has(chartKey(path))))
  ) {
    if (!references.test(directory) || extension === ".mnd") {
      report(
        path,
        `${root}/references/<model>/${name}${extension === ".mnd" ? ".mmd" : extension}`
      );
    }
  } else if (
    (scriptExtensions.has(extension) ||
      (source !== undefined && scriptsWithShebang.has(source))) &&
    (!scripts.test(directory) || extension !== ".ts") &&
    (inside || (source !== undefined && hasFormalSource(readSource(source))))
  ) {
    report(
      path,
      `${root}/scripts/${name}.ts or ${root}/scripts/<model>/${name}.ts`
    );
  }
}

if (invalid) {
  process.exitCode = 1;
}
