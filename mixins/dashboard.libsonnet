local id = 'static-targets';
local prometheus = 'prometheus';
local fieldColor(hex) = { mode: 'fixed', fixedColor: hex };
local dataQuery(query, index, instant) = {
  kind: 'PanelQuery',
  spec: {
    hidden: false,
    refId: ['A', 'B'][index],
    query: {
      kind: 'DataQuery',
      group: 'prometheus',
      version: 'v0',
      datasource: { name: prometheus },
      spec: {
        expr: query.expr,
        legendFormat: query.name,
        instant: instant,
        range: !instant,
        format: if instant then 'table' else 'time_series',
      },
    },
  },
};
local panel(id, title, viz, queries, unit, options, custom={}) = {
  kind: 'Panel',
  spec: {
    id: id,
    title: title,
    links: [],
    data: {
      kind: 'QueryGroup',
      spec: {
        queries: std.mapWithIndex(
          function(index, query) dataQuery(query, index, viz != 'timeseries'),
          queries
        ),
        transformations:
          if viz == 'table' then [{
            kind: 'Transformation',
            group: 'organize',
            spec: { options: { excludeByName: { Time: true, __name__: true } } },
          }]
          else [],
        queryOptions: {},
      },
    },
    vizConfig: {
      kind: 'VizConfig',
      group: viz,
      version: '',
      spec: {
        options: options,
        fieldConfig: {
          defaults: { unit: unit, custom: custom, color: fieldColor('#0072B2') },
          overrides: [
            {
              matcher: { id: 'byName', options: query.name },
              properties: [{ id: 'color', value: fieldColor(query.color) }],
            }
            for query in queries
            if viz == 'timeseries' && std.objectHas(query, 'color')
          ],
        },
      },
    },
  },
};
local item(name, x, y, width, height) = {
  kind: 'GridLayoutItem',
  spec: {
    x: x,
    y: y,
    width: width,
    height: height,
    element: { kind: 'ElementReference', name: name },
  },
};
local queries(metric) =
  if std.objectHas(metric, 'queries') then metric.queries
  else [{ name: metric.name, expr: metric.expr }];
local trend(index, metric) = panel(
  10 + 2 * index,
  metric.title,
  'timeseries',
  queries(metric),
  metric.unit,
  {
    tooltip: { mode: if std.length(queries(metric)) > 1 then 'multi' else 'single', sort: 'none' },
    legend: { showLegend: std.length(queries(metric)) > 1, displayMode: 'list', placement: 'bottom', calcs: [] },
  },
  { lineWidth: 1, fillOpacity: 0, drawStyle: 'line', showPoints: 'never' }
);
local tableQueries(metric) =
  local inputs = queries(metric);
  if std.length(inputs) == 1 then inputs
  else [{
    name: 'Failing peers',
    expr: std.join(' or ', [
      'label_replace((%s), "protocol", "%s", "", "")' % [query.expr, query.name]
      for query in inputs
    ]),
  }];
local table(index, metric) = panel(
  11 + 2 * index,
  metric.title + ' now',
  'table',
  tableQueries(metric),
  metric.unit,
  { showHeader: true }
);

function(targets) {
  apiVersion: 'dashboard.grafana.app/v2',
  kind: 'Dashboard',
  metadata: { name: id },
  spec: {
    title: 'Static build targets',
    description: 'Scrape health, traffic, and upstream peer readiness.',
    annotations: [],
    cursorSync: 'Off',
    links: [],
    preload: false,
    tags: [],
    variables: [],
    timeSettings: {
      from: 'now-1h',
      to: 'now',
      autoRefresh: '1m',
      autoRefreshIntervals: ['30s', '1m', '5m', '15m', '1h'],
      hideTimepicker: false,
      fiscalYearStartMonth: 0,
      timezone: 'utc',
    },
    elements: {
      unavailable: panel(
        1,
        'Unreachable scrape targets',
        'stat',
        [{
          name: 'Unreachable scrape targets',
          expr: 'sum(up{job=~"%s"} == bool 0)' % std.join('|', targets.jobs),
        }],
        'short',
        { colorMode: 'none', graphMode: 'none', reduceOptions: { calcs: ['lastNotNull'], values: false } }
      ),
      scrapes: panel(
        2,
        'Scrape status by instance',
        'table',
        [{
          name: 'Scrape status',
          expr: 'up{job=~"%s"}' % std.join('|', targets.jobs),
        }],
        'none',
        { showHeader: true }
      ),
    } + {
      ['trend-%d' % index]: trend(index, targets.panels[index])
      for index in std.range(0, std.length(targets.panels) - 1)
    } + {
      ['table-%d' % index]: table(index, targets.panels[index])
      for index in std.range(0, std.length(targets.panels) - 1)
    },
    layout: {
      kind: 'GridLayout',
      spec: {
        items: [
          item('unavailable', 0, 0, 6, 5),
          item('scrapes', 6, 0, 18, 5),
        ] + std.flattenArrays([
          [item('trend-%d' % index, 0, y, 16, 7), item('table-%d' % index, 16, y, 8, 7)]
          for index in std.range(0, std.length(targets.panels) - 1)
          for y in [5 + 7 * index]
        ]),
      },
    },
  },
}
