// Bicep template for deploying Azure Resource Inventory to Container Apps
// This template creates a Container App that pulls from your ACR

@description('The name of the Container App')
param containerAppName string = 'azure-resource-inventory'

@description('The name of the Container Apps environment')
param environmentName string = 'rk-azure-inventory'

@description('The resource group name')
param resourceGroupName string = 'rg-rkibbe-2470'

@description('The Azure Container Registry name')
param acrName string = 'rkazureinventory'

@description('The container image name and tag')
param imageName string = 'azure-resource-inventory:latest'

@description('The location for all resources')
param location string = 'eastus'

// Reference the existing Container Apps environment
resource environment 'Microsoft.App/managedEnvironments@2023-05-01' existing = {
  name: environmentName
}

// Reference the existing Azure Container Registry
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
  scope: resourceGroup(resourceGroupName)
}

// Create the Container App
resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: containerAppName
  location: location
  properties: {
    managedEnvironmentId: environment.id
    configuration: {
      // Container registry configuration
      registries: [
        {
          server: acr.properties.loginServer
          username: acr.listCredentials().username
          passwordSecretRef: 'acr-password'
        }
      ]
      // Secrets for ACR authentication
      secrets: [
        {
          name: 'acr-password'
          value: acr.listCredentials().passwords[0].value
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

// Output the application URL
output applicationUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output containerAppName string = containerApp.name