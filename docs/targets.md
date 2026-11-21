# Target metrics reference

The source of the target list is [static-builds metadata](https://github.com/ririnto/static-builds/blob/main/metadata.json).
Ports marked as examples require explicit listener configuration.
Configure the job name shown in this table so the generated PromQL selects the intended data.

| Build target | Service and port | Metrics job and HTTP path | Metrics used |
| --- | --- | --- | --- |
| `apache-exporter` | HTTP 9117 by default. | `apache-exporter`, `/metrics`. | `apache_up` and `apache_accesses_total`. Prometheus attaches `job` and `instance`. |
| `apache-httpd` | HTTP 80 and HTTPS 443 in the image. | No native Prometheus exposition in this build. Enable `mod_status` and point `apache-exporter` at `/server-status?auto`. | Apache exporter converts Apache's status response. |
| `coredns` | DNS TCP and UDP 53. The configured `prometheus` plugin defaults to loopback 9153. | `coredns`, `/metrics`. | `coredns_dns_requests_total`. |
| `dnsmasq` | DNS TCP and UDP 53 and DHCP UDP 67. | No native Prometheus HTTP listener in this build. | None. Collect DNS/DHCP logs or supply an independent exporter. |
| `haproxy` | The image declares HTTP 80 and HTTPS 443. The exporter binds on a frontend you configure. | `haproxy`, `/metrics` when the frontend selects `prometheus-exporter` on that path. | `haproxy_frontend_http_responses_total` and `haproxy_backend_status{state="DOWN"}`. The `proxy` label identifies the frontend or backend. |
| `monit` | Optional Monit HTTP interface. The image declares 2812. | No native Prometheus exposition in this build. | Monit status and events are separate from Prometheus. |
| `nginx` | HTTP 80 and HTTPS 443 in the image. | `nginx`, `/status/format/prometheus` when you configure a VTS display location at `/status`. | `nginx_vts_server_requests_total` with `host` and `code`. The aggregate `host="*"` is excluded. |
| `nginx-upstream-healthcheck` | HTTP 80 and HTTPS 443 in the image. The checked-in metrics example uses loopback 18080. | `nginx-upstream-healthcheck` at `/health-metrics` and optional `nginx-health-traffic` at `/traffic-metrics`. | HTTP and stream `nginx_*healthcheck_check_status` and `nginx_*healthcheck_admin_down` by `upstream`, `server`, `peer`, and `backup`. The separate traffic endpoint exposes VTS. |
| `node-exporter` | HTTP 9100 by default. | `node-exporter`, `/metrics`. | `node_exporter_build_info` identifies the build. `node_scrape_collector_success` and `node_scrape_collector_duration_seconds` use the `collector` label. `node_textfile_scrape_error` identifies a textfile collection error. |
| `vector` | The image declares 8686 for the optional API. A configured `prometheus_exporter` sink defaults to 9598. | `vector`, `/metrics`. Wire the `internal_metrics` source to the sink. | `vector_component_received_events_total` and `vector_component_errors_total`. The `component_id` label identifies the component. The events panel counts sources and excludes the metrics source. |

VTS accepts an explicit format suffix or the format set on the display location.
The health-check example sets the location format to Prometheus.
Choose a private listener for metrics that contain backend or virtual-host labels.

## CoreDNS request metric labels

The `coredns_dns_requests_total` metric has these labels.

- `server`
- `zone`
- `view`
- `proto`
- `family`
- `type`

## NGINX probe results

| Value | Probe result |
| --- | --- |
| `-1` | No probe has completed. |
| `0` | The last probe failed. |
| `1` | The last probe passed. |

The dashboard counts last-probe failures and excludes administratively disabled peers.

## Node Exporter collector results

Node Exporter returns a collector success value of zero for both an error and a no-data result.
The dashboard counts both outcomes from reachable exporters and shows the longest duration among successful collectors.
The textfile alert uses the specific error metric while its exporter remains reachable.
The general scrape alert covers exporter unreachability.

## Source evidence

- Apache exporter listener, path, and metrics are defined in [startup](https://github.com/Lusitaniae/apache_exporter/blob/main/apache_exporter.go) and its [collector](https://github.com/Lusitaniae/apache_exporter/blob/main/collector/collector.go).
  The [Apache build](https://github.com/ririnto/static-builds/blob/main/apache-httpd/Dockerfile) includes [mod_status](https://httpd.apache.org/docs/2.4/mod/mod_status.html).
- CoreDNS defines its listener and metrics in the [Prometheus plugin](https://github.com/coredns/coredns/tree/master/plugin/metrics) and [metric variables](https://github.com/coredns/coredns/blob/master/plugin/metrics/vars/vars.go).
- HAProxy compiles [Prometheus exporter support](https://github.com/ririnto/static-builds/blob/main/haproxy/Dockerfile).
  The exporter listener is selected by [HAProxy configuration](https://docs.haproxy.org/3.4/configuration.html#prometheus-exporter) and metric behavior is in the [addon source](https://github.com/haproxy/haproxy/tree/master/addons/promex).
- The [DNSMasq build](https://github.com/ririnto/static-builds/blob/main/dnsmasq/Dockerfile) and [upstream manual](https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html) describe DNS, DHCP, and logging.
- The [Monit build](https://github.com/ririnto/static-builds/blob/main/monit/Dockerfile) and [upstream manual](https://mmonit.com/monit/documentation/monit.html) describe its HTTP interface.
- NGINX VTS exposes [Prometheus metric families](https://github.com/vozlt/nginx-module-vts/blob/master/src/ngx_http_vhost_traffic_status_display_prometheus.h) through its [display handler](https://github.com/vozlt/nginx-module-vts/blob/master/src/ngx_http_vhost_traffic_status_display.c).
  The health-check build contains the [checker](https://github.com/ririnto/static-builds/tree/main/nginx-upstream-healthcheck/ngx_http_upstream_healthcheck_module) and [listener example](https://github.com/ririnto/static-builds/blob/main/nginx-upstream-healthcheck/examples/config/nginx.conf).
- Node Exporter sets port 9100 and registers build information in [startup](https://github.com/prometheus/node_exporter/blob/v1.13.1/node_exporter.go).
  The [collector](https://github.com/prometheus/node_exporter/blob/v1.13.1/collector/collector.go) defines success and duration, and the [textfile collector](https://github.com/prometheus/node_exporter/blob/v1.13.1/collector/textfile.go) defines its error gauge.
  [Static Builds #210](https://github.com/ririnto/static-builds/pull/210) added the Linux amd64 and arm64 target and documents its default metrics path.
- Vector implements metrics in the [internal metrics source](https://github.com/vectordotdev/vector/tree/master/src/sources/internal_metrics) and its [Prometheus sink](https://github.com/vectordotdev/vector/blob/master/src/sinks/prometheus/exporter.rs).
  The [build](https://github.com/ririnto/static-builds/blob/main/vector/Dockerfile) shows the separate API port.
