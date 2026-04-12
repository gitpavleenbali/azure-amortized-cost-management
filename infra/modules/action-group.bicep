// ============================================================
// Action Group Module (QW-01)
// Creates the central FinOps budget alert Action Group.
// ============================================================

param location string = 'Global'
param actionGroupName string = 'ag-finops-budget-alerts'
param shortName string = 'FinOpsBgt'

@description('FinOps team email(s) — comma-separated for multiple recipients (e.g. "team@org.com,lead@org.com")')
param finopsEmail string

@secure()
param teamsWebhookUri string = ''
param tags object = {}

var enableTeams = !empty(teamsWebhookUri)

// Split comma-separated emails into array and build emailReceivers
var emailList = split(replace(finopsEmail, ' ', ''), ',')
var emailReceivers = [for (email, i) in emailList: {
  name: 'finops-recipient-${i + 1}'
  emailAddress: email
  useCommonAlertSchema: true
}]

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: location
  tags: tags
  properties: {
    groupShortName: shortName
    enabled: true
    emailReceivers: emailReceivers
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
