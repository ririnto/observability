local mixin = (import 'kubernetes-mixin/mixin.libsonnet') + { _config+:: { datasourceName: 'prometheus' } };
local grafanaAlerts = import 'grafana-alerts.libsonnet';
local alertGroups = [
  group {
    interval: std.get(group, 'interval', '1m'),
    rules: [rule { labels+: { owner: 'prometheus' } } for rule in group.rules],
  }
  for group in mixin.prometheusAlerts.groups
];
local apiCodeRecord = 'code_verb:apiserver_request_total:increase1h';
local recordingGroups = [
  if group.name == 'kube-apiserver-availability.rules' then
    local codeRules = [rule for rule in group.rules if rule.record == apiCodeRecord];
    group {
      rules: [rule for rule in group.rules if rule.record != apiCodeRecord] + [
        codeRules[0] {
          expr: std.join('\n  or ', ['(' + std.stripChars(rule.expr, '\n') + ')' for rule in codeRules]) + '\n',
        },
      ],
    }
  else group
  for group in mixin.prometheusRules.groups
];

{
  'kubernetes-recording-rules.yaml': std.manifestYamlDoc({ groups: recordingGroups }) + '\n',
  'kubernetes-alert-rules.yaml': std.manifestYamlDoc({ groups: alertGroups }) + '\n',
  'kubernetes-grafana-alerts.yaml': std.manifestYamlDoc(grafanaAlerts(alertGroups, 'Kubernetes')) + '\n',
} + {
  local dashboard = mixin.grafanaDashboards[file],
  local panels = [
    if std.objectHasAll(panel, 'fieldConfig') && std.objectHas(std.get(panel.fieldConfig, 'defaults', {}), 'thresholds') then
      panel {
        fieldConfig+: {
          defaults+: {
            thresholds+: {
              steps: [std.objectRemoveKey(step, 'index') for step in super.steps],
            },
          },
        },
      }
    else panel
    for panel in dashboard.panels
  ],
  ['kubernetes-dashboards/' + file]: std.manifestJsonEx(dashboard { panels: panels }, '  ') + '\n'
  for file in std.objectFields(mixin.grafanaDashboards)
}
