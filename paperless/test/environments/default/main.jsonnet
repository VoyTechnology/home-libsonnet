// Overrides: hostPath storage on a node, an env var, a replaced volume and a container mixin.
local m = (import '../../../main.libsonnet') {
  _config+:: { namespace: 'docs', url: 'https://docs.example.com', hostPath: '/storage/docs', nodeName: 'node' },
  paperless_env+:: { PAPERLESS_OCR_LANGUAGE: 'eng' },
  volumes+:: { export: { emptyDir: {} } },
  paperless_container+:: { volumeMounts+: [{ name: 'extra', mountPath: '/extra' }] },
};

local dep = m.paperlessDeployment;
local pod = dep.spec.template.spec;
local c = pod.containers[0];
assert dep.spec.selector.matchLabels == { app: 'paperless' };
assert dep.spec.strategy.type == 'Recreate';
assert [x.name for x in pod.containers] == ['paperless', 'redis'];
assert [e.name for e in c.env] == ['PAPERLESS_OCR_LANGUAGE', 'PAPERLESS_REDIS', 'PAPERLESS_SECRET_KEY', 'PAPERLESS_URL'];
assert pod.nodeSelector['kubernetes.io/hostname'] == 'node';
local vol(n) = [v for v in pod.volumes if v.name == n][0];
assert vol('consume').hostPath.path == '/storage/docs/consume';
assert vol('export') == { name: 'export', emptyDir: {} };
assert m.paperlessService.spec.selector == dep.spec.selector.matchLabels;
m
