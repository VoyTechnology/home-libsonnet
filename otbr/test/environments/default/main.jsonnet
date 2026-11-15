// Overrides: an env var, a container mixin, a storage class and a pod spec mixin.
local m = (import '../../../main.libsonnet') {
  _config+:: {
    nodeName: 'node1',
    threadDongle: '/dev/ttyACM0',
    networkInterface: 'eth0',
    dataStorageClass: 'fast',
  },
  otbr_env+:: { BAUDRATE: '115200' },
  otbr_container+:: { volumeMounts+: [{ name: 'extra', mountPath: '/extra' }] },
  pod_spec+:: { tolerations: [{ operator: 'Exists' }] },
};

local sts = m.otbrStatefulSet;
local pod = sts.spec.template.spec;
local c = pod.containers[0];
assert sts.spec.selector.matchLabels == { app: 'otbr', name: 'otbr' };
assert sts.spec.volumeClaimTemplates[0].metadata.name == 'data';
assert sts.spec.volumeClaimTemplates[0].spec.storageClassName == 'fast';
assert [e.name for e in c.env] == std.sort([e.name for e in c.env]);
assert [e.value for e in c.env if e.name == 'BAUDRATE'] == ['115200'];
assert [e.value for e in c.env if e.name == 'DEVICE'] == ['/dev/ttyACM0'];
assert [v.name for v in c.volumeMounts] == ['thread-dongle', 'tun', 'data', 'extra'];
assert pod.nodeSelector == { 'kubernetes.io/hostname': 'node1' };
assert pod.tolerations == [{ operator: 'Exists' }];
assert m.otbrService.spec.selector == { app: 'otbr' };
m
