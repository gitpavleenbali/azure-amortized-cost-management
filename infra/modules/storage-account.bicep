// ============================================================
// Storage Account Module (LT-03 + QW-05)
// Storage for: budget table, cost exports, function app.
// ============================================================

param location string
param environment string
param storageAccountName string = 'safinops${uniqueString(resourceGroup().id)}'
param tags object = {}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    accessTier: 'Hot'
  }
}

// Blob container for amortized cost exports
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource exportContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'amortized-cost-exports'
  properties: { publicAccess: 'None' }
}

// Table for budget targets (amortized engine reads this)
resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource budgetTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableService
  name: 'finopsInventory'
}

output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob
output tableEndpoint string = storageAccount.properties.primaryEndpoints.table
