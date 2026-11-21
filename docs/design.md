# Design and validation

## Mixins

The Jsonnet mixin keeps metric queries, dashboard layout, and rule ownership in source files.
It emits plain configuration for Prometheus, Grafana, and Alertmanager.

- [Monitoring Mixins](https://monitoring.mixins.dev/) defines the Jsonnet bundle pattern for dashboards and rules.
- [kube-prometheus](https://github.com/prometheus-operator/kube-prometheus) demonstrates composing monitoring modules and rendering deployable configuration.
  This repository renders standalone files for the target binaries.
- [Awesome Prometheus Alerts](https://github.com/samber/awesome-prometheus-alerts) demonstrates covering exporter reachability and application health independently.
  The expressions and annotations here are written for the target contracts in this repository.
  The reference collection documents its [dual license](https://github.com/samber/awesome-prometheus-alerts/blob/master/LICENSE).

- The [upstream Node Exporter mixin](https://github.com/prometheus/node_exporter/blob/v1.13.1/docs/node-mixin/alerts/alerts.libsonnet) supplies the textfile error signal.
  This repository scopes it to the `node-exporter` job, checks that Prometheus reached the exporter, and waits five minutes before firing.

## Configuration contracts

- [Prometheus rule tests](https://github.com/prometheus/prometheus/blob/main/docs/configuration/unit_testing_rules.md) and [promtool commands](https://github.com/prometheus/prometheus/blob/main/docs/command-line/promtool.md) define the native rule checks.
- [Alertmanager configuration](https://github.com/prometheus/alertmanager/blob/main/docs/configuration.md) defines receiver and grouping behavior.
- Grafana's [V2 dashboard specification](https://github.com/grafana/grafana/blob/main/apps/dashboard/kinds/v2/dashboard_spec.cue) defines the resource's panel, query, and layout shape.
  The checker uses the same Grafana release as the local import fixture.
- Grafana's [alert provisioning implementation](https://github.com/grafana/grafana/blob/main/pkg/services/provisioning/alerting/rules_types.go) defines rule group, query, and no-data fields.
- Grafana Core provides guidance for three parts of the configuration.
  - [PromQL](https://github.com/grafana/skills/tree/main/skills/grafana-core/promql) covers query windows.
  - [Alerting and IRM](https://github.com/grafana/skills/tree/main/skills/grafana-core/alerting-irm) covers annotations.
  - [Dashboarding](https://github.com/grafana/skills/tree/main/skills/grafana-core/dashboarding) covers panel form and import verification.

## Visualization

A stat tile shows the current number of configured scrape targets reporting a failure.
A table identifies the target and an adjacent table gives each trend's current values.
Time-series panels use thin, unfilled lines, hover values, and native Grafana theme text.
The two-series panel lists HTTP before Stream, with a fixed blue and orange palette and a visible legend.
Each chart uses one quantity and one axis.
The two Node Exporter trends each use one blue series and a table of current values.

The blue and orange strokes have a minimum simulated CIEDE2000 distance of 49.99 at full severity across protan, deutan, and tritan simulations.
The adjacent table lists both protocols and their current counts.
The two line colors have at least 3.33:1 contrast against the tested white and dark-gray backgrounds.
The plot has no filled areas or bar ends.

The local Grafana import was queried through Prometheus using synthetic HTTP and stream health samples.
Grafana rendered the legend and returned one failed HTTP probe and zero failed stream probes in the table.
