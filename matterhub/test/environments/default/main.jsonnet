// Overrides: an env var, a container mixin, a node and a pod spec mixin.
local m = (import '../../../main.libsonnet') {
  _config+:: { nodeName: 'node1', secretName: 'ha', logLevel: 'debug' },
  matterhub_env+:: { HAMH_MDNS_NETWORK_INTERFACE: 'eth0' },
  matterhub_container+:: { resources: { limits: { memory: '512Mi' } } },
  pod_spec+:: { tolerations: [{ operator: 'Exists' }] },
};

local sts = m.matterhubStatefulSet;
local pod = sts.spec.template.spec;
local c = pod.containers[0];
local env(n) = [e for e in c.env if e.name == n][0];
assert sts.metadata.name == 'homeassistant-matterhub';
assert sts.spec.selector.matchLabels == { 'app.kubernetes.io/name': 'homeassistant-matterhub' };
assert sts.spec.volumeClaimTemplates[0].metadata.name == 'data';
assert env('HAMH_HOME_ASSISTANT_URL').valueFrom.secretKeyRef == { name: 'ha', key: 'url' };
assert env('HAMH_LOG_LEVEL').value == 'debug';
assert env('HAMH_MDNS_NETWORK_INTERFACE').value == 'eth0';
assert c.resources.limits.memory == '512Mi';
assert pod.nodeSelector == { 'kubernetes.io/hostname': 'node1' };
assert pod.tolerations == [{ operator: 'Exists' }];
assert m.matterhubService.spec.selector == sts.spec.selector.matchLabels;
m
