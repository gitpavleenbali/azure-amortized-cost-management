// ============================================================
// Backfill Logic App — Subscription-Scope Reader Role
// Grants Reader at subscription scope so the backfill
// Logic App can enumerate resource groups.
// ============================================================

targetScope = 'subscription'

@description('Principal ID of the Backfill Logic App managed identity')
param principalId string

// Reader — enumerate resource groups for backfill
resource readerRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(principalId, 'Reader-backfill-sub')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
