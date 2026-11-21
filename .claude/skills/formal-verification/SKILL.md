---
name: formal-verification
description: Check the Node Exporter textfile error alert when changing its PromQL, firing delay, or evaluation interval.
---

# Formal verification

Use the [Node Exporter textfile alert check](references/node-textfile/README.md) when you change the alert's condition or timing.
The check runs the TLA+ model and replays bounded histories against the current generated Prometheus rules.

Read the source mapping and assumptions before editing the model.
Run pstack's `statechart` skill on the model to inspect any counterexample or draw the passing state graph.
Replay a counterexample with the real rule before deciding whether to fix the implementation or update the model.

The source mapping was verified at `1d4c2b9252bb9c4cfdad16b08e37e3b6d72fdf04`.
Update that commit after you compare the covered source, run the check, and confirm the model matches the new behavior.
