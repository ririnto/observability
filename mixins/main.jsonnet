local targets = import 'targets.libsonnet';
local dashboard = (import 'dashboard.libsonnet')(targets);
local alerts = (import 'alerts.libsonnet')(targets);

{
  'alertmanager.yaml': std.manifestYamlDoc({
    route: {
      receiver: 'discard',
      group_by: ['alertname', 'job'],
      group_wait: '30s',
      group_interval: '5m',
      repeat_interval: '4h',
    },
    receivers: [{ name: 'discard' }],
  }) + '\n',
  'grafana-alerts.yaml': std.manifestYamlDoc(alerts.grafana) + '\n',
  'prometheus-rules.yaml': std.manifestYamlDoc(alerts.prometheus) + '\n',
  'static-targets.json': std.manifestJsonEx(dashboard, '  ') + '\n',
}
