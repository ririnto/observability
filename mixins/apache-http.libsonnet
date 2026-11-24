local grafanaAlerts = import 'grafana-alerts.libsonnet';
local mixin = import 'grafana-jsonnet-libs/apache-http-mixin/mixin.libsonnet';
local replacements = {
  apache_uptime_seconds_total: 'apache_uptime_seconds_total{job="apache-exporter"}',
  'sum by (instance) (apache_workers{state="busy"})': 'sum by (job, instance, cluster) (apache_workers{job="apache-exporter", state="busy"})',
  'sum by (instance) (apache_scoreboard)': '(sum by (job, instance, cluster) (apache_scoreboard{job="apache-exporter"}) > 0)',
  'apache_duration_ms_total[5m]': 'apache_duration_ms_total{job="apache-exporter"}[5m]',
  'increase(apache_accesses_total[5m])': '(increase(apache_accesses_total{job="apache-exporter"}[5m]) > 0)',
};
local alertGroups = [
  group {
    interval: '1m',
    rules: [
      rule {
        expr: std.foldl(
          function(expr, source) std.strReplace(expr, source, replacements[source]),
          std.objectFields(replacements),
          rule.expr
        ),
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
  local rowOffsets = [0, 3, 10, 20],
  local dashboard = std.objectRemoveKey(mixin.grafanaDashboards[file], 'gnetId') {
    timepicker: std.objectRemoveKey(super.timepicker, 'time_options'),
    panels: [
      {
        [key]: panel[key]
        for key in std.objectFields(panel)
        if !(key == 'timeFrom' || key == 'timeShift') || panel[key] != null
      } {
        gridPos+: { y: rowOffsets[super.y] },
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
