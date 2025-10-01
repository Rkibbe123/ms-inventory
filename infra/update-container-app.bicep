// Bicep template to update Container App with new image version
// This will update the existing container app with the improved async version

@description('The name of the Container App')
param containerAppName string = 'azure-resource-inventory'

@description('The name of the Container Apps environment')
param environmentName string = 'ari-inventory-env'

@description('The Azure Container Registry name')
param acrName string = 'rkazureinventory'

@description('The container image name and tag')
param imageName string = 'azure-resource-inventory:v2.0'

@description('The location for all resources')
param location string = 'eastus'

// Reference the existing Container Apps environment
resource environment 'Microsoft.App/managedEnvironments@2023-05-01' existing = {
  name: environmentName
}

// Reference the existing Azure Container Registry
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

// Update the Container App with new configuration
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
        {
          name: 'flask-secret'
          value: 'ari-secret-key-${uniqueString(resourceGroup().id)}'
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
              name: 'FLASK_SECRET_KEY'
              secretRef: 'flask-secret'
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