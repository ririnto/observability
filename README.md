# Observability configuration

This repository generates Prometheus rules, Grafana dashboards and alert rules, and Alertmanager configuration for the [static-builds targets](https://github.com/ririnto/static-builds/blob/main/metadata.json).
It also generates dashboards and paired alerts for [Kubernetes](#monitor-kubernetes), [Node Exporter](#monitor-node-exporter), [Istio](#monitor-istio), [NGINX VTS](#monitor-nginx-vts), [Apache HTTP Server](#monitor-apache-http-server), and [CoreDNS](#monitor-coredns).
The Kubernetes and Node Exporter mixins also generate recording rules.
See the [target metrics reference](docs/targets.md) for scrape paths, enablement, and source evidence.

## Generate and verify

Use Go as declared in `go.mod`, Node.js 24, and the pnpm version in `package.json`.
Install Java for the Node Exporter textfile model check.
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
- Check the Node Exporter textfile model and replay its alert against the generated rules.
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

## Monitor Node Exporter

1. Scrape the Node Exporter `/metrics` endpoint with the job name `node-exporter`.
   Use a scrape interval of 30 seconds or less for the two-minute CPU and network rate queries.
   Enable the collectors relevant to each host. For the systemd rules, set `--collector.systemd` and `--collector.systemd.enable-restarts-metrics`.
   The RAID, bonding, conntrack, and clock alerts require the corresponding Linux metrics.
2. Add `rendered/node-exporter-recording-rules.yaml` to Prometheus `rule_files` and use a global evaluation interval of one minute.
   The USE Method dashboards query these recording rules.
3. Import the files in `rendered/node-exporter-dashboards/` as Grafana Classic dashboards.
   Select the Prometheus data source that evaluates the recording rules.
4. To evaluate alerts in Prometheus, add `rendered/node-exporter-alert-rules.yaml` to `rule_files`.
   To evaluate alerts in Grafana, provision `rendered/node-exporter-grafana-alerts.yaml` in the `Node Exporter` folder and unpause the desired rules in the file.
   Grafana alert queries use the data source UID `prometheus`.
5. For exporter reachability and textfile collector errors, use the existing static-target rules in `rendered/prometheus-rules.yaml` or `rendered/grafana-alerts.yaml`.
   Set `--collector.textfile.directory` on exporters that collect textfiles.

The upstream warning and critical variants can fire together. Use the `severity` label to route them in either evaluator.

### NodeTextfile statechart

The `NodeTextfile` model shows how the Node Exporter textfile collector error alert moves between inactive, pending, and firing.

![NodeTextfile statechart](.claude/skills/formal-verification/references/node-textfile/statechart.svg)

Run `pnpm render:statecharts` to regenerate the SVG.

## Monitor Istio

1. Scrape Istiod and the Envoy proxies, including gateways, at least once a minute.
   Use `/metrics` on Istiod's monitoring port and `/stats/prometheus` on the proxy telemetry endpoint.
   For endpoint setup, see [Istio's Prometheus integration guide](https://istio.io/latest/docs/ops/integrations/prometheus/).
2. Set the resulting scrape label `job="integrations/istio"` for both sets of targets.
   Attach `cluster` and `pod` to the scraped series.
   Control-plane alerts use pod names that start with `istiod`.
   Request alerts use source-reported Istio metrics and canonical service labels.
3. Import the files in `rendered/istio-dashboards/` as Grafana Classic dashboards.
   Select the Prometheus data source that scrapes Istio.
   For the optional **Istio logs** dashboard, select a Loki data source with Envoy access logs labeled for the [upstream Istio mixin](https://github.com/grafana/jsonnet-libs/tree/59b6c850610f7fa8816851c981bc76b92a55cde9/istio-2-mixin#istio-logs).
4. To evaluate the alerts in Prometheus, add `rendered/istio-alert-rules.yaml` to `rule_files`.
   To evaluate them in Grafana, provision `rendered/istio-grafana-alerts.yaml` in the `Istio` folder, set up a Prometheus data source with UID `prometheus`, and unpause the desired rules.
5. Route Istio notifications by `severity` and the alert name.
   In Prometheus Alertmanager, match `alertname` and `owner="prometheus"` and configure a real receiver.
   In Grafana, match `prometheus_alertname` and `owner="grafana"` and configure a contact point.

The dashboards and alerts query scraped metrics directly.
`IstioMetricsDown` fires for configured Istio targets with a failed scrape.
Track the coverage of service discovery separately.

## Monitor NGINX VTS

1. Enable the [NGINX VTS module](https://github.com/vozlt/nginx-module-vts) and scrape its Prometheus display endpoint at least once a minute.
   Use `/status/format/prometheus` when the display location is `/status`.
   The rule reads `nginx_vts_server_requests_total` with the native `host` and `code` labels.
   Attach a `cluster` label to the VTS scrape targets for the dashboards and to distinguish clusters in alerts.
2. Import the files in `rendered/nginx-vts-dashboards/` as Grafana Classic dashboards.
   Select the Prometheus data source that scrapes VTS and select a cluster.
   On the VTS panels, select named hosts or the `*` aggregate to count each request once.
   For **Nginx VTS Enhanced**, attach `namespace` and `pod` labels to VTS targets and load `rendered/kubernetes-recording-rules.yaml` for the CPU panel.
   Its resource panels also require kubelet cAdvisor and kube-state-metrics data.
3. For Prometheus evaluation, add `rendered/nginx-vts-alert-rules.yaml` to `rule_files`.
   For Grafana evaluation, provision `rendered/nginx-vts-grafana-alerts.yaml` in the `NGINX VTS` folder, use a Prometheus data source with UID `prometheus`, and unpause the desired rules.
4. Route `NginxVTSSuccessRateLow` by `severity` and evaluator ownership.
   Match `alertname` in Prometheus Alertmanager and `prometheus_alertname` in Grafana.
   Configure an Alertmanager receiver or Grafana contact point for the chosen evaluator.

The warning fires below 95% success and the critical alert fires below 85%, each after five minutes.
Both severities can fire together.
The rules stay quiet when traffic is idle or missing.
Track failed scrapes separately with the [static-target alerts](#load-the-configuration).

## Monitor Apache HTTP Server

1. Configure Apache's `mod_status` handler at `/server-status` with `ExtendedStatus On`.
   Restrict access to the exporter and point its `--scrape_uri` at `/server-status?auto`.
2. Scrape the exporter's `/metrics` endpoint on port 9117 as the `apache-exporter` job.
   Use a scrape interval of 15 seconds or less and a one-minute Prometheus evaluation interval.
   Attach a `cluster` label to distinguish identical instance labels from different clusters in the worker alert.
3. Import `rendered/apache-http-dashboards/apache-http.json` as a Grafana Classic dashboard.
   Select the Prometheus data source, the `apache-exporter` job, and an instance.
4. For Prometheus evaluation, add `rendered/apache-http-alert-rules.yaml` to `rule_files`.
   For Grafana evaluation, provision `rendered/apache-http-grafana-alerts.yaml` in the `Apache HTTP Server` folder.
   Use a Prometheus data source with UID `prometheus` and unpause the desired rules.
5. Route `ApacheRestart` as info and `ApacheWorkersLoad` and `ApacheResponseTimeTooHigh` as warnings.
   Match `alertname` and `owner="prometheus"` in Alertmanager or `prometheus_alertname` and `owner="grafana"` in Grafana.
   Configure a receiver or contact point for the chosen evaluator.
   The [static-target rules](#load-the-configuration) still cover exporter reachability and the `apache_up` signal.

The restart alert fires on the first evaluation that sees uptime below one minute, including at initial startup.
Scrape or evaluation gaps can hide that brief signal.
Grafana uses query presence to fire even when uptime is zero and can retain a vanished series until eviction.
The worker alert fires after 15 minutes above 80% of scoreboard slots.
The response-time alert fires after 15 minutes with a five-minute average above 5000 ms.
It needs requests in the five-minute window.

## Monitor CoreDNS

1. Enable the `prometheus` plugin in the Corefile and bind it to an address reachable by Prometheus.
2. Scrape `/metrics` as the `coredns` job at least once a minute.
   Keep the Prometheus `instance` label for dashboard filtering.
3. Import `rendered/coredns-dashboards/coredns.json` as a Grafana Classic dashboard.
   Select the Prometheus data source and an instance.
4. For Prometheus evaluation, add `rendered/coredns-alert-rules.yaml` to `rule_files`.
   For Grafana evaluation, provision `rendered/coredns-grafana-alerts.yaml` in the `CoreDNS` folder.
   Use a Prometheus data source with UID `prometheus` and unpause the desired rules.
5. Route the warning and critical alerts through the [chosen evaluator](#choose-which-engine-delivers-alerts).
   Keep the [static-target rules](#load-the-configuration) for failed scrapes.

The latency alerts fire after the 99th percentile exceeds four seconds for ten minutes.
The SERVFAIL alerts fire after the response ratio exceeds 1% for ten minutes.
The critical variant also fires after the ratio exceeds 3% for ten minutes.
The forwarding alerts and panels need the `forward` plugin.
The cache panels need the `cache` plugin.

## Choose which engine delivers alerts

The generated Grafana rules start paused.
Enable one evaluator per alert when you need only one copy.
If you run both evaluators, configure receiving policies so only the chosen engine can notify for each alert.
Prometheus rules carry `owner="prometheus"` and Grafana rules carry `owner="grafana"`.
Match Grafana rules by `prometheus_alertname` when a policy needs the original Prometheus alert name.
Route Grafana `DatasourceError` alerts separately if you enable their notifications.

See [design and validation](docs/design.md) for implementation sources and the visualization criteria.
