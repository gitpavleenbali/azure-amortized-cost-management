// ============================================================
// Post-Deploy Subscription Role Assignment
// Grants Cost Management Contributor at subscription scope
// to the post-deploy managed identity for cost export creation.
// Separate module because it needs subscription scope.
// ============================================================

targetScope = 'subscription'

@description('Principal ID of the post-deploy managed identity')
param principalId string

// Cost Management Contributor — create/manage cost exports
resource costMgmtRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(principalId, 'CostManagementContributor-postdeploy')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '434105ed-43f6-45c7-a02f-909b2ba83430')
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
