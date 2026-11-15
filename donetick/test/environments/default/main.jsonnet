// Overrides: a namespace, an env var, a config section, a replaced volume and a container mixin.
local m = (import '../../../main.libsonnet') {
  _config+:: { namespace: 'chores', host: 'chores.example.com', storage+: { storageClassName: 'fast' } },
  donetick_env+:: { DT_TELEGRAM_TOKEN: { secretKeyRef: { name: 'x', key: 'y' } } },
  donetick_config+:: { logging+: { level: 'debug' } },
  volumes+:: { data: { emptyDir: {} } },
  donetick_container+:: { volumeMounts+: [{ name: 'extra', mountPath: '/extra' }] },
};

local dep = m.donetickDeployment;
local pod = dep.spec.template.spec;
local c = pod.containers[0];
assert dep.spec.selector.matchLabels == { 'app.kubernetes.io/name': 'donetick' };
assert dep.spec.strategy.type == 'Recreate';
assert [e.name for e in c.env] == ['DT_JWT_SECRET', 'DT_SQLITE_PATH', 'DT_TELEGRAM_TOKEN'];
assert [v.name for v in c.volumeMounts] == ['config', 'data', 'extra'];
local vol(n) = [v for v in pod.volumes if v.name == n][0];
assert vol('data') == { name: 'data', emptyDir: {} };
assert vol('config').configMap.name == m.donetickConfigMap.metadata.name;
assert std.length(std.findSubstr('debug', m.donetickConfigMap.data['selfhosted.yaml'])) == 1;
assert m.donetickPvc.spec.storageClassName == 'fast';
assert m.donetickService.spec.selector == dep.spec.selector.matchLabels;
m
