param location string
param tags object = {}
param containerAppName string
param wordpressFqdn string
param infraSnetId string
param logAnalytics object 
param storageAccountName string 
@secure()
param storageAccountKey string
param storageShareName string 
param dbHost string
param dbUser string
@secure()
param dbPassword string
param deployWithRedis bool = false

var dbPort = '3306'
var volumename = 'wpstorage' //sensitive to casing and length. It has to be all lowercase.
var dbName = 'wordpress'

module environment 'modules/containerappsEnvironment.module.bicep' = {
  name: 'containerAppEnv-deployement'
  params: {
    tags: tags
    infraSnetId: infraSnetId
    location: location
    logAnalytics: logAnalytics
    storageAccountKey: storageAccountKey
    storageAccountName: storageAccountName
    storageShareName: storageShareName
  }
}

resource redis 'Microsoft.App/containerApps@2022-06-01-preview' = if (deployWithRedis) {
  name: '${containerAppName}redis'
  location: location
  tags: tags
  properties: {
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        allowInsecure: true
        external: true
        targetPort: 6379
        transport: 'auto'
      }
    }
    environmentId: environment.outputs.containerEnvId
    template: {
      containers: [
        {
          args: []
          command: []
          env: []
          image: 'redis:latest'
          name: 'redis'
          probes: []
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          volumeMounts: []
        }
      ]
      scale: {
        minReplicas: 1
      }
      volumes:[]
    }
  }
}

resource wordpressApp 'Microsoft.App/containerApps@2022-06-01-preview' = {
  name: '${containerAppName}web'
  location: location
  tags: tags
  properties: {
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        allowInsecure: true
        external: true
        targetPort: 80
        transport: 'auto'
      }
      secrets: [
        {
          name: 'db-host'
          value: dbHost
        }
        {
          name: 'db-port'
          value: dbPort
        }
        {
          name: 'db-user'
          value: '${dbUser}@${dbHost}'
        }
        {
          name: 'db-name'
          value: dbName
        }
        {
          name: 'db-pass'
          value: dbPassword
        }
      ]
    }
    environmentId: environment.outputs.containerEnvId
    template: {
      containers: [
        {
          args: []
          command: []
          env: [
            {
              name: 'DB_HOST'
              secretRef: 'db-host'
            }
            {
              name: 'DB_USER'
              secretRef: 'db-user'
            }
            {
              name: 'DB_NAME'
              secretRef: 'db-name'
            }
            {
              name: 'DB_PASS'
              secretRef: 'db-pass'
            }
            {
              name: 'DB_PORT'
              secretRef: 'db-port'
            }
          ]
          image: 'kpantos/wordpress-alpine-php:latest'
          name: 'wordpress'
          probes: []
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          volumeMounts: [
            {
              mountPath: '/home/site'
              volumeName: volumename
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
      }
      volumes:[
        {
          name: volumename
          storageName: environment.outputs.webStorageName
          storageType: 'AzureFile'
        }
      ]
    }
  }
}

output webFqdn string = wordpressApp.properties.latestRevisionFqdn
output redisFqdn string = redis.properties.latestRevisionFqdn
output webLatestRevisionName string = wordpressApp.properties.latestRevisionName
output envSuffix string = environment.outputs.envSuffix
output loadBalancerIP string = environment.outputs.loadBalancerIP
