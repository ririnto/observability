local mixin = (import 'node-exporter/docs/node-mixin/mixin.libsonnet') + {
  _config+:: { nodeExporterSelector: 'job="node-exporter"' },
};
local grafanaAlerts = import 'grafana-alerts.libsonnet';
local networkErrorDirections = {
  NodeNetworkReceiveErrs: 'receive',
  NodeNetworkTransmitErrs: 'transmit',
};
local alertGroups = [
  group {
    interval: '1m',
    rules: [
      rule {
        labels+: { owner: 'prometheus' },
        annotations+: {
          [if std.objectHas(networkErrorDirections, rule.alert) then 'description']:
            '{{ $labels.instance }} interface {{ $labels.device }} had a %s error ratio of {{ $value | humanizePercentage }} over the last two minutes.' % networkErrorDirections[rule.alert],
        },
      }
      for rule in group.rules
      // The static-target rule already covers this signal with a reachability guard.
      if rule.alert != 'NodeTextFileCollectorScrapeError'
    ],
  }
  for group in mixin.prometheusAlerts.groups
];

{
  'node-exporter-recording-rules.yaml': std.manifestYamlDoc(mixin.prometheusRules) + '\n',
  'node-exporter-alert-rules.yaml': std.manifestYamlDoc({ groups: alertGroups }) + '\n',
  'node-exporter-grafana-alerts.yaml': std.manifestYamlDoc(grafanaAlerts(alertGroups, 'Node Exporter')) + '\n',
} + {
  ['node-exporter-dashboards/' + file]: std.manifestJsonEx(mixin.grafanaDashboards[file], '  ') + '\n'
  for file in std.objectFields(mixin.grafanaDashboards)
}
