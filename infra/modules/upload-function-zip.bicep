// ============================================================
// Upload Function App Zip to Blob Storage
// Downloads the zip from GitHub and uploads to the storage
// account so the function app can use WEBSITE_RUN_FROM_PACKAGE
// with managed identity authentication.
// ============================================================

param location string
param storageAccountName string
param tags object = {}

@description('GitHub URL to download the function app zip from')
param sourceZipUrl string = 'https://raw.githubusercontent.com/gitpavleenbali/azure-amortized-cost-management/main/functions/amortized-budget-engine.zip'

@description('Blob container name for function releases')
param containerName string = 'function-releases'

@description('Blob name for the zip file')
param blobName string = 'engine.zip'

// User-assigned managed identity for the deployment script
resource scriptIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-finops-deploy-script'
  location: location
  tags: tags
}

// Grant the script identity Blob Data Contributor on the storage account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource blobContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, scriptIdentity.id, 'StorageBlobDataContributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: scriptIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Create the blob container
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' existing = {
  parent: storageAccount
  name: 'default'
}

resource releaseContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: containerName
  properties: { publicAccess: 'None' }
}

// Deployment script to download from GitHub and upload to blob
resource uploadScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'upload-function-zip'
  location: location
  tags: tags
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${scriptIdentity.id}': {}
    }
  }
  properties: {
    azCliVersion: '2.60.0'
    retentionInterval: 'PT1H'
    cleanupPreference: 'OnSuccess'
    timeout: 'PT10M'
    environmentVariables: [
      { name: 'SA_NAME', value: storageAccountName }
      { name: 'CONTAINER', value: containerName }
      { name: 'BLOB_NAME', value: blobName }
      { name: 'SOURCE_URL', value: sourceZipUrl }
    ]
    scriptContent: '''
      set -e
      echo "Downloading zip from $SOURCE_URL..."
      wget -q "$SOURCE_URL" -O /tmp/engine.zip
      ls -la /tmp/engine.zip
      echo "Uploading to $SA_NAME/$CONTAINER/$BLOB_NAME..."
      az storage blob upload \
        --account-name "$SA_NAME" \
        --container-name "$CONTAINER" \
        --name "$BLOB_NAME" \
        --file /tmp/engine.zip \
        --auth-mode login \
        --overwrite \
        --only-show-errors
      echo "Upload complete"
    '''
  }
  dependsOn: [
    blobContributorRole
    releaseContainer
  ]
}

output blobUrl string = 'https://${storageAccountName}.blob.core.windows.net/${containerName}/${blobName}'
