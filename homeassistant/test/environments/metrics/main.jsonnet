local ha = (import '../../../main.libsonnet') + { _config+:: { metricsEnabled: true } };
local ep = ha.haServiceMonitor.spec.endpoints[0];

assert ha.haServiceMonitor.kind == 'ServiceMonitor';
assert !std.objectHas(ep, 'bearerTokenSecret');
ha
