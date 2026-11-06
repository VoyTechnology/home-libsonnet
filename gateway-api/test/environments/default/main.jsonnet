// Renders with the default config.
local ga = import '../../../main.libsonnet';

assert std.length(std.objectFields(ga.gatewayApiCrds)) == 13 : std.length(std.objectFields(ga.gatewayApiCrds));
assert ga.gatewayApiCrds['gateways.gateway.networking.k8s.io'].kind == 'CustomResourceDefinition';
ga
