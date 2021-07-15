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
    apiGroups: [''],
    resources: ['services','endpoints','pods'],
    verbs: ['get','watch','list'],
   },
   {
    apiGroups: ['extensions','networking.k8s.io'],
    resources: ['ingresses'] ,
    verbs: ['get','watch','list'],
   },
   {
    apiGroups: [''],
    resources: ['nodes'],
    verbs: ['list'],
   },
  ],
};


local clusterrolebinding = kube.ClusterRoleBinding('external-dns') {
  roleRef_: clusterrolebinding,
  subjects_: [serviceaccount],
};

// https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/azure.md#creating-configuration-file
local azuresecret = kube.Secret('azure-config-file') {
  metadata+: {
    namespace: params.namespace
  },
  stringData+: {
    "azure.json": {
      tenantId: params.providerConfig.azure.authentication.tenantId,
      subscriptionId: params.providerConfig.azure.authentication.subscriptionId,
      resourceGroup: params.providerConfig.azure.authentication.resourceGroup,
      aadClientId: params.providerConfig.azure.authentication.aadClientId,
      aadClientSecret: params.providerConfig.azure.authentication.aadClientSecret,
    },
  },
};

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
            args: [
              "--provider=" + params.provider,
              "--source=ingress",
              if params.config.domainFilter != "" then "--domain-filter=" + params.config.domainFilter,
              if params.config.txtPrefix != "" then "--txt-record=" + params.config.txtPrefix,
            ],
          },
        },
      },
      serviceAccountName: serviceaccount.metadata.name,
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
  [if params.provider == "azure" then '20_azure_secret']: azuresecret
}
