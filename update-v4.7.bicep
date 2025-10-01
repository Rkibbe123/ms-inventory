@description('Container App Environment for Azure Resource Inventory')
param environmentName string = 'ari-inventory-env'

@description('Container App Name')
param containerAppName string = 'azure-resource-inventory'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Container Registry Server')
param registryServer string = 'rkazureinventory.azurecr.io'

@description('Container Registry Username')
@secure()
param registryUsername string

@description('Container Registry Password')
@secure()
param registryPassword string

@description('Container Image')
param containerImage string = 'rkazureinventory.azurecr.io/azure-resource-inventory:v4.7'

// Reference existing Container App Environment
resource environment 'Microsoft.App/managedEnvironments@2023-05-01' existing = {
  name: environmentName
}

// Update existing Container App
resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: containerAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: environment.id
    configuration: {
      secrets: [
        {
          name: 'registry-password'
          value: registryPassword
        }
      ]
      registries: [
        {
          server: registryServer
          username: registryUsername
          passwordSecretRef: 'registry-password'
        }
      ]
      ingress: {
        external: true
        targetPort: 5000
        allowInsecure: false
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
      }
    }
    template: {
      containers: [
        {
          name: 'azure-resource-inventory'
          image: containerImage
          resources: {
            cpu: json('1.0')
            memory: '2Gi'
          }
          env: [
            {
              name: 'FLASK_APP'
              value: 'app.main'
            }
            {
              name: 'FLASK_ENV'
              value: 'production'
            }
            {
              name: 'PYTHONUNBUFFERED'
              value: '1'
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

output fqdn string = containerApp.properties.configuration.ingress.fqdn