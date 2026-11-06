// Overrides: another namespace and image, no CRDs, config knobs and a container mixin.
local dns = (import '../../../main.libsonnet') {
  _config+:: {
    namespace: 'dns',
    createNamespace: true,
    installCRDs: false,
    sources: ['service', 'gateway-httproute'],
    policy: 'upsert-only',
    annotationFilter: 'dns.kubernetes.io/exclude notin (true)',
    extraArgs: ['--txt-owner-id=bet1'],
    env: [{ name: 'CF_API_TOKEN', valueFrom: { secretKeyRef: { name: 'cloudflare-secret', key: 'token' } } }],
    resources: { requests: { cpu: '10m' } },
    nodeSelector: { role: 'infra' },
  },
  _images+:: { externalDns: 'registry.k8s.io/external-dns/external-dns:v0.24.0' },
  external_dns_container+:: { args+: ['--log-level=debug'] },
};

local deployment = dns.externalDnsDeployment;
local container = deployment.spec.template.spec.containers[0];
assert dns.externalDnsCrds == {};
assert dns.externalDnsNamespace.metadata.name == 'dns';
assert deployment.metadata.namespace == 'dns';
assert deployment.spec.template.spec.nodeSelector == { role: 'infra' };
assert container.image == 'registry.k8s.io/external-dns/external-dns:v0.24.0';
assert container.resources.requests.cpu == '10m';
assert container.env[0].name == 'CF_API_TOKEN';
assert std.member(container.args, '--source=gateway-httproute');
assert !std.member(container.args, '--source=ingress');
assert std.member(container.args, '--policy=upsert-only');
assert std.member(container.args, '--annotation-filter=dns.kubernetes.io/exclude notin (true)');
assert std.member(container.args, '--txt-owner-id=bet1');
assert std.member(container.args, '--log-level=debug');
assert dns.externalDnsClusterRoleBinding.subjects[0].namespace == 'dns';
dns
