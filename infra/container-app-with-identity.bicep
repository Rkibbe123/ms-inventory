// Updated Bicep template with Managed Identity for secure Azure authentication
// This template adds managed identity and RBAC permissions for ARI

@description('The name of the Container App')
param containerAppName string = 'azure-resource-inventory'

@description('The name of the Container Apps environment')
param environmentName string = 'ari-inventory-env'

@description('The Azure Container Registry name')
param acrName string = 'rkazureinventory'

@description('The container image name and tag')
param imageName string = 'azure-resource-inventory:latest'

@description('The location for all resources')
param location string = 'eastus'

// Get the current subscription ID for RBAC assignment
var subscriptionId = subscription().subscriptionId

// Reference the existing Container Apps environment
resource environment 'Microsoft.App/managedEnvironments@2023-05-01' existing = {
  name: environmentName
}

// Reference the existing Azure Container Registry
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

// Update the Container App with Managed Identity
resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: containerAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: environment.id
    configuration: {
      // Container registry configuration
      registries: [
        {
          server: acr.properties.loginServer
          identity: 'system'  // Use managed identity for ACR access
        }
      ]
      // Ingress configuration for web access
      ingress: {
        external: true
        targetPort: 8000
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
    }
    template: {
      containers: [
        {
          name: containerAppName
          image: '${acr.properties.loginServer}/${imageName}'
          resources: {
            cpu: json('1.0')
            memory: '2.0Gi'
          }
          env: [
            {
              name: 'PORT'
              value: '8000'
            }
            {
              name: 'PYTHONUNBUFFERED'
              value: '1'
            }
            {
              name: 'ARI_OUTPUT_DIR'
              value: '/data/AzureResourceInventory'
            }
            {
              name: 'AZURE_CLIENT_ID'
              value: 'MSI'  // Use Managed Service Identity
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
      }
    }
  }
}

// Assign Reader role to the managed identity for the subscription
resource readerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerApp.id, 'Reader', subscriptionId)
  properties: {
    roleDefinitionId: '/subscriptions/${subscriptionId}/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'
    principalId: containerApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Assign AcrPull role to the managed identity for ACR access
resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerApp.id, 'AcrPull', acr.id)
  scope: acr
  properties: {
    roleDefinitionId: '/subscriptions/${subscriptionId}/providers/Microsoft.Authorization/roleDefinitions/7f951dda-4ed3-4680-a7ca-43fe172d538d'
    principalId: containerApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Outputs
output applicationUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output containerAppName string = containerApp.name
output managedIdentityPrincipalId string = containerApp.identity.principalId
output managedIdentityClientId string = containerApp.identity.tenantId