local grafanaAlerts = import 'grafana-alerts.libsonnet';
local mixin = import 'grafana-jsonnet-libs/apache-http-mixin/mixin.libsonnet';
local expressions = {
  ApacheRestart: {
    upstream: 'apache_uptime_seconds_total / 60 < 1',
    scoped: 'apache_uptime_seconds_total{job="apache-exporter"} / 60 < 1',
  },
  ApacheWorkersLoad: {
    upstream: |||
      (sum by (instance) (apache_workers{state="busy"}) / sum by (instance) (apache_scoreboard) ) * 100 > 80
    |||,
    scoped: |||
      (sum by (job, instance, cluster) (apache_workers{job="apache-exporter", state="busy"}) / (sum by (job, instance, cluster) (apache_scoreboard{job="apache-exporter"}) > 0) ) * 100 > 80
    |||,
  },
  ApacheResponseTimeTooHigh: {
    upstream: |||
      increase(apache_duration_ms_total[5m])/increase(apache_accesses_total[5m]) > 5000
    |||,
    scoped: |||
      increase(apache_duration_ms_total{job="apache-exporter"}[5m])/(increase(apache_accesses_total{job="apache-exporter"}[5m]) > 0) > 5000
    |||,
  },
};
local alertGroups = [
  group {
    interval: '1m',
    rules: [
      local expression = expressions[rule.alert];
      assert rule.expr == expression.upstream : 'Upstream Apache expression changed for ' + rule.alert;
      rule {
        expr: expression.scoped,
        'for': if rule['for'] == '0' then '0s' else rule['for'],
        labels+: { owner: 'prometheus' },
      }
      for rule in group.rules
      if rule.alert != 'ApacheDown'
    ],
  }
  for group in mixin.prometheusAlerts.groups
];

{
  'apache-http-alert-rules.yaml': std.manifestYamlDoc({ groups: alertGroups }) + '\n',
  'apache-http-grafana-alerts.yaml': std.manifestYamlDoc(grafanaAlerts(alertGroups, 'Apache HTTP Server')) + '\n',
} + {
  local upstreamDashboard = mixin.grafanaDashboards[file],
  local rowOffsets = std.foldl(
    function(layout, y) {
      nextY: layout.nextY + std.maxArray([panel.gridPos.h for panel in upstreamDashboard.panels if panel.gridPos.y == y]),
      offsets: layout.offsets { [std.toString(y)]: layout.nextY },
    },
    std.set([panel.gridPos.y for panel in upstreamDashboard.panels]),
    { nextY: 0, offsets: {} }
  ).offsets,
  local dashboard = std.objectRemoveKey(upstreamDashboard, 'gnetId') {
    timepicker: std.objectRemoveKey(super.timepicker, 'time_options'),
    panels: [
      {
        [key]: panel[key]
        for key in std.objectFields(panel)
        if !(key == 'timeFrom' || key == 'timeShift') || panel[key] != null
      } {
        gridPos+: { y: rowOffsets[std.toString(super.y)] },
      }
      for panel in super.panels
    ],
    templating+: {
      list: [
        if variable.type == 'query' then
          (if variable.allValue == null then std.objectRemoveKey(variable, 'allValue') else variable) {
            datasource: { type: 'prometheus', uid: '${prometheus_datasource}' },
          }
        else variable
        for variable in super.list
      ],
    },
  },
  ['apache-http-dashboards/' + file]: std.manifestJsonEx(dashboard, '  ') + '\n'
  for file in std.objectFields(mixin.grafanaDashboards)
}
