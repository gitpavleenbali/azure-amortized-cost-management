// ============================================================
// Action Group Module (QW-01)
// Creates the central FinOps budget alert Action Group.
// ============================================================

param location string = 'Global'
param actionGroupName string = 'ag-finops-budget-alerts'
param shortName string = 'FinOpsBgt'
param finopsEmail string
@secure()
param teamsWebhookUri string = ''
param tags object = {}

var enableTeams = !empty(teamsWebhookUri)

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: location
  tags: tags
  properties: {
    groupShortName: shortName
    enabled: true
    emailReceivers: [
      {
        name: 'finops-team'
        emailAddress: finopsEmail
        useCommonAlertSchema: true
      }
    ]
    webhookReceivers: enableTeams ? [
      {
        name: 'teams-finops-budget-alerts'
        serviceUri: teamsWebhookUri
        useCommonAlertSchema: true
      }
    ] : []
    armRoleReceivers: [
      {
        name: 'subscription-contributors'
        roleId: 'b24988ac-6180-42a0-ab88-20f7382dd24c' // Contributor
        useCommonAlertSchema: true
      }
    ]
  }
}

output actionGroupId string = actionGroup.id
output actionGroupName string = actionGroup.name
