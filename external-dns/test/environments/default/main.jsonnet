// Renders with the default config.
local dns = import '../../../main.libsonnet';

// Every Kubernetes object, whether a top-level field or grouped in a map of them.
local objects(o) =
  if std.objectHas(o, 'kind') then [o]
  else std.flattenArrays([objects(o[f]) for f in std.objectFields(o)]);
local all = objects({ [f]: dns[f] for f in std.objectFields(dns) if f != '_config' });
local kinds = std.set([o.kind for o in all]);

assert std.length(std.objectFields(dns.externalDnsCrds)) == 2;
assert std.length(all) == 7 : std.length(all);
assert kinds == ['ClusterRole', 'ClusterRoleBinding', 'CustomResourceDefinition', 'Deployment', 'Service', 'ServiceAccount'] : kinds;
assert dns.externalDnsNamespace == {};
assert std.all([o.metadata.namespace == 'external-dns' for o in all if std.member(['Deployment', 'Service', 'ServiceAccount'], o.kind)]);
assert dns.externalDnsClusterRoleBinding.subjects[0].namespace == 'external-dns';
assert dns.externalDnsService.spec.selector == dns.externalDnsDeployment.spec.selector.matchLabels;
assert dns.externalDnsDeployment.spec.template.spec.containers[0].args == [
  '--log-level=info', '--log-format=text', '--interval=1m', '--source=service', '--source=ingress',
  '--policy=sync', '--registry=txt', '--provider=cloudflare',
];
dns
