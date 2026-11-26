import { execFileSync } from "node:child_process";
import { basename, dirname, extname, join } from "node:path/posix";
import { argv, stderr } from "node:process";

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
const paths = execFileSync(
  "git",
  commit === undefined
    ? ["ls-files", "-z"]
    : ["ls-tree", "-r", "-z", "--name-only", commit],
  gitOptions
)
  .split("\0")
  .filter(Boolean);
const readSource = (file: string): string =>
  execFileSync("git", ["show", `${commit ?? ""}:${file}`], gitOptions);
const inSkill = (file: string): boolean => file.startsWith(`${root}/`);
const models = paths.filter((file) => extname(file) === ".tla");
const modelDirectories = new Set(models.map((file) => dirname(file)));
const modelNames = new Set(models.map((file) => basename(file, ".tla")));
const associatedWithModel = (file: string): boolean =>
  modelDirectories.has(dirname(file)) ||
  modelNames.has(basename(file, extname(file)));
const chartExtensions = new Set([".mmd", ".mnd"]);
const frontMatter =
  /^(?:\uFEFF)?---[ \t]*\r?\n(?<fields>[\s\S]*?)\r?\n(?:---|\.\.\.)[ \t]*(?:\r?\n|$)/u;
const titleField =
  /^(?:title|"title"|'title')[ \t]*:[ \t]*(?:"(?<double>[^"\r\n]*)"|'(?<single>[^'\r\n]*)'|(?<plain>[^#\r\n]*?))[ \t]*(?:#[^\r\n]*)?\r?$/mu;
const formalCharts = new Set(
  paths.filter((file) => {
    if (!chartExtensions.has(extname(file))) {
      return false;
    }
    if (inSkill(file) || associatedWithModel(file)) {
      return true;
    }
    const fields = frontMatter.exec(readSource(file))?.groups?.fields;
    const title =
      fields === undefined ? undefined : titleField.exec(fields)?.groups;
    const value = title?.double ?? title?.single ?? title?.plain;
    return value !== undefined && modelNames.has(value);
  })
);
const scriptExtensions = new Set([
  ".ts",
  ".js",
  ".mjs",
  ".mts",
  ".cjs",
  ".cts",
  ".sh",
  ".py"
]);
const tlcTool =
  /(?<![\w.-])(?:tlc2\.TLC|tla2tools(?:-[\w.-]+)?\.jar)(?![\w.-])/u;
const peleImport =
  /^\s*import\b(?:[^"'();]*?\bfrom)?\s*(?<quote>["'])pele\k<quote>/mu;
const peleImportCall =
  /(?<![\w$.])(?:import|require)\s*\(\s*(?<quote>["'])pele\k<quote>\s*\)/u;
const modelFileCall =
  /\b(?:URL|readFile(?:Sync)?|open(?:Sync)?)\s*\(\s*(?<quote>["'`])[^"'`\r\n]+\.tla\k<quote>/u;
const modelReference =
  /(?<quote>["'`])(?<literal>[^"'`\r\n]+\.tla)\k<quote>|(?<![\w./-])(?<token>[\w./-]+\.tla)(?![\w./-])/gu;
const hasFormalSource = (source: string): boolean => {
  if (
    tlcTool.test(source) ||
    peleImport.test(source) ||
    peleImportCall.test(source) ||
    modelFileCall.test(source)
  ) {
    return true;
  }
  for (const { groups } of source.matchAll(modelReference)) {
    const reference = groups?.literal ?? groups?.token;
    if (
      reference !== undefined &&
      (reference.includes("/") || modelNames.has(basename(reference, ".tla")))
    ) {
      return true;
    }
  }
  return false;
};

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
        chartExtensions
          .values()
          .some((chartExtension) =>
            formalCharts.has(join(directory, `${name}${chartExtension}`))
          )))
  ) {
    if (!references.test(directory) || extension === ".mnd") {
      report(
        path,
        `${root}/references/<model>/${name}${extension === ".mnd" ? ".mmd" : extension}`
      );
    }
  } else if (
    scriptExtensions.has(extension) &&
    (!scripts.test(directory) || extension !== ".ts") &&
    (inside || hasFormalSource(readSource(path)))
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
