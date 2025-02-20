@description('The location where all resources will be deployed. Default is the location of the resource group')
param location string = resourceGroup().location

@description('The name given to the virtual network')
param vnetName string

@description('The name given to the API server subnet')
param apiServerSubnetName string

@description('The name given to the cluster subnet')
param clusterSubnetName string

@description('The name given to the user-assigned identity')
param uaiName string

@description('The name of the AKS Cluster')
param aksClusterName string

@description('The name given to the NSG for the API server subnet')
param apiServerNsgName string

@description('The user object Id')
@secure()
param userObjectId string

var addressPrefix = '172.19.0.0/16'
var apiSeverSubnetPrefix = '172.19.0.0/28'
var clusterSubnetPrefix = '172.19.1.0/24'
var networkContributorRoleId = resourceId('Microsoft.Authorization/roleDefinitions', '4d97b98b-1d4f-4787-a291-c67834d212e7')
var aksClusterAdminRoleId = resourceId('Microsoft.Authorization/roleDefinitions', 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b')

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      {
        name: apiServerSubnetName
        properties: {
          addressPrefix: apiSeverSubnetPrefix
          delegations: [
            {
              name: 'aks-delegation'
              properties: {
                serviceName: 'Microsoft.ContainerService/managedClusters'
              }
            }
          ]
        }
      }
      {
        name: clusterSubnetName
        properties: {
          addressPrefix: clusterSubnetPrefix
        }
      }
    ]
  }

  resource apiSubnet 'subnets' existing = {
    name: apiServerSubnetName
  }

  resource clusterSubnet 'subnets' existing = {
    name: clusterSubnetName
  }
}

resource apiServerNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: apiServerNsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowClusterToApiServer'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          priority: 100
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '433'
            '4443'
          ]
          sourceAddressPrefix: vnet::clusterSubnet.properties.addressPrefix
          destinationAddressPrefix: apiSeverSubnetPrefix
        }
      }
      {
        name: 'AllowAzureLoadBalancerToApiServer'
        properties: {
          access: 'Allow'
          direction: 'Inbound'
          priority: 200
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '9988'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: apiSeverSubnetPrefix
        }
      }
    ]
  }
}

resource uai 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: uaiName
  location: location
}

resource aks 'Microsoft.ContainerService/managedClusters@2024-09-02-preview' = {
  name: aksClusterName
  location: location
  sku: {
    name: 'Automatic'
  }
  properties: {
    agentPoolProfiles: [
      {
        name: 'systempool'
        mode: 'System'
        count: 3
        vnetSubnetID: vnet::clusterSubnet.id
      }
    ]
    apiServerAccessProfile: {
      subnetId: vnet::apiSubnet.id
    }
    networkProfile: {
      outboundType: 'loadBalancer'
    }
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uai.id}': {}
    }
  }
}

// Role Assignments
resource networkContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, vnet.id, networkContributorRoleId)
  scope: vnet
  properties: {
    principalId: uai.properties.principalId 
    roleDefinitionId: networkContributorRoleId
    principalType: 'ServicePrincipal'
  }
}

resource aksClusterAdminRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroup().id, userObjectId, 'Azure Kubernetes Service RBAC Cluster Admin')
  scope: aks
  properties: {
    principalId: userObjectId
    principalType: 'User'
    roleDefinitionId: aksClusterAdminRoleId
  }
}
