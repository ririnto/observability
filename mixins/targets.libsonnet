local rate(metric, job) = 'sum(rate(%s{job="%s"}[5m]))' % [metric, job];
local unhealthy(prefix) =
  'sum((nginx_%shealthcheck_check_status{job="nginx-upstream-healthcheck"} == bool 0) unless (nginx_%shealthcheck_admin_down{job="nginx-upstream-healthcheck"} == 1))' % [prefix, prefix];
local nodeReachable = 'and on (job, instance) (up{job="node-exporter"} == 1)';
local nodeCollectorSuccess = 'node_scrape_collector_success{job="node-exporter"}';

{
  jobs: [
    'apache-exporter',
    'coredns',
    'haproxy',
    'nginx',
    'nginx-health-traffic',
    'nginx-upstream-healthcheck',
    'node-exporter',
    'vector',
  ],
  panels: [
    { title: 'Apache requests', expr: rate('apache_accesses_total', 'apache-exporter'), name: 'Requests', unit: 'reqps' },
    { title: 'CoreDNS queries', expr: rate('coredns_dns_requests_total', 'coredns'), name: 'Queries', unit: 'reqps' },
    {
      title: 'HAProxy HTTP responses',
      expr: rate('haproxy_frontend_http_responses_total', 'haproxy'),
      name: 'Responses',
      unit: 'reqps',
    },
    {
      title: 'NGINX virtual-host requests',
      expr: 'sum(rate(nginx_vts_server_requests_total{job="nginx",host!="*"}[5m]))',
      name: 'Requests',
      unit: 'reqps',
    },
    {
      title: 'Health-check NGINX virtual-host requests',
      expr: 'sum(rate(nginx_vts_server_requests_total{job="nginx-health-traffic",host!="*"}[5m]))',
      name: 'Requests',
      unit: 'reqps',
    },
    {
      title: 'NGINX peers with failing probes',
      queries: [
        { name: 'HTTP', color: '#0072B2', expr: unhealthy('') },
        { name: 'Stream', color: '#D55E00', expr: unhealthy('stream_') },
      ],
      unit: 'short',
    },
    {
      title: 'Vector events received from sources',
      expr: 'sum(rate(vector_component_received_events_total{job="vector",component_kind="source",component_type!="internal_metrics"}[5m]))',
      name: 'Events',
      unit: 'eps',
    },
    {
      title: 'Node Exporter collectors without a successful scrape',
      expr: 'sum((%s == bool 0) %s)' % [nodeCollectorSuccess, nodeReachable],
      name: 'Non-successful collectors',
      unit: 'short',
    },
    {
      title: 'Slowest successful Node Exporter collector',
      expr: 'max(node_scrape_collector_duration_seconds{job="node-exporter"} and on (job, instance, collector) (%s == 1) %s)' % [nodeCollectorSuccess, nodeReachable],
      name: 'Collector duration',
      unit: 's',
    },
  ],
  nodeTextfileError: '(node_textfile_scrape_error{job="node-exporter"} == 1) ' + nodeReachable,
  vectorErrors: rate('vector_component_errors_total', 'vector'),
}
