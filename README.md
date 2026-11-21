# Observability configuration

This repository generates Prometheus rules, Grafana dashboards and alert rules, and Alertmanager configuration for the [static-builds targets](https://github.com/ririnto/static-builds/blob/main/metadata.json).
See the [target metrics reference](docs/targets.md) for scrape paths, enablement, and source evidence.

## Generate and verify

Use Go as declared in `go.mod`, Node.js 24, and the pnpm version in `package.json`.
The Go module supplies the tools used to generate and verify the configuration.

- Jsonnet
- promtool
- amtool
- Task
- shfmt
- golangci-lint

```sh
pnpm install --frozen-lockfile
pnpm generate
pnpm check
```

Edit `mixins/` and commit the regenerated files under `rendered/`.
CI runs the following configuration checks.

- Render into a temporary directory and compare the bytes with the committed output.
- Check and test Prometheus rules.
- Check Alertmanager configuration and routing.
- Validate the dashboard against Grafana's published V2 CUE schema.
  The check downloads the upstream schema over HTTPS and rejects a fixture with a numeric title.

## Load the configuration

1. Set the exact scrape job names from the [target reference](docs/targets.md).
   Set a scrape interval of one minute or less for the five-minute rate queries.
2. Load `rendered/prometheus-rules.yaml` through Prometheus `rule_files`.
3. Use `rendered/alertmanager.yaml` to verify grouping before configuring your own receivers.
   Its only receiver discards notifications.
4. Create or select a Grafana Prometheus data source with UID `prometheus`.
   Import `rendered/static-targets.json` as a V2 Dashboard resource.
5. To evaluate the Vector alert in Grafana, provision `rendered/grafana-alerts.yaml` and review its no-data and delivery behavior in your environment.
   The rule starts paused and Prometheus has no equivalent rule.

A missing time series means the dashboard has no observations for that query.
Prometheus's scrape alert requires a configured target.
If a target disappears from service discovery, that alert stops seeing the series.
Manage service discovery coverage separately.

The Prometheus rules carry `owner="prometheus"`.
The Grafana rule carries `owner="grafana"`.
If you add another rule, assign one engine to evaluate it and one receiver path for delivery.

See [design and validation](docs/design.md) for implementation sources and the visualization criteria.
