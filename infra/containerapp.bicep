param location string
param tags object = {}
param containerAppName string
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

var dbPort = '5432'

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
          value: 'mastodon-prod'
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
          command: [
            '/bin/bash'
            '-c'
            'bundle exec rails s -p 3000'
          ]
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
          image: 'wordpress:php8.2-fpm'
          name: 'wordpress'
          probes: [
            {
              failureThreshold: 5
              tcpSocket: {
                port: 80
              }
              timeoutSeconds: 5
              type: 'Liveness'
            }
            {
              failureThreshold: 5
              httpGet: {
                path: '/'
                port: 80
                scheme: 'HTTP'
              }
              timeoutSeconds: 5
              type: 'Readiness'
            }
            {
              failureThreshold: 30
              httpGet: {
                path: '/'
                port: 80
                scheme: 'HTTP'
              }
              timeoutSeconds: 5
              type: 'Startup'
            }
          ]
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          volumeMounts: [
            {
              mountPath: '/var/www/html'
              volumeName: 'volStorage'
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
      }
      volumes:[
        {
          name: 'volStorage'
          storageName: environment.outputs.webStorageName
          storageType: 'AzureFile'
        }
      ]
    }
  }
}

output webFqdn string = wordpressApp.properties.latestRevisionFqdn

