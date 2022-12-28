param name string
param location string = resourceGroup().location
param tags object = {}
param subnetId string
@description('The FQDN of the Application Gateawy.Must match the TLS Certificate.')
param appGatewayFQDN string
param webContainerAppFqdn string
param keyVaultName string
param certificateKeyName string

var resourceNames = {
  publicIP: 'pip-${name}'
  webBackendAddressPool: 'web-beap-capp-${name}'
  streamingBackendAddressPool: 'streaming-beap-capp-${name}'
  frontendPort443: 'feport-${name}-443'
  frontendIpConfiguration: 'feip-${name}'
  backendHttpSettingFor80: 'be-htst-${name}-80'
  httpListener: 'httplstn-${name}'
  urlPathMaps: 'urlPathmaps-${name}'
  requestRoutingRule: 'rqrt-${name}'
  redirectConfiguration: 'rdrcfg-${name}'
}
var webPath = '/'
var keyVaultSecretsUserRoleDefinitionId = '4633458b-17de-408a-b874-0445c86b69e6'

resource vault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: keyVaultName
}

resource keyVaultCertificate 'Microsoft.KeyVault/vaults/secrets@2022-07-01' existing = {
  name: certificateKeyName
  parent: vault
}

resource pip 'Microsoft.Network/publicIPAddresses@2022-05-01' = {
  name: resourceNames.publicIP
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource agwManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2022-01-31-preview' = {
  name: 'agw-managed-identity'    //3-128, can contain '-' and '_'.
  location: location
  tags: tags
}

resource kv 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: keyVaultName
}

resource kvRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVaultSecretsUserRoleDefinitionId,'agwManagedIdentity',kv.id)
  scope: kv
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleDefinitionId)
    principalId: agwManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource applicationGateway 'Microsoft.Network/applicationGateways@2022-05-01' = {
  name: name
  location: location
  tags: tags
  identity:{
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${agwManagedIdentity.id}': {}
    }
  }
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
    }
    webApplicationFirewallConfiguration: {
      enabled: true
      firewallMode: 'Detection'
      ruleSetType: 'OWASP'
      ruleSetVersion: '3.0'
      disabledRuleGroups: []
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 100
    }
    autoscaleConfiguration: {
      minCapacity: 1
      maxCapacity: 4
    }
    sslCertificates: [
      {
        name: appGatewayFQDN
        properties: {
          keyVaultSecretId:  keyVaultCertificate.properties.secretUriWithVersion
        }
      }
    ]
    gatewayIPConfigurations: [
      {
        name: '${name}-ip-configuration'
        properties: {
          subnet: {
            id: subnetId
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: resourceNames.frontendIpConfiguration
        properties: {
          publicIPAddress: {
            id: pip.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: resourceNames.frontendPort443
        properties: {
          port: 443
        }
      }
    ]
    backendAddressPools: [
      {
        name: resourceNames.webBackendAddressPool
        properties: {
          backendAddresses: [
            {
              fqdn: webContainerAppFqdn
            }
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: resourceNames.backendHttpSettingFor80
        properties: {
          port: 80
          protocol: 'Http'
          cookieBasedAffinity: 'Enabled'
          affinityCookieName: ''
          pickHostNameFromBackendAddress: false
          requestTimeout: 120
          probe:{
            id: resourceId('Microsoft.Network/applicationGateways/probes', name, 'webProbe')
          }
        }
      }
    ]
    httpListeners: [
      {
        name: resourceNames.httpListener
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', name, resourceNames.frontendIpConfiguration)
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', name, resourceNames.frontendPort443)
          }
          protocol: 'Https'
          sslCertificate: {
            id: resourceId('Microsoft.Network/applicationGateways/sslCertificates', name, appGatewayFQDN)
          }
        }
      }
    ]
    requestRoutingRules: [
      {
        name: resourceNames.requestRoutingRule
        properties: {
          ruleType: 'Basic'
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', name, resourceNames.httpListener)
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', name, resourceNames.webBackendAddressPool)
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', name, resourceNames.backendHttpSettingFor80)
          }
        }
      }
    ]
    urlPathMaps:[]
    probes: [
      {
        name: 'webProbe'
        properties: {
          protocol: 'Http'
          host: webContainerAppFqdn
          path: webPath
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          pickHostNameFromBackendHttpSettings: false
          minServers: 0
          match: {
            statusCodes: [
              '200-399'
            ]
          }
        }
      }
    ]
  }
}

resource vaultAccess 'Microsoft.KeyVault/vaults/accessPolicies@2022-07-01' = {
  name: 'add'
  parent: vault
  properties: {
    accessPolicies: [
      {
        tenantId: applicationGateway.identity.tenantId
        objectId: applicationGateway.identity.principalId
        permissions: {
          secrets: [
            'get'
          ]
        }
      }
    ]
  }
}

output backendAddressPools array = applicationGateway.properties.backendAddressPools
