# Node Exporter textfile alert

`NodeTextFileCollectorScrapeError` fires when Prometheus observes a reachable Node Exporter with a textfile collector error from the first qualifying evaluation through five elapsed minutes.
An ineligible evaluation clears a firing alert and resets a pending alert.
An alert that fires for an unreachable exporter sends the operator to investigate a collector error during a scrape outage.

## Run the check

Install the repository dependencies with `pnpm install --frozen-lockfile`.
Install Java.
Download `tla2tools.jar` from the [TLA+ v1.7.4 release](https://github.com/tlaplus/tlaplus/releases/tag/v1.7.4).
The jar has SHA-256 `936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88`.
Set `TLA2TOOLS` to the jar's path and run this command from the repository root.

```sh
node .claude/skills/formal-verification/scripts/node-textfile/check.ts
```

TLC checks the model's invariants.
The same command regenerates the rules in a temporary directory and checks the declared group interval.
It runs the repository's `promtool` against the generated rules at that interval.

## Source mapping

| Model | Source |
| --- | --- |
| Eligible evaluation | [`nodeTextfileError` and `nodeReachable`](../../../../../mixins/targets.libsonnet) require the error metric to equal 1 and the same `job` and `instance` to be reachable. |
| Six eligible evaluations | [`NodeTextFileCollectorScrapeError`](../../../../../mixins/alerts.libsonnet) uses a five-minute delay and a one-minute rule interval. The first evaluation starts the timer at minute zero. |
| Clear or reset | [Prometheus rule tests](../../../../../tests/prometheus/rules.yaml) exercise the firing result when a collector recovers or an exporter is unreachable. The replay reads the `ALERTS` series after each evaluation. |

The [model](../../assets/node-textfile/NodeTextfile.tla) compares a saturating counter to a window of the six most recent eligibility values.
TLC checks every reachable combination of counter and window for unbounded sequences of one-minute evaluations.
The replay checks all seven-tick binary histories twice, once varying reachability and once varying the collector error.
Each replay includes another reachable instance to exercise matching by instance.
Both replays use samples at each evaluation.
Scrape jitter, missing samples, and Alertmanager delivery are outside the check.

## Check a counterexample

To test the invariant in a scratch model, replace the streak reset in `Ineligible` with `streak' = streak`.
TLC finds a history where the counter reaches six despite an ineligible evaluation in the last six ticks.
To test the replay in a scratch checkout, remove the `nodeReachable` conjunct from `nodeTextfileError` in `mixins/targets.libsonnet` and run the check.
TLC passes the model, and `promtool` reports an alert firing while the exporter is unreachable.
Restore the conjunct and rerun the check.

## Regenerate the statechart

Set `STATECHART` to the path of `scripts/statechart` in pstack 0.15.46's `statechart` skill.
With `TLA2TOOLS` still set, run these commands from the repository root.

```sh
model=.claude/skills/formal-verification/assets/node-textfile
out="$(mktemp -d)"
"$STATECHART" "$model/NodeTextfile.tla" \
  --config "$model/NodeTextfile.cfg" \
  --view .claude/skills/formal-verification/scripts/node-textfile/view.ts \
  --out "$out"
diff -u "$model/statechart.mmd" "$out/chart.mmd"
```

After a model or view change, inspect `report.md` in the output directory before copying `chart.mmd` over the [committed statechart](../../assets/node-textfile/statechart.mmd).
The chart hides evaluations that stay in the same display state.
