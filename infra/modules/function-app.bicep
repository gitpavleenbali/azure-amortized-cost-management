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
        { name: 'WEBSITE_RUN_FROM_PACKAGE', value: packageUri }
        { name: 'SCM_DO_BUILD_DURING_DEPLOYMENT', value: 'true' }
        { name: 'ENABLE_ORYX_BUILD', value: 'true' }
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

output functionAppName string = functionApp.name
output functionAppId string = functionApp.id
output principalId string = functionApp.identity.principalId
output defaultHostName string = functionApp.properties.defaultHostName
