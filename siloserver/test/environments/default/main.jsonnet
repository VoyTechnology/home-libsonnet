// Overrides: an env var, a replaced volume, a container mixin and a pod mixin.
local k = import 'github.com/jsonnet-libs/k8s-libsonnet/1.35/main.libsonnet';
local container = k.core.v1.container;
local volume = k.core.v1.volume;

local m = (import '../../../main.libsonnet') {
  _config+:: {
    silo+: { storage+: { storageClassName: 'longhorn' } },
  },
  silo_env+:: { SILO_NET_TCP_CONGESTION: 'off' },
  silo_volumes+:: {
    media: volume.withName('media') + volume.nfs.withServer('s1') + volume.nfs.withPath('/storage'),
  },
  silo_container+:: container.resources.withLimits({ memory: '8Gi' }) + { volumeMounts+: [{ name: 'extra', mountPath: '/extra' }] },
  silo_pod_spec+:: { tolerations: [] },
};

local sts = m.silo_statefulset;
local pod = sts.spec.template.spec;
local c = pod.containers[0];
assert sts.spec.selector.matchLabels == { 'app.kubernetes.io/name': 'silo' };
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
assert c.volumeMounts[1] == { name: 'media', mountPath: '/mnt/media', readOnly: true };
local vol(n) = [v for v in pod.volumes if v.name == n][0];
assert vol('media') == { name: 'media', nfs: { server: 's1', path: '/storage' } };
assert c.resources == {
  requests: { cpu: '1', memory: '2Gi' },
  limits: { memory: '8Gi' },
};
assert pod.tolerations == [] && pod.terminationGracePeriodSeconds == 120;
assert sts.spec.volumeClaimTemplates[0].spec.storageClassName == 'longhorn';
assert m.silo_service.spec.selector == sts.spec.selector.matchLabels;
assert [p.name for p in m.silo_service.spec.ports] == ['audiobookshelf', 'http', 'jellyfin'];
m
