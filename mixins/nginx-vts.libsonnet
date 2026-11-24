local config = import 'dnation-kubernetes-monitoring/jsonnet/config.libsonnet';
local mixin =
  (import 'dnation-kubernetes-monitoring/jsonnet/dashboards/apps/nginx-vts.libsonnet') +
  (import 'dnation-kubernetes-monitoring/jsonnet/dashboards/apps/nginx-vts-enhanced.libsonnet') +
  (import 'dnation-kubernetes-monitoring/jsonnet/dashboards/grafana-templates.libsonnet') +
  config.mergeConfig(config.defaultConfig, { grafanaDashboards: { isLoki: false } }) + {
    grafanaTemplates+: {
      datasourceTemplate():: super.datasourceTemplate() {
        current+: { text: 'Prometheus', value: 'prometheus' },
      },
      clusterTemplate(query):: super.clusterTemplate('label_values(nginx_vts_server_bytes_total, cluster)'),
      namespaceTemplate(query):: super.namespaceTemplate(query) {
        allValue: '.*',
        current: { text: 'All', value: '$__all' },
      },
      podTemplate(query):: super.podTemplate(query) {
        allValue: '.*',
        current: { text: 'All', value: '$__all' },
      },
    },
  };
local grafanaAlerts = import 'grafana-alerts.libsonnet';
local upstreamAlert = config.defaultTemplate.L1.appTemplates.nginxVts.alert;
local requestRate = 'sum by (job, cluster) (rate(nginx_vts_server_requests_total{job=~".+", host!="*", code=~"%s"}[5m]))';
local totalRate = requestRate % '[1-5]xx';
local successRate = '100 * ((%s or (0 * %s)) / (%s > 0))' % [requestRate % '[1-3]xx', totalRate, totalRate];
local alertGroups = [{
  name: 'nginx-vts',
  interval: '1m',
  rules: [
    {
      alert: upstreamAlert.name % { prefix: '' },
      expr: '%s %s %s' % [successRate, upstreamAlert.thresholds.operator, upstreamAlert.thresholds[severity]],
      'for': config.defaultConfig.prometheusRules.alertInterval,
      labels: { severity: severity, owner: 'prometheus' },
      annotations: {
        summary: 'NGINX VTS request success rate is low.',
        description: 'The NGINX VTS request success rate for {{ $labels.job }} is {{ printf "%.4g" $value }}%. Check 4xx and 5xx responses.',
      },
    }
    for severity in ['critical', 'warning']
  ],
}];

{
  'nginx-vts-alert-rules.yaml': std.manifestYamlDoc({ groups: alertGroups }) + '\n',
  'nginx-vts-grafana-alerts.yaml': std.manifestYamlDoc(grafanaAlerts(alertGroups, 'NGINX VTS')) + '\n',
} + {
  ['nginx-vts-dashboards/' + name + '.json']: std.manifestJsonEx(mixin.grafanaDashboards[name], '  ') + '\n'
  for name in std.objectFields(mixin.grafanaDashboards)
}
