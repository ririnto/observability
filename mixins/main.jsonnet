local targets = import 'targets.libsonnet';
local dashboard = (import 'dashboard.libsonnet')(targets);
local alerts = (import 'alerts.libsonnet')(targets);
local grafanaAlerts = import 'grafana-alerts.libsonnet';
local kubernetes = (import 'kubernetes.libsonnet');
local nodeExporter = import 'node-exporter.libsonnet';

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
  'grafana-alerts.yaml': std.manifestYamlDoc(grafanaAlerts([alerts.static, alerts.vector], 'Static targets', {
    VectorComponentErrors: {
      uid: 'static-vector-component-errors',
      title: 'Vector component errors',
      query: targets.vectorErrors,
      math: '$A > 0',
    },
  })) + '\n',
  'prometheus-rules.yaml': std.manifestYamlDoc({ groups: [alerts.static] }) + '\n',
  'vector-rules.yaml': std.manifestYamlDoc({ groups: [alerts.vector] }) + '\n',
  'static-targets.json': std.manifestJsonEx(dashboard, '  ') + '\n',
} + kubernetes + nodeExporter
