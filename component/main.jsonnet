// main template for external-dns
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.external_dns;

local namespace = kube.Namespace(params.namespace);

local serviceaccount = kube.ServiceAccount('external-dns') {
  metadata+: {
    namespace: params.namespace,
  },
};


local clusterrole = kube.ClusterRole('external-dns') {
  rules: [
    {
      apiGroups: [ '' ],
      resources: [ 'services', 'endpoints', 'pods' ],
      verbs: [ 'get', 'watch', 'list' ],
    },
    {
      apiGroups: [ 'extensions', 'networking.k8s.io' ],
      resources: [ 'ingresses' ],
      verbs: [ 'get', 'watch', 'list' ],
    },
    {
      apiGroups: [ '' ],
      resources: [ 'nodes' ],
      verbs: [ 'list' ],
    },
  ],
};


local clusterrolebinding = kube.ClusterRoleBinding('external-dns') {
  roleRef_: clusterrolebinding,
  subjects_: [ serviceaccount ],
};

// https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/azure.md#creating-configuration-file
local azuresecret = kube.Secret('azure-config-file') {
  metadata+: {
    namespace: params.namespace,
  },
  stringData+: {
    'azure.json': '{\n      tenantId: ' + params.providerConfig.azure.authentication.tenantId + ',\n      subscriptionId: ' + params.providerConfig.azure.authentication.subscriptionId + ',\n      resourceGroup: ' + params.providerConfig.azure.authentication.resourceGroup + ',\n      aadClientId: ' + params.providerConfig.azure.authentication.aadClientId + ',\n      aadClientSecret: ' + params.providerConfig.azure.authentication.aadClientSecret + '\n    }',
  },
};


local mountVolumes =
  if params.provider == 'azure' then
    [
      {
        name: 'azure-config-file',
        mountPath: '/etc/kubernetes',
        readOnly: true,
      },
    ]
  else [];

local volumes =
  if params.provider == 'azure' then
    [
      {
        name: 'azure-config-file',
        secret: {
          secretName: azuresecret.metadata.name,
          items: [
            {
              key: 'externaldns-config.json',
              path: 'azure.json',
            },
          ],
        },
      },
    ]
  else [];


local deployment = kube.Deployment('external-dns') {
  metadata+: {
    namespace: params.namespace,
    labels: {
      'app.kubernetes.io/name': 'external-dns',
      'app.kubernetes.io/managed-by': 'syn',
    },
  },
  spec+: {
    template+: {
      spec+: {
        containers_+: {
          'external-dns': kube.Container('external-dns') {
            image: params.images.externaldns.registry + '/' + params.images.externaldns.image + ':' + params.images.externaldns.tag,
            imagePullPolicy: 'Always',
            args: std.prune([
              '--provider=' + params.provider,
              '--source=ingress',
              if params.config.domainFilter != '' then '--domain-filter=' + params.config.domainFilter else null,
              if params.config.txtPrefix != '' then '--txt-record=' + params.config.txtPrefix else null,
              if params.provider == 'azure' && params.providerConfig.azure.resourceGroup != '' then '--azure-resource-group=' + params.providerConfig.azure.resourceGroup else null,
            ]),
            volumeMounts: mountVolumes,
          },
        },
        serviceAccountName: serviceaccount.metadata.name,
        volumes: volumes,
      },
    },
  },
};

// Define outputs below
{
  '00_namespace': namespace,
  '09_serviceaccount': serviceaccount,
  '10_cluster_role': clusterrole,
  '11_cluster_role_binding': clusterrolebinding,
  '12_deployment': deployment,
  [if params.provider == 'azure' then '20_azure_secret']: azuresecret,
}
