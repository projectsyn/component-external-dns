local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.external_dns;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('external-dns', params.namespace);

{
  'external-dns': app,
}
