local lib = import 'grafana-jsonnet-libs/istio-2-mixin/main.libsonnet';
local mixin = lib.new() + lib.withConfigMixin({ filteringSelector: 'job="integrations/istio"' });
local grafanaAlerts = import 'grafana-alerts.libsonnet';
local alertGroups = [
  group {
    interval: '1m',
    rules: [rule { labels+: { owner: 'prometheus' } } for rule in group.rules],
  }
  for group in mixin.prometheus.alerts.groups
];

{
  'istio-alert-rules.yaml': std.manifestYamlDoc({ groups: alertGroups }) + '\n',
  'istio-grafana-alerts.yaml': std.manifestYamlDoc(grafanaAlerts(alertGroups, 'Istio')) + '\n',
} + {
  local dashboard = mixin.grafana.dashboards[file],
  ['istio-dashboards/' + file]: std.manifestJsonEx(
    dashboard {
      panels: [
        if panel.type == 'row' && panel.gridPos.w == 0 then panel { gridPos+: { w: 24 } }
        else panel
        for panel in dashboard.panels
      ],
    },
    '  '
  ) + '\n'
  for file in std.objectFields(mixin.grafana.dashboards)
}
