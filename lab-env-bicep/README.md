# Setting up an AKS lab environment with Bicep

This sample shows you how to build an AKS lab environment with Bicep. This sample was inspired by this [AKS Labs](https://azure-samples.github.io/aks-labs/docs/getting-started/setting-up-lab-environment) provided by the AKS team!

In this sample, we're going to build the lab environment step by step using Bicep. Wherever possible, **we will avoid creating resources using the AZ CLI**, and instead take an opinionated approach to defining our infrastructure **declaratively** with Bicep instead. We will still need to use the AZ CLI to do some tasks, such as deploying our resources.

If you want to follow along with this sample, you'll need the following tools and services:

- An Azure Subscription
- A code editor - I'm using Visual Studio Code!
- The AZ CLI
- kubectl
- A bash shell (VS Code has an integrated terminal, Windows terminal is also pretty neat)

Once you have these tools, or if you've already installed them, let's start to build our AKS lab environment with Bicep!

## Creating our resources

Before we do anything, use the AZ CLI to login to your Azure Subscription. To do this, open up a `bash` terminal and run the following:

```bash
$ az login --use-device-code
```

For our AKS lab, we'll create the following resources:

- An Azure Kubernetes Service cluster (I hope that was obvious....)
- Azure Log Analytics
- Azure Managed Prometheus
- Azure Managed Grafana
- Azure Key Vault
- Azure Container Registry

We'll also need a resource group to deploy our resources to. For this, we'll use the AZ CLI:

```bash
$ export RG_NAME='<RG-NAME>'
$ export LOCATION='<LOCATION>'
```

For `RG_NAME`, give your resource group a name, and for `LOCATION` choose an Azure Region that supports availability zones. Because I live in a land Down Under, I've chosen `australiaeast`. [Choose a region](https://learn.microsoft.com/azure/aks/availability-zones-overview?WT.mc_id=MVP_400037) that's close to you.

Once you've set those variable, use the AZ CLI to create your resource group:

```bash
$ az group create --name $RG_NAME --location $LOCATION
```

Your output should look like this:

```bash
{
  "id": "/subscriptions/<subscription-id>/resourceGroups/<RG-NAME>",
  "location": "<LOCATION>",
  "managedBy": null,
  "name": "<RG-NAME>",
  "properties": {
    "provisioningState": "Succeeded"
  },
  "tags": null,
  "type": "Microsoft.Resources/resourceGroups"
}
```

I've omitted my details for clarity.

With our resource group created, let's start to define our resources using Bicep. To keep things simple for now, we'll have a `main.bicep` file (where we will define our template) and a `main.bicepparam` file (where we will define our parameters that we pass to our template). 

We won't go into too much detail about [Bicep](https://learn.microsoft.com/azure/azure-resource-manager/bicep/file?WT.mc_id=MVP_400037) or [Bicep parameters](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/parameters?WT.mc_id=MVP_400037), but I'd recommend clicking those two links if you want to learn more about how it all works if you don't know already.

## Design choices

When deploying Azure Kubernetes Service in the real world, there'll be a whole bunch of different scenarios and edge-cases that you'll have to take into account. 

For the purposes of our lab environment, I've taken the following design decisions:

1. **Enable AKS Monitoring and Logging**

As with all compute platforms, it's vital that you turn on logging and monitoring to ensure that you can maintain the health and performance of your AKS cluster. AKS has a bunch of integrations with Azure Monitor that we can use for logs and metrics, such as:

- Container Insights, which sends container logs to Log Analytics workspaces.
- Azure Monitor managed service, which sends performance metrics from nodes and pools.
- Azure Managed Grafana, which allows us to visualize those performance metrics sent by Prometheus.

For our lab, we're just going to be plugging the components together. Creating various dashboards in Bicep is a PROCESS which will just add too much complexity to what we're trying to do here. But it's worth setting up the integrations at least for our lab environment.

2. **Enable Managed Identities and RBAC for authentication over keys and SSH**

Even though we're setting this AKS cluster for our own personal lab environment, it's a good habit to use RBAC over keys and SSH to access your AKS cluster and various other Azure resources. 

Creating role assignments in Bicep is pretty straightforward, and we'll need to assign our identity in Azure certain roles over our resources, as well as give our Managed Identity that we provision roles over other resources.

Disabling SSH access to our AKS nodes will also help prevent unauthorized access to our clusters.

3. **Use Azure CNI Overlay with Cilium networking**

Just like the AKS lab, I'm going to use Azure CNI Overlay with Cilium for our networking. This will give us the most advanced networking features available in AKS, as well as give us flexibility as to how IP addresses are assigned to Pods.

There's a lot to networking in AKS, and I'm planning on creating some specific AKS networking content in the future to cover this. If you're interested in learning more about networking in AKS by yourself, check out [Networking concepts for applications in Azure Kubernetes Service (AKS)](https://learn.microsoft.com/azure/aks/concepts-network?WT.mc_id=MVP_400037)

Bear in mind, there' s a whole bunch of "best practices" that we're not implementing here. Like the lab, this cluster will be accessible from the public internet. In production scenarios, it's better to create a private cluster. The purpose of this is to just keep things simple for our own personal lab environment.

With all that in mind, let's start writing some Bicep code!

### Log Analytics workspace

Let's start by creating a Log Analytics workspace! To do so, we can define our Log Analytics workspace resource using the following Bicep code:

```bicep
@description('The name given to the Log Analytics workspace')
param logAnalyticsName string

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
```

This block defines a Log Analytics workspace that will be deployed to the same region as our resource group. We use the `param logAnalytics` to provide our resource with a name (I'll cover the parameters file later). We also give it a SKU of `PerGB2018` and enabled a `SystemAssigned` identity.

### Azure Managed Prometheus

We can define a Azure Managed Prometheus resource with just a couple of lines of Bicep using a `Microsoft.Monitor/account` resource. We also define a parameter for `prometheusName` so we can give a name to the resource.

```bicep
@description('The name given to the Azure Managed Prometheus workspace')
param prometheusName string

resource prometheusWorkspace 'Microsoft.Monitor/accounts@2023-04-03' = {
  name: prometheusName
  location: location
  tags: tags
}
```

### Azure Managed Grafana

Creating a Managed Grafana resource is a little bit more involved. We want to configure an integration between our Grafana resource with our managed Prometheus resource so we can visualize performance metrics emitted by Prometheus.

This is done in the `properties.grafanaIntegrations.azureMonitorWorkspaceIntegrations` block. In this block, we pass through the `Id` of our Prometheus resource block so we can integrate it with the Grafana dashboard:

```bicep
@description('The name given to the Grafana Dashboard')
param grafanaName string

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

resource grafanaAdminRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroup().id, userObjectId, 'Grafana Admin')
  scope: grafanaDashboard
  properties: {
    principalId: userObjectId
    principalType: 'User'
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '22926164-76b3-42b3-bc55-97df8dab3e41')
  }
}
```

We also create a role assignment, granting ourselves the `Grafana Admin` role, through the `userObjectId` parameter. I'll show you how we can retrieve the value for this parameter using the AZ CLI later.

### User-Assigned Managed Identity

Speaking of identities, we need to create an identity for password authentication to Azure Services. For this, we'll create a user-assigned managed identity resource, and use that to assign permissions to. 

All we need is to define a parameter for `managedIdentityName` (which will be the name of the managed identity), and a resource block of type `Microsoft.ManagedIdentity/userAssignedIdentities`:

```bicep
@description('The name given to the User-Assigned Managed Identity')
param managedIdentityName string

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
}
```

### Azure Key Vault

As part of your AKS lab environment, we should deploy an Azure Key Vault to manage secrets. We'll also need to assign some roles to both ourselves, and our managed identity.

For the Key Vault, we can enable RBAC authorization using the `enableRbacAuthorization` property.

For role assignments, we assign ourselves the `Key Vault Administrator` role by passing in our `userObjectId` and creating a role assignment of `User` principal type. We assign our managed identity two roles; the `Key Vault Secrets User` and `Key Vault Certificate User` roles.

```bicep
@description('The name given to the Key Vault')
param keyVaultName string

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
```

### Azure Container Registry

It's also handy to have our own private container registry as part of our lab environment so that we can get into the habit of building, storing, and managing our container images in a private registry.

[Azure Container Registry](https://learn.microsoft.com/azure/container-registry/?WT.mc_id=MVP_400037) allows us to build, store, and manage container images and artifacts in a private registry for all types of container deployments.

To create one in Bicep, we can define a resource block of type `Microsoft.ContainerRegistry/registries`, give it a name with the `acrName` parameter, and assign it a `SystemAssigned` identity.

I'm also assigning two roles for my identity; `AcrPull` and `AcrPush`. This will allow me to push and pull images from my private container registry:

```bicep
@description('The name given to the Azure Container Registry')
param acrName string

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
```

### And Finally, our Azure Kubernetes Cluster!

It's now time to create our AKS cluster! When we deploy an AKS cluster, there's a couple of things we have to consider before doing so.

1. **How big should our cluster be?**

The size of your cluster depends on what you're going to run on AKS. This includes the number of pods you plan to run, which determines the amount of nodes you need to run (along with how much CPU and memory required for each pod). As time goes by, you can adjust the number of nodes your cluster has, along with the size of them.

Nodes for AKS are essentially Virtual Machines, so it's a good idea to familiarize yourself with what types of [virtual machines are available to you](https://learn.microsoft.com/azure/virtual-machines/sizes/overview?tabs=breakdownseries%2Cgeneralsizelist%2Ccomputesizelist%2Cmemorysizelist%2Cstoragesizelist%2Cgpusizelist%2Cfpgasizelist%2Chpcsizelist&WT.mc_id=MVP_400037).

2. **System vs User Node Pools**

It's best to create separate system and user node pools when creating an AKS cluster. This allows us to manage system and user workloads independently.

System node pools host pods that implement the Kubernetes Control Plane (such as the *kube-apiserver*, *coredns* etc.).

User node pools are pools of compute that we can create to host our workloads. User node pools can be created with different settings (things like VM sizes, node counts etc.) than our System node pools.

3. **Availability Zones!**

We can distribute the control plane of our AKS cluster using [availability zones](https://learn.microsoft.com/azure/aks/availability-zones-overview?WT.mc_id=MVP_400037). Doing this ensures high availability for our control plane.

Here's the Bicep that we need to define our AKS cluster:

```bicep
@description('The name given to the AKS Cluster')
param aksName string

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
```

There's a lot going on here, so let's break it down:

- We define another parameter to name our cluster: `aksName`
- We deploy the cluster to the same Azure region as our resource group.
- We create both a `systempool` and a `userpool`. We assign 3 nodes to our `systempool` and 1 node to our `userpool`.
- We add a taint to our `systempool` to prevent user workloads being provisioned on it using the `nodeTaints` property. We can use `kubectl taint` command to do this, but since AKS can scale node pools, we should use do this to ensure that the taint is applied to all nodes in the pool.
- We configure the Azure CNI Overlay for Cilium using the `networkProfile`. `cilium` is defined so that we can use it as the network dataplane, and we also provision a `standard` load balancer.
- `enableRBAC` is set to true, enabling RBAC for the cluster.
- We configure two add-ons for our cluster; `azureKeyVaultSecretsProvider` and `omsAgent`. For our `omsAgent`, we use the `id` property of our Log Analytics workspace to configure the `omsAgent` to use that workspace.
- Finally, the `azureMonitorProfile` section enables metrics monitoring with `kubeStateMetrics` configured to allow all metric annotations and labels.

### Supplying values to our Parameters in our `main.bicepparam` file

We have a bunch of parameters that we need to supply with values. You can do this inline using the AZ CLI (which is handy in some scenarios, and we'll actually do this later), but it's better to use a parameters file.

For Bicep templates, you can use a JSON parameters file (which is a pretty tedious way of doing it), or using a Bicep parameters file with a `.bicepparam` file extension. Using parameter files allow us to be flexible with what we supply as parameters, as the values can change over different environments, or different users.

Here are the contents of my `main.bicepparam` file. (If you're following along, change the values for your deployment):

```bicep
using 'main.bicep'

param logAnalyticsName = 'law-wv-prod-001'
param prometheusName = 'prom-wv-prod-001'
param grafanaName = 'graf-wv-prod-001'
param keyVaultName = 'kv-wv-prod-001'
param managedIdentityName = 'uai-wv-prod-001'
param acrName = 'acrwvprod001'
param aksName = 'aks-wv-prod-001'
param userObjectId = ''
```

We apply the `using` statement to let our parameters file know which parameters we need to supply values to. You can use Bicep template, JSON templates, and template specifications. Since we just have one `bicep` file to keep things simple, we just set the using statement to use our Bicep template.

To get the value of your `userObjectId`, we can run the following AZ CLI command:

```bash
$ export USER_ID="$(az ad signed-in-user show --query id -o tsv)"
```

We're saving this to a variable in our bash terminal so that we can use it when deploying the template, which we'll do now.

## Deploying our Lab environment

To deploy our resources to our resource group, run the following AZ CLI command:

```bash
$ az deployment group create --resource-group $RG_NAME --template-file main.bicep --parameters main.bicepparam userObjectId=$USER_ID
```

## Deploying the AKS Store Demo App to our Lab environment

Now that we have our lab environment set up, let's deploy an application to it. For this, I'm going to use (or steal, depending on your viewpoint) the [AKS Store Demo application](https://github.com/Azure-Samples/aks-store-demo) provided by the AKS team.

This is the high-level architecture of that application:

![The image is a system architecture diagram for a microservices-based e-commerce application. It shows customers interacting with a Vue.js-based store-front, which serves as the main interface. The store-front communicates with two backend services: an order-service built with Node.js and a product-service built with Rust. The order-service processes customer orders and sends them to an order queue powered by RabbitMQ for asynchronous handling. Arrows in the diagram illustrate the data flow between these components, highlighting the interactions between the front-end, backend services, and the message queue.](https://azure-samples.github.io/aks-labs/assets/images/aks-store-architecture-778ef23874e9ffd101bb1ff5429a3c4e.png)

First, let's use `kubectl` to create a namespace for the store application:

```bash
$ kubectl create namespace pets
```

Within the sample repository, there's a yaml file that'll create all the Kubernetes resources we need for our application. We can apply this using `kubectl apply`

```bash
$ kubectl apply -f https://raw.githubusercontent.com/Azure-Samples/aks-store-demo/refs/heads/main/aks-store-quickstart.yaml -n pets
```

Give it a moment, and all the required resources should be installed on our cluster. To verify this, run the following command:

```bash
$ kubectl get all -n pets
```

The application uses a LoadBalancer service to allow access to the application's UI. Once everything is deployed, we can retrieve the IP address of our storefront service with the following command:

```bash
$ kubectl get svc store-front -n pets
```

Hit the **EXTERNAL-IP** address of the store-front service, and you should be able to access the application:

![](https://azure-samples.github.io/aks-labs/assets/images/acns-pets-app-637000317205e6726da11d85b4664781.png)

## Conclusion

Congratulations! You've successfully deployed your own AKS lab environment using Bicep code and deployed a sample application to it.