local rule(name, expr, wait, summary, description) = {
  alert: name,
  expr: expr,
  'for': wait,
  labels: { severity: 'warning', owner: 'prometheus' },
  annotations: { summary: summary, description: description },
};

function(targets) {
  prometheus: {
    groups: [
      {
        name: 'static-targets',
        interval: '1m',
        rules: [
          rule(
            'StaticTargetScrapeFailed',
            'up{job=~"%s"} == 0' % std.join('|', targets.jobs),
            '5m',
            'Prometheus cannot scrape {{ $labels.job }} at {{ $labels.instance }}.',
            'Check the target process, listener, scrape path, and network reachability.'
          ),
          rule(
            'ApacheStatusScrapeFailed',
            'apache_up{job="apache-exporter"} == 0',
            '5m',
            'The Apache exporter cannot read Apache status at {{ $labels.instance }}.',
            'Check the configured scrape URI, mod_status access rules, and the Apache service.'
          ),
          rule(
            'HAProxyBackendDown',
            'haproxy_backend_status{job="haproxy",state="DOWN"} == 1',
            '5m',
            'HAProxy backend {{ $labels.proxy }} is down at {{ $labels.instance }}.',
            'Check server health and connectivity in the affected backend.'
          ),
          rule(
            'NodeTextFileCollectorScrapeError',
            targets.nodeTextfileError,
            '5m',
            'Node Exporter could not read textfile metrics at {{ $labels.instance }}.',
            'Check the configured textfile directories, permissions, and Prometheus format of the metric files.'
          ),
        ],
      },
    ],
  },
  grafana: {
    apiVersion: 1,
    groups: [
      {
        orgId: 1,
        name: 'Vector pipeline',
        folder: 'Static targets',
        interval: '1m',
        rules: [
          {
            uid: 'static-vector-component-errors',
            title: 'Vector component errors',
            condition: 'B',
            noDataState: 'OK',
            execErrState: 'Error',
            'for': '10m',
            isPaused: true,
            labels: { severity: 'warning', owner: 'grafana' },
            annotations: {
              summary: 'Vector records sustained component errors.',
              description: 'Inspect the error type, component logs, and pipeline inputs before enabling notifications.',
            },
            data: [
              {
                refId: 'A',
                datasourceUid: 'prometheus',
                relativeTimeRange: { from: 300, to: 0 },
                model: { refId: 'A', expr: targets.vectorErrors, instant: true, range: false },
              },
              {
                refId: 'B',
                datasourceUid: '__expr__',
                relativeTimeRange: { from: 0, to: 0 },
                model: { refId: 'B', type: 'math', expression: '$A > 0' },
              },
            ],
          },
        ],
      },
    ],
  },
}
