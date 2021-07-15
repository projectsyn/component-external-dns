// main template for external-dns
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.external_dns;

local namespace = kube.Namespace(params.namespace);

local service_account = kube.ServiceAccount('external-dns');

local cluster_role = kube.ClusterRole('external-dns') {
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


local cluster_role_binding = kube.ClusterRoleBinding('external-dns');


// Provider specific configuration

local azure_secret = kube.Secret('azure-config-file') {
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
    labels {
      'app.kubernetes.io/name': 'external-dns',
      'app.kubernetes.io/managed-by': 'syn',
    },
  },
  spec+: {
    template+: {
      containers_+: {
        'external-dns': kubeContainer('external-dns') {
          image: params.images.external-dns.registry + '/' + params.images.external-dns.image + ':' + params.images.external-dns.tag,
          imagePullPolicy: 'Always'
          args: [
            "--provider=" + params.provider,
            "--source=ingress",
            [if params.config.domain-filter != "" then "--domain-filter=" + params.config.domain-filter ,]
            ""
          ],
        },
      
      },
      serviceAccountName: service_account.metadata.name
    },
  
  },

};

// Define outputs below
{
  '00_namespace': namespace,
  '09_serviceaccount': service_account,
  '10_cluster_role': cluster_role,
  '11_cluster_role_binding': cluster_role_binding,
  '12_deployment': deployment
  [if params.provider == "azure"] '20_azure_secret', azure_secret
}
