// ============================================================
// Logic App: Self-Service Budget Change (MT-02)
// HTTP-triggered: RG owners submit budget change requests.
// Validates floor/cap, optional approval, updates via REST API.
// ============================================================

param location string
param logicAppName string = 'la-finops-budget-change'
param finopsEmail string
@secure()
param teamsWebhookUri string = ''
@secure()
@description('Function App host key for /api/update-budget')
param functionAppKey string = ''
param functionAppName string = ''
param tags object = {}

@description('Set to false if deployer lacks User Access Administrator role')
param enableRbacAssignment bool = true

resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  tags: union(tags, { 'finops-component': 'budget-change' })
  identity: { type: 'SystemAssigned' }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        finopsEmail: { type: 'String', defaultValue: finopsEmail }
        teamsWebhookUri: { type: 'SecureString', defaultValue: teamsWebhookUri }
        functionAppKey: { type: 'SecureString', defaultValue: functionAppKey }
        functionAppName: { type: 'String', defaultValue: functionAppName }
      }
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              required: [ 'subscriptionId', 'resourceGroupName', 'newBudgetAmount', 'reason', 'requestorEmail' ]
              properties: {
                subscriptionId: { type: 'string' }
                resourceGroupName: { type: 'string' }
                newBudgetAmount: { type: 'integer', minimum: 100 }
                reason: { type: 'string' }
                requestorEmail: { type: 'string' }
              }
            }
          }
        }
      }
      actions: {
        Validate_Floor: {
          type: 'If'
          expression: { and: [ { less: [ '@triggerBody()?[\'newBudgetAmount\']', 100 ] } ] }
          runAfter: {}
          actions: {
            Reject_Below_Floor: {
              type: 'Response'
              inputs: {
                statusCode: 400
                body: { error: 'Budget must be at least EUR 100', requested: '@triggerBody()?[\'newBudgetAmount\']' }
              }
            }
          }
          else: {
            actions: {
              Get_Current_Budget: {
                type: 'Http'
                inputs: {
                  method: 'GET'
                  uri: 'https://management.azure.com/subscriptions/@{triggerBody()?[\'subscriptionId\']}/resourceGroups/@{triggerBody()?[\'resourceGroupName\']}/providers/Microsoft.Consumption/budgets?api-version=2023-11-01'
                  authentication: { type: 'ManagedServiceIdentity' }
                }
                runAfter: {}
              }
              Extract_Current: {
                type: 'Compose'
                inputs: '@if(greater(length(body(\'Get_Current_Budget\')?[\'value\']), 0), body(\'Get_Current_Budget\')?[\'value\'][0]?[\'properties\']?[\'amount\'], 100)'
                runAfter: { Get_Current_Budget: [ 'Succeeded' ] }
              }
              Extract_Name: {
                type: 'Compose'
                inputs: '@if(greater(length(body(\'Get_Current_Budget\')?[\'value\']), 0), body(\'Get_Current_Budget\')?[\'value\'][0]?[\'name\'], concat(\'finops-rg-budget-\', triggerBody()?[\'resourceGroupName\']))'
                runAfter: { Get_Current_Budget: [ 'Succeeded' ] }
              }
              Validate_Cap: {
                type: 'If'
                expression: { and: [ { greater: [ '@triggerBody()?[\'newBudgetAmount\']', '@mul(outputs(\'Extract_Current\'), 3)' ] } ] }
                runAfter: { Extract_Current: [ 'Succeeded' ], Extract_Name: [ 'Succeeded' ] }
                actions: {
                  Reject_Over_Cap: {
                    type: 'Response'
                    inputs: {
                      statusCode: 400
                      body: { error: 'Exceeds 3x cap. Max: EUR @{mul(outputs(\'Extract_Current\'), 3)}', current: '@outputs(\'Extract_Current\')' }
                    }
                  }
                }
                else: {
                  actions: {
                    Update_Budget: {
                      type: 'Http'
                      inputs: {
                        method: 'PUT'
                        uri: 'https://management.azure.com/subscriptions/@{triggerBody()?[\'subscriptionId\']}/resourceGroups/@{triggerBody()?[\'resourceGroupName\']}/providers/Microsoft.Consumption/budgets/@{outputs(\'Extract_Name\')}?api-version=2023-11-01'
                        authentication: { type: 'ManagedServiceIdentity' }
                        body: {
                          properties: {
                            category: 'Cost'
                            amount: '@triggerBody()?[\'newBudgetAmount\']'
                            timeGrain: 'Monthly'
                            timePeriod: { startDate: '@{formatDateTime(startOfMonth(utcNow()), \'yyyy-MM-ddTHH:mm:ssZ\')}', endDate: '2027-03-31T00:00:00Z' }
                            notifications: {
                              Forecasted_90: { enabled: true, operator: 'GreaterThan', threshold: 90, thresholdType: 'Forecasted', contactEmails: [ '@{triggerBody()?[\'requestorEmail\']}', '@parameters(\'finopsEmail\')' ] }
                              Actual_100: { enabled: true, operator: 'GreaterThan', threshold: 100, thresholdType: 'Actual', contactEmails: [ '@{triggerBody()?[\'requestorEmail\']}', '@parameters(\'finopsEmail\')' ] }
                              Forecasted_110: { enabled: true, operator: 'GreaterThan', threshold: 110, thresholdType: 'Forecasted', contactEmails: [ '@{triggerBody()?[\'requestorEmail\']}', '@parameters(\'finopsEmail\')' ] }
                            }
                          }
                        }
                      }
                      runAfter: {}
                    }
                    Update_Cosmos_Inventory: {
                      type: 'Http'
                      inputs: {
                        method: 'POST'
                        uri: 'https://@{parameters(\'functionAppName\')}.azurewebsites.net/api/update-budget?code=@{parameters(\'functionAppKey\')}'
                        body: {
                          subscriptionId: '@triggerBody()?[\'subscriptionId\']'
                          resourceGroupName: '@triggerBody()?[\'resourceGroupName\']'
                          newBudgetAmount: '@triggerBody()?[\'newBudgetAmount\']'
                          requestorEmail: '@triggerBody()?[\'requestorEmail\']'
                          reason: '@triggerBody()?[\'reason\']'
                        }
                      }
                      runAfter: { Update_Budget: [ 'Succeeded' ] }
                    }
                    Notify_Teams: {
                      type: 'Http'
                      inputs: {
                        method: 'POST'
                        uri: '@parameters(\'teamsWebhookUri\')'
                        body: { text: '**[FinOps Budget Changed]** RG: **@{triggerBody()?[\'resourceGroupName\']}** EUR @{outputs(\'Extract_Current\')} → EUR @{triggerBody()?[\'newBudgetAmount\']} | By: @{triggerBody()?[\'requestorEmail\']} | Reason: @{triggerBody()?[\'reason\']}' }
                      }
                      runAfter: { Update_Cosmos_Inventory: [ 'Succeeded' ] }
                    }
                    Success_Response: {
                      type: 'Response'
                      inputs: {
                        statusCode: 200
                        body: {
                          status: 'success'
                          resourceGroup: '@triggerBody()?[\'resourceGroupName\']'
                          oldBudget: '@outputs(\'Extract_Current\')'
                          newBudget: '@triggerBody()?[\'newBudgetAmount\']'
                        }
                      }
                      runAfter: { Notify_Teams: [ 'Succeeded' ] }
                    }
                  }
                }
              }
            }
          }
        }
      }
      outputs: {}
    }
  }
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableRbacAssignment) {
  name: guid(logicApp.id, 'CostManagementContributor-change')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '434105ed-43f6-45c7-a02f-909b2ba83430')
    principalId: logicApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output logicAppId string = logicApp.id
output triggerUrl string = listCallbackUrl(resourceId('Microsoft.Logic/workflows/triggers', logicAppName, 'manual'), '2019-05-01').value
output principalId string = logicApp.identity.principalId
