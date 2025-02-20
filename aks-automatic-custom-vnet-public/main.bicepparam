using 'main.bicep'

param aksClusterName = 'prod-wv-aks-auto-001'
param vnetName = 'vnet-wv-001'
param apiServerSubnetName = 'apiServerSubnet'
param clusterSubnetName = 'clusterSubnet'
param uaiName = 'uai-wv-001'
param apiServerNsgName = 'nsg-wv-apiserver-001'
param userObjectId = ''
