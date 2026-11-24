# Observability configuration

This repository generates Prometheus rules, Grafana dashboards and alert rules, and Alertmanager configuration for the [static-builds targets](https://github.com/ririnto/static-builds/blob/main/metadata.json).
It also generates dashboards, recording rules, and paired alerts for [Kubernetes](#monitor-kubernetes).
See the [target metrics reference](docs/targets.md) for scrape paths, enablement, and source evidence.

## Generate and verify

Use Go as declared in `go.mod`, Node.js 24, and the pnpm version in `package.json`.
The Go module supplies the tools used to generate and verify the configuration.

- Jsonnet
- Jsonnet Bundler
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
- Require a Grafana and a Prometheus rule for each alert, including each variant with distinct labels.
- Check Alertmanager configuration and routing.
- Validate the dashboards against Grafana's published V2 and Classic CUE schemas.
  The check downloads the schemas over HTTPS and rejects a V2 fixture with a numeric title.

## Load the configuration

1. Set the exact scrape job names from the [target reference](docs/targets.md).
   Set a scrape interval of one minute or less for the five-minute rate queries.
2. Load `rendered/prometheus-rules.yaml` through Prometheus `rule_files`.
3. Use `rendered/alertmanager.yaml` to verify grouping before configuring your own receivers.
   Its only receiver discards notifications.
4. Create or select a Grafana Prometheus data source with UID `prometheus`.
   Import `rendered/static-targets.json` as a V2 Dashboard resource.
5. To evaluate static-target alerts in Grafana, provision `rendered/grafana-alerts.yaml` in the `Static targets` folder and unpause the desired rules in the file.
6. To evaluate Vector in Prometheus, add `rendered/vector-rules.yaml` to `rule_files`.
   To evaluate it in Grafana, unpause `Vector component errors` in `rendered/grafana-alerts.yaml`.

A missing time series means the dashboard has no observations for that query.
Prometheus's scrape alert requires a configured target.
If a target disappears from service discovery, that alert stops seeing the series.
Manage service discovery coverage separately.

## Monitor Kubernetes

1. Configure Prometheus to scrape the mixin's [job names and metrics](https://github.com/kubernetes-sigs/kubernetes-mixin/blob/464d0ae592cb7d7b1c6f40741fc72fb7bb2449ac/config.libsonnet).
   The defaults include `cadvisor`, `kubelet`, `kube-state-metrics`, `node-exporter`, `kube-apiserver`, `kube-scheduler`, `kube-controller-manager`, and `kube-proxy`.
   The Windows dashboards use `kubernetes-windows-exporter`.
   Scrape the API server every 15 seconds to give the one-minute increase query enough samples.
   Scrape the other jobs at least once a minute for the five-minute rate queries.
2. Add `rendered/kubernetes-recording-rules.yaml` to Prometheus `rule_files` and use a global evaluation interval of one minute.
   The dashboards and several alerts query these recording rules.
3. Import the files in `rendered/kubernetes-dashboards/` as Grafana Classic dashboards.
   Select the Prometheus data source that evaluates the recording rules.
4. To evaluate alerts in Prometheus, add `rendered/kubernetes-alert-rules.yaml` to `rule_files`.
   To evaluate alerts in Grafana, provision `rendered/kubernetes-grafana-alerts.yaml` in the `Kubernetes` folder and unpause the desired rules in the file.
   Grafana alert queries use the data source UID `prometheus`.

## Choose which engine delivers alerts

The generated Grafana rules start paused.
Enable one evaluator per alert when you need only one copy.
If you run both evaluators, configure receiving policies so only the chosen engine can notify for each alert.
Prometheus rules carry `owner="prometheus"` and Grafana rules carry `owner="grafana"`.
Match Grafana rules by `prometheus_alertname` when a policy needs the original Prometheus alert name.
Route Grafana `DatasourceError` alerts separately if you enable their notifications.

See [design and validation](docs/design.md) for implementation sources and the visualization criteria.
