// ============================================================
// Networking Module — VNet + Private Endpoints (v2)
// Provides network isolation for Cosmos DB, Storage, and Function App.
// Deployed only when enablePrivateNetworking = true.
// ============================================================

param location string
param tags object = {}

@description('Name of the VNet to create or use')
param vnetName string = 'vnet-finops-governance'

@description('VNet address space')
param vnetAddressPrefix string = '10.100.0.0/24'

@description('Subnet for private endpoints')
param privateEndpointSubnetName string = 'snet-private-endpoints'
param privateEndpointSubnetPrefix string = '10.100.0.0/26'

@description('Subnet for Function App VNet integration')
param functionAppSubnetName string = 'snet-function-app'
param functionAppSubnetPrefix string = '10.100.0.64/26'

@description('Cosmos DB account ID for private endpoint')
param cosmosAccountId string

@description('Cosmos DB account name')
param cosmosAccountName string

@description('Storage account ID for private endpoint')
param storageAccountId string

@description('Storage account name')
param storageAccountName string

@description('Function App ID (empty if pipeline disabled)')
param functionAppId string = ''

@description('Function App name')
param functionAppName string = ''

// ── VNet ─────────────────────────────────────────────────────
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: privateEndpointSubnetName
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: functionAppSubnetName
        properties: {
          addressPrefix: functionAppSubnetPrefix
          delegations: [
            {
              name: 'Microsoft.Web.serverFarms'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
    ]
  }
}

// ── Private DNS Zones ────────────────────────────────────────
resource dnsZoneCosmos 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.documents.azure.com'
  location: 'global'
  tags: tags
}

resource dnsZoneStorage 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.blob.core.windows.net'
  location: 'global'
  tags: tags
}

resource dnsZoneStorageTable 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.table.core.windows.net'
  location: 'global'
  tags: tags
}

// ── DNS Zone → VNet Links ────────────────────────────────────
resource cosmosVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: dnsZoneCosmos
  name: '${vnetName}-cosmos-link'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}

resource storageVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: dnsZoneStorage
  name: '${vnetName}-blob-link'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}

resource storageTableVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: dnsZoneStorageTable
  name: '${vnetName}-table-link'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnet.id }
    registrationEnabled: false
  }
}

// ── NSG for Private Endpoint Subnet ──────────────────────────
resource nsgPrivateEndpoints 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-${privateEndpointSubnetName}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
      {
        name: 'AllowVnetInbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// ── Private Endpoint: Cosmos DB ──────────────────────────────
resource peCosmosDb 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${cosmosAccountName}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: vnet.properties.subnets[0].id
    }
    privateLinkServiceConnections: [
      {
        name: 'pe-${cosmosAccountName}-sql'
        properties: {
          privateLinkServiceId: cosmosAccountId
          groupIds: [ 'Sql' ]
        }
      }
    ]
  }
}

resource peCosmosDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: peCosmosDb
  name: 'cosmos-dns'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-documents-azure-com'
        properties: {
          privateDnsZoneId: dnsZoneCosmos.id
        }
      }
    ]
  }
}

// ── Private Endpoint: Storage (Blob) ─────────────────────────
resource peStorageBlob 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${storageAccountName}-blob'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: vnet.properties.subnets[0].id
    }
    privateLinkServiceConnections: [
      {
        name: 'pe-${storageAccountName}-blob'
        properties: {
          privateLinkServiceId: storageAccountId
          groupIds: [ 'blob' ]
        }
      }
    ]
  }
}

resource peStorageBlobDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: peStorageBlob
  name: 'blob-dns'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-blob-core-windows-net'
        properties: {
          privateDnsZoneId: dnsZoneStorage.id
        }
      }
    ]
  }
}

// ── Private Endpoint: Storage (Table) ────────────────────────
resource peStorageTable 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${storageAccountName}-table'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: vnet.properties.subnets[0].id
    }
    privateLinkServiceConnections: [
      {
        name: 'pe-${storageAccountName}-table'
        properties: {
          privateLinkServiceId: storageAccountId
          groupIds: [ 'table' ]
        }
      }
    ]
  }
}

resource peStorageTableDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: peStorageTable
  name: 'table-dns'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-table-core-windows-net'
        properties: {
          privateDnsZoneId: dnsZoneStorageTable.id
        }
      }
    ]
  }
}

// ── Outputs ──────────────────────────────────────────────────
output vnetId string = vnet.id
output privateEndpointSubnetId string = vnet.properties.subnets[0].id
output functionAppSubnetId string = vnet.properties.subnets[1].id
output vnetName string = vnet.name
