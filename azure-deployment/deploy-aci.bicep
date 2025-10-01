@description('Name of the container group')
param containerGroupName string = 'ari-web-interface'

@description('Container image name including registry and tag')
param containerImageName string = 'your-registry.azurecr.io/ari-web-interface:latest'

@description('DNS name label for the public IP')
param dnsNameLabel string = 'ari-web-${uniqueString(resourceGroup().id)}'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Number of CPU cores for the container')
@allowed([
  '1'
  '2'
  '4'
])
param cpuCores string = '2'

@description('Amount of memory in GB for the container')
@allowed([
  '1'
  '2'
  '4'
  '8'
  '16'
])
param memoryInGb string = '4'

@description('Container registry username (if using private registry)')
param registryUsername string = ''

@description('Container registry password (if using private registry)')
@secure()
param registryPassword string = ''

var containerName = 'ari-web-container'
var port = 3000

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2021-03-01' = {
  name: containerGroupName
  location: location
  properties: {
    containers: [
      {
        name: containerName
        properties: {
          image: containerImageName
          ports: [
            {
              port: port
              protocol: 'TCP'
            }
          ]
          resources: {
            requests: {
              cpu: int(cpuCores)
              memoryInGB: int(memoryInGb)
            }
          }
          environmentVariables: [
            {
              name: 'PORT'
              value: string(port)
            }
            {
              name: 'NODE_ENV'
              value: 'production'
            }
          ]
        }
      }
    ]
    osType: 'Linux'
    restartPolicy: 'Always'
    ipAddress: {
      type: 'Public'
      dnsNameLabel: dnsNameLabel
      ports: [
        {
          port: port
          protocol: 'TCP'
        }
      ]
    }
    imageRegistryCredentials: empty(registryUsername) ? null : [
      {
        server: split(containerImageName, '/')[0]
        username: registryUsername
        password: registryPassword
      }
    ]
  }
}

@description('Container IPv4 address')
output containerIPv4Address string = containerGroup.properties.ipAddress.ip

@description('Container FQDN')
output containerFQDN string = containerGroup.properties.ipAddress.fqdn

@description('Application URL')
output applicationUrl string = 'http://${containerGroup.properties.ipAddress.fqdn}:${port}'