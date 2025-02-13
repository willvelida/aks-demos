@description('The region where all resources will be deployed. Default is the location of the resource group')
param location string = resourceGroup().location

@description('The user object id for the cluster admin')
@secure()
param userObjectId string

@description('The name given to the Log Analytics workspace')
param logAnalyticsName string

@description('The name given to the Azure Managed Prometheus workspace')
param prometheusName string

@description('The name given to the Grafana Dashboard')
param grafanaName string

@description('The name given to the Key Vault')
param keyVaultName string

@description('The name given to the User-Assigned Managed Identity')
param managedIdentityName string

@description('The name given to the Azure Container Registry')
param acrName string

@description('The name given to the AKS Cluster')
param aksName string

@description('The tags applied to all resources')
param tags object = {
  ApplicationName: 'lab-env-bicep'
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource prometheusWorkspace 'Microsoft.Monitor/accounts@2023-04-03' = {
  name: prometheusName
  location: location
  tags: tags
}

resource grafanaDashboard 'Microsoft.Dashboard/grafana@2023-09-01' = {
  name: grafanaName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    grafanaIntegrations: {
      azureMonitorWorkspaceIntegrations: [
        {
          azureMonitorWorkspaceResourceId: prometheusWorkspace.id
        }
      ]
    }
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'standard'
      family: 'A'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
  }
}

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource aks 'Microsoft.ContainerService/managedClusters@2024-09-01' = {
  name: aksName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Base'
    tier: 'Standard'
  }
  properties: {
    dnsPrefix: 'aksdns'
    agentPoolProfiles: [
      {
        name: 'systempool'
        count: 3
        vmSize: 'Standard_DS2_v2'
        osType: 'Linux'
        osSKU: 'AzureLinux'
        mode: 'System'
        availabilityZones: [
          '1'
          '2'
          '3'
        ]
        nodeTaints: [
          'CriticalAddonsOnly=true:NoSchedule'
        ]
      }
      {
        name: 'userpool'
        count: 1
        vmSize: 'Standard_DS2_v2'
        availabilityZones: [
          '1'
          '2'
          '3'
        ]
        mode: 'User'
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkDataplane: 'cilium'
      loadBalancerSku: 'standard'
    }
    enableRBAC: true
    addonProfiles: {
      azureKeyvaultSecretsProvider: {
        enabled: true
      }
      omsAgent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalytics.id
        }
      }
    }
    azureMonitorProfile: {
      metrics: {
        enabled: true
        kubeStateMetrics: {
          metricAnnotationsAllowList: '*'
          metricLabelsAllowlist: '*'
        }
      }     
    }
  }
}

// ROLE ASSIGNMENTS
resource grafanaAdminRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroup().id, userObjectId, 'Grafana Admin')
  scope: grafanaDashboard
  properties: {
    principalId: userObjectId
    principalType: 'User'
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '22926164-76b3-42b3-bc55-97df8dab3e41')
  }
}

resource keyVaultSecretUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroup().id, managedIdentity.id, 'Key Vault Secrets User')
  scope: keyVault
  properties: {
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
  }
}

resource keyVaultCertificateUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroup().id, managedIdentity.id, 'Key Vault Certificate User')
  scope: keyVault
  properties: {
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'db79e9a7-68ee-4b58-9aeb-b90e7c24fcba')
  }
}

resource keyVaultAdminRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroup().id, userObjectId, 'Key Vault Administrator')
  scope: keyVault
  properties: {
    principalId: userObjectId
    principalType: 'User'
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '00482a5a-887f-4fb3-b363-3b7fe8e74483')
  }
}

resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroup().id, userObjectId, 'AcrPull')
  scope: acr
  properties: {
    principalId: userObjectId
    principalType: 'User' 
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
  }
}

resource acrPushRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroup().id, userObjectId, 'AcrPush')
  scope: acr
  properties: {
    principalId: userObjectId
    principalType: 'User'
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '8311e382-0749-4cb8-b61a-304f252e45ec')
  }
}
