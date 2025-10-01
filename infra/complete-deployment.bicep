// Complete Bicep template for Container Apps Environment and Application
// This creates both the environment and deploys the Azure Resource Inventory app

@description('The name of the Container Apps environment')
param environmentName string = 'ari-inventory-env'

@description('The name of the Container App')
param containerAppName string = 'azure-resource-inventory'

@description('The Azure Container Registry name')
param acrName string = 'rkazureinventory'

@description('The container image name and tag')
param imageName string = 'azure-resource-inventory:latest'

@description('The location for all resources')
param location string = 'eastus'

@description('Log Analytics workspace name')
param logAnalyticsWorkspaceName string = 'ari-logs-workspace'

// Create Log Analytics workspace for Container Apps
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Create the Container Apps environment
resource environment 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: environmentName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
  }
}

// Reference the existing Azure Container Registry
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
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

// Outputs
output environmentName string = environment.name
output containerAppName string = containerApp.name
output applicationUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name