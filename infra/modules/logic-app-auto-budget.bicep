// ============================================================
// Logic App: Auto-Budget Creator (MT-01)
// Event Grid triggers: auto-create €100 budget on new RG.
// Uses managed identity for ARM API calls.
// ============================================================

param location string
param logicAppName string = 'la-finops-auto-budget'
param finopsEmail string
param defaultBudgetAmount int = 100
@secure()
param teamsWebhookUri string = ''
param tags object = {}

@description('Set to false if deployer lacks User Access Administrator role')
param enableRbacAssignment bool = true

resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  tags: union(tags, { 'finops-component': 'auto-budget' })
  identity: { type: 'SystemAssigned' }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        finopsEmail: { type: 'String', defaultValue: finopsEmail }
        defaultBudgetAmount: { type: 'Int', defaultValue: defaultBudgetAmount }
        teamsWebhookUri: { type: 'SecureString', defaultValue: teamsWebhookUri }
      }
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                subject: { type: 'string' }
                eventType: { type: 'string' }
                data: {
                  type: 'object'
                  properties: {
                    resourceUri: { type: 'string' }
                    subscriptionId: { type: 'string' }
                  }
                }
              }
            }
          }
        }
      }
      actions: {
        Parse_Event: {
          type: 'ParseJson'
          inputs: {
            content: '@if(equals(string(triggerBody()?[\'subject\']), \'\'), triggerBody()[0], triggerBody())'
            schema: {
              type: 'object'
              properties: {
                subject: { type: 'string' }
                eventType: { type: 'string' }
                data: {
                  type: 'object'
                  properties: {
                    resourceUri: { type: 'string' }
                    subscriptionId: { type: 'string' }
                  }
                }
              }
            }
          }
          runAfter: {}
        }
        Extract_RG_Name: {
          type: 'Compose'
          inputs: '@last(split(body(\'Parse_Event\')?[\'subject\'], \'/\'))'
          runAfter: { Parse_Event: [ 'Succeeded' ] }
        }
        Extract_Sub_Id: {
          type: 'Compose'
          inputs: '@split(body(\'Parse_Event\')?[\'subject\'], \'/\')[2]'
          runAfter: { Parse_Event: [ 'Succeeded' ] }
        }
        Check_Budget_Exists: {
          type: 'Http'
          inputs: {
            method: 'GET'
            uri: 'https://management.azure.com/subscriptions/@{outputs(\'Extract_Sub_Id\')}/resourceGroups/@{outputs(\'Extract_RG_Name\')}/providers/Microsoft.Consumption/budgets?api-version=2023-11-01'
            authentication: { type: 'ManagedServiceIdentity' }
          }
          runAfter: { Extract_RG_Name: [ 'Succeeded' ], Extract_Sub_Id: [ 'Succeeded' ] }
        }
        Create_If_Missing: {
          type: 'If'
          expression: { and: [ { equals: [ '@length(body(\'Check_Budget_Exists\')?[\'value\'])', 0 ] } ] }
          runAfter: { Check_Budget_Exists: [ 'Succeeded' ] }
          actions: {
            Create_Budget: {
              type: 'Http'
              inputs: {
                method: 'PUT'
                uri: 'https://management.azure.com/subscriptions/@{outputs(\'Extract_Sub_Id\')}/resourceGroups/@{outputs(\'Extract_RG_Name\')}/providers/Microsoft.Consumption/budgets/finops-rg-budget-@{outputs(\'Extract_RG_Name\')}?api-version=2023-11-01'
                authentication: { type: 'ManagedServiceIdentity' }
                body: {
                  properties: {
                    category: 'Cost'
                    amount: '@parameters(\'defaultBudgetAmount\')'
                    timeGrain: 'Monthly'
                    timePeriod: {
                      startDate: '@{formatDateTime(startOfMonth(utcNow()), \'yyyy-MM-ddTHH:mm:ssZ\')}'
                      endDate: '2027-03-31T00:00:00Z'
                    }
                    notifications: {
                      Forecasted_90: { enabled: true, operator: 'GreaterThan', threshold: 90, thresholdType: 'Forecasted', contactEmails: [ '@parameters(\'finopsEmail\')' ] }
                      Actual_100: { enabled: true, operator: 'GreaterThan', threshold: 100, thresholdType: 'Actual', contactEmails: [ '@parameters(\'finopsEmail\')' ] }
                      Forecasted_110: { enabled: true, operator: 'GreaterThan', threshold: 110, thresholdType: 'Forecasted', contactEmails: [ '@parameters(\'finopsEmail\')' ] }
                    }
                  }
                }
              }
              runAfter: {}
            }
            Notify_Teams: {
              type: 'Http'
              inputs: {
                method: 'POST'
                uri: '@parameters(\'teamsWebhookUri\')'
                body: { text: '**[FinOps Auto-Budget]** Budget EUR @{parameters(\'defaultBudgetAmount\')} created for RG: **@{outputs(\'Extract_RG_Name\')}**' }
              }
              runAfter: { Create_Budget: [ 'Succeeded' ] }
            }
          }
          else: { actions: {} }
        }
      }
      outputs: {}
    }
  }
}

// Grant managed identity Cost Management Contributor on subscription
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableRbacAssignment) {
  name: guid(logicApp.id, 'CostManagementContributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '434105ed-43f6-45c7-a02f-909b2ba83430') // Cost Management Contributor
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output logicAppId string = logicApp.id
output principalId string = logicApp.identity.principalId
