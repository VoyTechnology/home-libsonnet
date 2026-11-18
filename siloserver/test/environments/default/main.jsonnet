// Overrides: a namespace, an env var, a replaced volume, a container mixin and a pod mixin.
local m = (import '../../../main.libsonnet') {
  _config+:: {
    namespace: 'media',
    silo+: { mediaPath: '/nfs', resources+: { limits+: { memory: '8Gi' } }, storage+: { storageClassName: 'longhorn' } },
  },
  silo_env+:: { SILO_NET_TCP_CONGESTION: 'off' },
  silo_volumes+:: { media: { nfs: { server: 's1', path: '/storage' } } },
  silo_container+:: { volumeMounts+: [{ name: 'extra', mountPath: '/extra' }] },
  silo_pod_spec+:: { tolerations: [] },
};

local sts = m.siloStatefulSet;
local pod = sts.spec.template.spec;
local c = pod.containers[0];
assert sts.spec.selector.matchLabels == { 'app.kubernetes.io/name': 'silo' };
assert sts.metadata.namespace == 'media';
assert [e.name for e in c.env] == [
  'ABS_PORT',
  'JF_PORT',
  'PGID',
  'PORT',
  'PUID',
  'SECRET_KEY',
  'SILO_NET_TCP_CONGESTION',
  'TZ',
];
assert c.env[5].valueFrom.secretKeyRef == { name: 'silo-secrets', key: 'secret_key' };
assert [v.name for v in c.volumeMounts] == ['config', 'media', 'transcode', 'downloads', 'extra'];
assert c.volumeMounts[1] == { name: 'media', mountPath: '/nfs', readOnly: true };
local vol(n) = [v for v in pod.volumes if v.name == n][0];
assert vol('media') == { name: 'media', nfs: { server: 's1', path: '/storage' } };
assert c.resources == {
  requests: { memory: '2Gi', cpu: 1 },
  limits: { memory: '8Gi' },
};
assert pod.tolerations == [] && pod.terminationGracePeriodSeconds == 120;
assert sts.spec.volumeClaimTemplates[0].spec.storageClassName == 'longhorn';
assert m.siloService.spec.selector == sts.spec.selector.matchLabels;
assert [p.name for p in m.siloService.spec.ports] == ['audiobookshelf', 'http', 'jellyfin'];
m
