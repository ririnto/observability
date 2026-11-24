local grafanaAlerts = import 'grafana-alerts.libsonnet';
local selector = 'job="coredns"';
local mixin = (import 'coredns-mixin/mixin.libsonnet') {
  _config+:: {
    corednsSelector: selector,
    instanceLabel: 'instance',
  },
};
local forwardMetrics = {
  coredns_forward_healthcheck_failures_total: 'coredns_proxy_healthcheck_failures_total',
  coredns_forward_request_duration_seconds_bucket: 'coredns_proxy_request_duration_seconds_bucket',
  coredns_forward_requests_total: 'coredns_proxy_request_duration_seconds_count',
  coredns_forward_responses_total: 'coredns_proxy_request_duration_seconds_count',
};
local useProxyMetrics(expr) = std.foldl(
  function(query, metric) std.strReplace(query, metric + '{', forwardMetrics[metric] + '{proxy_name="forward",'),
  std.objectFields(forwardMetrics),
  expr
);
local alertDescriptions = {
  CoreDNSLatencyHigh: 'CoreDNS 99th percentile latency is {{ $value | humanizeDuration }} for server {{ $labels.server }} in zone "{{ $labels.zone }}".',
  CoreDNSForwardLatencyHigh: 'CoreDNS has 99th percentile latency of {{ $value | humanizeDuration }} forwarding requests to {{ $labels.to }}.',
  CoreDNSForwardHealthcheckBrokenCount: 'CoreDNS received requests while all forwarding upstreams were unhealthy.',
};
local alertGroups = [
  group {
    interval: '1m',
    rules: [
      rule {
        expr: useProxyMetrics(super.expr),
        labels+: { owner: 'prometheus' },
        annotations: std.objectRemoveKey(super.annotations, 'runbook_url') {
          description: std.get(alertDescriptions, rule.alert, super.description),
        },
      }
      for rule in group.rules
      if rule.alert != 'CoreDNSDown'
    ],
  }
  for group in mixin.prometheusAlerts.groups
];

local upstream = mixin.grafanaDashboards['coredns.json'];
local datasource = { type: 'prometheus', uid: '${datasource}' };
local instanceSelector = selector + ',instance=~"${instance:regex}"';
local cacheRequests = 'sum(rate(coredns_cache_requests_total{%s}[5m]))' % instanceSelector;
local cacheHits = '(sum(rate(coredns_cache_hits_total{%s}[5m])) or vector(0))' % instanceSelector;
local dashboard = {
  uid: upstream.uid,
  title: upstream.title,
  tags: upstream.tags,
  time: upstream.time,
  refresh: upstream.refresh,
  schemaVersion: 41,
  templating: {
    list: [
      std.objectRemoveKey(upstream.templating.list[0], 'current'),
      upstream.templating.list[1] {
        label: 'Instance',
        datasource: datasource,
        allValue: '.+',
        current: { text: 'All', value: '$__all' },
      },
    ],
  },
  panels: [
    local stat = panel.type == 'singlestat';
    {
      id: panel.id,
      title: std.get({
        'RPC Rate': 'DNS responses',
        'Forward Requests (by to)': 'Forwarded responses by upstream',
        Cached: 'Cache hit ratio',
        'Cache hit Rate': 'Cache hits and misses',
      }, panel.title, panel.title),
      type: if stat then 'stat' else 'timeseries',
      datasource: datasource,
      gridPos: {
        x: 2 * std.foldl(function(offset, previous) offset + previous.span, row.panels[:columnIndex], 0),
        y: rowIndex * 8,
        w: panel.span * 2,
        h: 8,
      },
      fieldConfig: {
        defaults: { unit: if stat then panel.format else panel.yaxes[0].format },
        overrides: [],
      },
      options: if stat then {
        colorMode: 'none',
        graphMode: 'none',
        reduceOptions: { calcs: ['lastNotNull'] },
      } else {
        legend: { showLegend: true, displayMode: 'list', placement: 'bottom' },
        tooltip: { mode: 'multi' },
      },
      targets: [
        {
          refId: target.refId,
          legendFormat: target.legendFormat,
          datasource: datasource,
          instant: stat,
          range: !stat,
          expr:
            if panel.title == 'Cached' then '%s / (%s > 0)' % [cacheHits, cacheRequests]
            else if target.legendFormat == 'misses' then '%s - %s' % [cacheRequests, cacheHits]
            else useProxyMetrics(std.strReplace(
              std.strReplace(target.expr, selector + '}', instanceSelector + '}'),
              '$instance',
              '${instance:regex}'
            )),
        }
        for target in panel.targets
      ],
    }
    for rowIndex in std.range(0, std.length(upstream.rows) - 1)
    for row in [upstream.rows[rowIndex]]
    for columnIndex in std.range(0, std.length(row.panels) - 1)
    for panel in [row.panels[columnIndex]]
  ],
};

{
  'coredns-alert-rules.yaml': std.manifestYamlDoc({ groups: alertGroups }) + '\n',
  'coredns-grafana-alerts.yaml': std.manifestYamlDoc(grafanaAlerts(alertGroups, 'CoreDNS')) + '\n',
  'coredns-dashboards/coredns.json': std.manifestJsonEx(dashboard, '  ') + '\n',
}
