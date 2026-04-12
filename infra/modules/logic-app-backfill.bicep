// ============================================================
// Logic App: Backfill Existing RGs (Scheduled)
// Runs daily → calls Function App /api/backfill → ensures ALL
// existing RGs have budgets + Cosmos DB inventory entries.
// Replaces manual PowerShell scripts with centralized automation.
// ============================================================

param location string
param logicAppName string = 'la-finops-backfill'
param functionAppName string
param functionAppKey string = ''
param subscriptionId string = subscription().subscriptionId
param tags object = {}

@description('Set to false if deployer lacks User Access Administrator role')
param enableRbacAssignment bool = true

// Reference the existing Function App to get its default hostname
resource functionApp 'Microsoft.Web/sites@2023-12-01' existing = {
  name: functionAppName
}

resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  tags: union(tags, { 'finops-component': 'backfill-scheduler' })
  identity: { type: 'SystemAssigned' }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        functionBaseUrl: { type: 'String', defaultValue: 'https://${functionApp.properties.defaultHostName}' }
        functionKey: { type: 'SecureString', defaultValue: functionAppKey }
        subscriptionId: { type: 'String', defaultValue: subscriptionId }
      }
      triggers: {
        Daily_Backfill: {
          type: 'Recurrence'
          recurrence: {
            frequency: 'Day'
            interval: 1
            schedule: {
              hours: [ '7' ]
              minutes: [ 30 ]
            }
            timeZone: 'UTC'
          }
        }
      }
      actions: {
        // Step 1: Dry-run to see what needs backfilling
        Scan_RGs: {
          type: 'Http'
          inputs: {
            method: 'GET'
            uri: '@{parameters(\'functionBaseUrl\')}/api/backfill?subscriptionId=@{parameters(\'subscriptionId\')}&dryRun=true&code=@{parameters(\'functionKey\')}'
          }
          runAfter: {}
        }
        // Step 2: Check if there are RGs that need backfilling
        Check_Pending: {
          type: 'If'
          expression: {
            and: [
              {
                greater: [
                  '@body(\'Scan_RGs\')?[\'processed\']'
                  0
                ]
              }
            ]
          }
          runAfter: { Scan_RGs: [ 'Succeeded' ] }
          actions: {
            // Step 3: Execute the actual backfill
            Execute_Backfill: {
              type: 'Http'
              inputs: {
                method: 'GET'
                uri: '@{parameters(\'functionBaseUrl\')}/api/backfill?subscriptionId=@{parameters(\'subscriptionId\')}&dryRun=false&code=@{parameters(\'functionKey\')}'
              }
              runAfter: {}
            }
            // Step 4: Log results (compose for run history visibility)
            Log_Results: {
              type: 'Compose'
              inputs: {
                backfillCompleted: true
                processedCount: '@body(\'Execute_Backfill\')?[\'processed\']'
                timestamp: '@utcNow()'
              }
              runAfter: { Execute_Backfill: [ 'Succeeded' ] }
            }
          }
          else: {
            actions: {
              No_Action_Needed: {
                type: 'Compose'
                inputs: {
                  message: 'All RGs already have budgets — no backfill needed'
                  timestamp: '@utcNow()'
                }
                runAfter: {}
              }
            }
          }
        }
      }
      outputs: {}
    }
  }
}

output logicAppId string = logicApp.id
output logicAppName string = logicApp.name
output principalId string = logicApp.identity.principalId
