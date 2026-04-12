// ============================================================
// Cosmos DB Module — FinOps Inventory (NoSQL API)
// Central source of truth for budget data, amortized costs,
// finance vs technical comparison, and compliance status.
// NoSQL API chosen for: Power BI native connector, change feed,
// rich queries, automatic indexing, serverless cost model.
// ============================================================

param location string
param cosmosAccountName string = 'cosmos-finops-inventory'
param databaseName string = 'finops'
param containerName string = 'inventory'
param tags object = {}

// Serverless = pay per request, ideal for 8,000 docs + daily batch
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: cosmosAccountName
  location: location
  tags: union(tags, { 'finops-component': 'inventory-store' })
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    capabilities: [
      { name: 'EnableServerless' }
    ]
    locations: [
      {
        locationName: location
        failoverPriority: 0
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    enableFreeTier: false
  }
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: cosmosAccount
  name: databaseName
  properties: {
    resource: {
      id: databaseName
    }
  }
}

resource container 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: database
  name: containerName
  properties: {
    resource: {
      id: containerName
      partitionKey: {
        paths: [ '/subscriptionId' ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
        includedPaths: [
          { path: '/*' }
        ]
        excludedPaths: [
          { path: '/"_etag"/?' }
        ]
      }
      defaultTtl: -1  // No auto-expiry, but TTL enabled for future use
    }
  }
}

output cosmosAccountName string = cosmosAccount.name
output cosmosEndpoint string = cosmosAccount.properties.documentEndpoint
output cosmosDatabaseName string = database.name
output cosmosContainerName string = container.name
output cosmosAccountId string = cosmosAccount.id
