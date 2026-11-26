import { execFileSync, spawnSync } from "node:child_process";
import { basename, dirname, extname } from "node:path/posix";
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
const paths = new Set(
  execFileSync(
    "git",
    commit === undefined
      ? ["ls-files", "-z"]
      : ["ls-tree", "-r", "-z", "--name-only", commit],
    gitOptions
  )
    .split("\0")
    .filter(Boolean)
);
const scriptExtensions = [
  ".ts",
  ".js",
  ".mjs",
  ".mts",
  ".cjs",
  ".cts",
  ".sh",
  ".py"
];
const formalToolPatterns = [
  "[\"']tlc2[.]TLC[\"']|require[.]resolve[(][[:blank:]]*[\"'][^\"']*tla2tools[.]jar[\"']",
  "^[[:blank:]]*import[[:blank:]]+[{][[:blank:]]*render([[:blank:]]+as[[:blank:]]+[$_[:alnum:]]+)?[[:blank:]]*[}][[:blank:]]+from[[:blank:]]+[\"']pele[\"']"
];
const matches = spawnSync(
  "git",
  [
    "grep",
    "-IlzE",
    ...formalToolPatterns.flatMap((pattern) => ["-e", pattern]),
    commit ?? "--cached",
    "--",
    ...scriptExtensions.map((extension) => `*${extension}`),
    `:(exclude,glob)${root}/**`
  ],
  gitOptions
);
if (matches.error || (matches.status !== 0 && matches.status !== 1)) {
  throw matches.error ?? new Error(matches.stderr.trim() || "git grep failed");
}
const formalScripts = new Set(
  matches.stdout
    .split("\0")
    .filter(Boolean)
    .map((file) =>
      commit === undefined ? file : file.slice(commit.length + 1)
    )
);

let invalid = false;
const report = (path: string, expected: string): void => {
  stderr.write(`${path}: expected ${expected}\n`);
  invalid = true;
};

for (const path of paths) {
  const directory = dirname(path);
  const extension = extname(path);
  const name = basename(path, extension);
  const formal =
    path.startsWith(`${root}/`) ||
    path.startsWith("verification/") ||
    (path.startsWith(".claude/skills/verify-") && path.includes("/model/"));
  if (extension === ".tla" || extension === ".cfg") {
    if (!assets.test(directory)) {
      report(path, `${root}/assets/<model>/${basename(path)}`);
    }
  } else if (
    extension === ".mmd" ||
    extension === ".mnd" ||
    (extension === ".svg" &&
      (formal ||
        name === "statechart" ||
        paths.has(`${directory}/${name}.mmd`)))
  ) {
    if (!references.test(directory) || extension === ".mnd") {
      report(
        path,
        `${root}/references/<model>/${name}${extension === ".mnd" ? ".mmd" : extension}`
      );
    }
  } else if (
    scriptExtensions.includes(extension) &&
    (formal || name.includes("statechart") || formalScripts.has(path)) &&
    (!scripts.test(directory) || extension !== ".ts")
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
