// ============================================================
// Function App Module (LT-01)
// Hosts the amortized budget evaluation engine.
// Python 3.11, Consumption plan, managed identity.
// ============================================================

param location string
param functionAppName string = 'func-finops-amortized-${uniqueString(resourceGroup().id)}'
param storageAccountName string
param cosmosEndpoint string = ''
param cosmosDatabaseName string = 'finops'
param cosmosContainerName string = 'inventory'
@secure()
param teamsWebhookUri string = ''
param finopsEmail string
param tags object = {}

@description('URL to the Function App zip package for automated deployment')
param packageUri string = 'https://raw.githubusercontent.com/gitpavleenbali/azure-amortized-cost-management/main/functions/amortized-budget-engine.zip'

@description('Set to false if deployer lacks User Access Administrator role')
param enableRbacAssignment bool = true

@description('Subscription budget amount (for subscription-level rollup)')
param subscriptionBudgetAmount int = 10000

@description('Cost tracking scope: resourceGroup, subscription, or both')
param costTrackingScope string = 'both'

@description('Log Analytics workspace customer ID (for _sync_to_law)')
param lawCustomerId string = ''

@description('Log Analytics workspace shared key (for _sync_to_law)')
@secure()
param lawSharedKey string = ''

@description('Cosmos DB account name (for data plane role assignment)')
param cosmosAccountName string = ''

@description('Cosmos DB account ID')
param cosmosAccountId string = ''

@description('Log Analytics workspace ID (resource ID)')
param logAnalyticsWorkspaceId string = ''

resource hostingPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${functionAppName}-plan'
  location: location
  tags: tags
  kind: 'functionapp'
  sku: { name: 'Y1', tier: 'Dynamic' }
  properties: { reserved: true } // Linux
}

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: union(tags, { 'finops-component': 'amortized-engine' })
  kind: 'functionapp,linux'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: hostingPlan.id
    httpsOnly: true
    siteConfig: {
      pythonVersion: '3.11'
      linuxFxVersion: 'PYTHON|3.11'
      appSettings: [
        // Managed Identity-based storage connection (no shared keys)
        { name: 'AzureWebJobsStorage__accountName', value: storageAccountName }
        { name: 'AzureWebJobsStorage__blobServiceUri', value: 'https://${storageAccountName}.blob.core.windows.net' }
        { name: 'AzureWebJobsStorage__queueServiceUri', value: 'https://${storageAccountName}.queue.core.windows.net' }
        { name: 'AzureWebJobsStorage__tableServiceUri', value: 'https://${storageAccountName}.table.core.windows.net' }
        { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'python' }
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
        { name: 'STORAGE_ACCOUNT_NAME', value: storageAccountName }
        { name: 'STORAGE_CONTAINER_NAME', value: 'amortized-cost-exports' }
        { name: 'COSMOS_ENDPOINT', value: cosmosEndpoint }
        { name: 'COSMOS_DATABASE', value: cosmosDatabaseName }
        { name: 'COSMOS_CONTAINER', value: cosmosContainerName }
        { name: 'TEAMS_WEBHOOK_URL', value: teamsWebhookUri }
        { name: 'FINOPS_EMAIL', value: finopsEmail }
        { name: 'ALERT_THRESHOLDS', value: '50,75,90,100,110' }
        { name: 'LAW_WORKSPACE_ID', value: lawCustomerId }
        { name: 'LAW_SHARED_KEY', value: lawSharedKey }
        { name: 'SUBSCRIPTION_BUDGET_AMOUNT', value: string(subscriptionBudgetAmount) }
        { name: 'AZURE_SUBSCRIPTION_ID', value: subscription().subscriptionId }
        { name: 'COST_TRACKING_SCOPE', value: costTrackingScope }
      ]
    }
  }
}

// Grant Storage Blob Data Owner (read exports + Function runtime)
resource blobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableRbacAssignment) {
  name: guid(functionApp.id, 'StorageBlobDataOwner')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Storage Queue Data Contributor (Function runtime needs queues)
resource queueRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableRbacAssignment) {
  name: guid(functionApp.id, 'StorageQueueDataContributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Storage Table Data Contributor (Function runtime needs tables)
resource tableRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableRbacAssignment) {
  name: guid(functionApp.id, 'StorageTableDataContributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Cosmos DB Built-in Data Contributor (data plane — read/write to inventory)
// Cosmos DB uses its own SQL role system, NOT ARM RBAC
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = if (!empty(cosmosAccountName)) {
  name: cosmosAccountName
}

resource cosmosDataRole 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-11-15' = if (enableRbacAssignment && !empty(cosmosAccountName)) {
  parent: cosmosAccount
  name: guid(functionApp.id, cosmosAccountName, 'CosmosDataContributor')
  properties: {
    roleDefinitionId: '${cosmosAccount.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
    principalId: functionApp.identity.principalId
    scope: cosmosAccount.id
  }
}

// Grant Cost Management Reader (read cost data for evaluation)
// Note: subscription-scope assignment — requires subscription targetScope
// This is handled from the parent main.bicep via a separate module

// Grant Log Analytics Contributor (write amortized cost data to LAW for workbook/alerts)
resource lawContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableRbacAssignment && !empty(logAnalyticsWorkspaceId)) {
  name: guid(functionApp.id, 'LogAnalyticsContributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '92aaf0da-9dab-42b6-94a3-d43ce8d16293')
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output functionAppName string = functionApp.name
output functionAppId string = functionApp.id
output principalId string = functionApp.identity.principalId
output defaultHostName string = functionApp.properties.defaultHostName
