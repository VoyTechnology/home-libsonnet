// The Gateway API CRDs of one upstream release (see generate.sh and crds/VERSION), as a map of
// CustomResourceDefinition objects. They are cluster scoped, so there is no namespace config.
{
  gatewayApiCrds: import 'crds/main.libsonnet',
}
