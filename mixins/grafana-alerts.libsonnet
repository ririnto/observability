function(groups, folder, overrides={})
  local names = [rule.alert for group in groups for rule in group.rules];
  {
    apiVersion: 1,
    groups: [
      {
        orgId: 1,
        name: group.name,
        folder: folder,
        interval: group.interval,
        rules: [
          local labels = std.get(rule, 'labels', {});
          local annotations = std.get(rule, 'annotations', {});
          local settings = {
            uid: 'obs-' + std.md5(std.manifestJsonEx([folder, group.name, rule.alert, labels], '')),
            title: rule.alert + (
              if std.count(names, rule.alert) == 1 then ''
              else ' (%s)' % std.join(', ', [key + '=' + labels[key] for key in std.objectFields(labels) if key != 'owner'])
            ),
            query: rule.expr,
            math: 'is_null($A) == 0',
          } + std.get(overrides, rule.alert, {});
          {
            uid: settings.uid,
            title: settings.title,
            condition: 'B',
            noDataState: 'OK',
            execErrState: 'Error',
            'for': std.get(rule, 'for', '0s'),
            [if 'keep_firing_for' in rule then 'keepFiringFor']: rule.keep_firing_for,
            isPaused: true,
            labels: labels { owner: 'grafana', prometheus_alertname: rule.alert },
            annotations: {
              [key]: std.strReplace(annotations[key], '$value', '$values.A.Value')
              for key in std.objectFields(annotations)
            },
            data: [
              {
                refId: 'A',
                datasourceUid: 'prometheus',
                relativeTimeRange: { from: 300, to: 0 },
                model: { refId: 'A', expr: settings.query, instant: true, range: false },
              },
              {
                refId: 'B',
                datasourceUid: '__expr__',
                relativeTimeRange: { from: 0, to: 0 },
                model: { refId: 'B', type: 'math', expression: settings.math },
              },
            ],
          }
          for rule in group.rules
        ],
      }
      for group in groups
    ],
  }
