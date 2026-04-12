// ============================================================
// Function App Subscription-Scope Role Assignments
// Grants Cost Management Reader at subscription scope
// so the Function App can read cost data for evaluation.
// ============================================================

targetScope = 'subscription'

@description('Principal ID of the Function App managed identity')
param functionAppPrincipalId string

// Cost Management Reader — read cost data from Cost Management API
resource costMgmtReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionAppPrincipalId, 'CostManagementReader-func')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '72fafb9e-0641-4937-9268-a91bfd8191a3')
    principalId: functionAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}
