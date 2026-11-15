// Overrides: an extra port, an env var, a volume mounted by a container mixin and a node selector.
local m = (import '../../../main.libsonnet') {
  _config+:: { namespace: 'games', dataSize: '50Gi', storageClassName: 'longhorn' },
  minecraft_env+:: { MOTD: 'hello', TYPE: 'PAPER' },
  ports+:: { map: { port: 8100, protocol: 'TCP', serviceType: 'ClusterIP' }, bedrock: { port: 19132, protocol: 'UDP' } },
  volumes+:: { extra: { emptyDir: {} } },
  minecraft_container+:: { volumeMounts+: [{ name: 'extra', mountPath: '/extra' }] },
  pod_spec+:: { nodeSelector: { 'kubernetes.io/hostname': 'node' } },
};

local sts = m.minecraftStatefulSet;
local pod = sts.spec.template.spec;
local c = pod.containers[0];
assert std.length(pod.containers) == 2;
assert std.length([e for e in c.env if e.name == 'MOTD' && e.value == 'hello']) == 1;
assert std.length([e for e in c.env if e.name == 'TYPE']) == 1;
assert [p.name for p in c.ports] == ['bedrock', 'map', 'minecraft', 'rcon'];
assert std.objectFields(m.minecraftServices) == ['map', 'minecraft', 'rcon'];
assert m.minecraftServices.minecraft.metadata.name == 'minecraft';
assert m.minecraftServices.map.metadata.name == 'minecraft-map';
assert m.minecraftServices.minecraft.spec.selector == sts.spec.selector.matchLabels;
assert sts.spec.volumeClaimTemplates[0].spec.storageClassName == 'longhorn';
assert pod.nodeSelector['kubernetes.io/hostname'] == 'node';
assert std.length([v for v in pod.volumes if v.name == 'extra']) == 1;
m
