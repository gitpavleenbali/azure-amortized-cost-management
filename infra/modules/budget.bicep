// ============================================================
// Budget Module (QW-02 / QW-03)
// Creates a budget at subscription or resource group scope.
// Supports per-threshold contact routing via Budgets API.
// ============================================================

targetScope = 'subscription'

@description('Budget name')
param budgetName string

@description('Monthly budget amount in billing currency')
param budgetAmount int

@description('Scope: subscription or resourceGroup')
@allowed(['subscription', 'resourceGroup'])
param scope string = 'subscription'

@description('Resource group name (required if scope is resourceGroup)')
param resourceGroupName string = ''

@description('FinOps team email')
param finopsEmail string

@description('RG owner email (for per-threshold routing)')
param ownerEmail string = ''

@description('BU lead email (added at 75%+)')
param buLeadEmail string = ''

@description('Action Group resource ID')
param actionGroupId string = ''

@description('Budget start date')
param startDate string = '${utcNow('yyyy')}-${utcNow('MM')}-01T00:00:00Z'

@description('Budget end date')
param endDate string = '2027-03-31T00:00:00Z'

param tags object = {}

// Contact arrays for per-threshold routing
var ownerOnly = empty(ownerEmail) ? [finopsEmail] : [ownerEmail]
var ownerPlusBuLead = empty(buLeadEmail) ? ownerOnly : concat(ownerOnly, [buLeadEmail])
var allContacts = union(ownerPlusBuLead, [finopsEmail])
var actionGroupArray = empty(actionGroupId) ? [] : [actionGroupId]

resource budget 'Microsoft.Consumption/budgets@2023-11-01' = {
  name: budgetName
  properties: {
    category: 'Cost'
    amount: budgetAmount
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: startDate
      endDate: endDate
    }
    notifications: {
      // 50% — Owner only, no action group (awareness)
      Actual_GreaterThan_50: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 50
        thresholdType: 'Actual'
        contactEmails: ownerOnly
        contactGroups: []
      }
      // 75% — Owner + BU Lead + Action Group
      Actual_GreaterThan_75: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 75
        thresholdType: 'Actual'
        contactEmails: ownerPlusBuLead
        contactGroups: actionGroupArray
      }
      // 90% — Forecasted — All contacts + Action Group
      Forecasted_GreaterThan_90: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 90
        thresholdType: 'Forecasted'
        contactEmails: allContacts
        contactGroups: actionGroupArray
      }
      // 100% — Actual breach — All contacts + Action Group
      Actual_GreaterThan_100: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 100
        thresholdType: 'Actual'
        contactEmails: allContacts
        contactGroups: actionGroupArray
      }
      // 110% — Forecasted overrun — All contacts + Escalation
      Forecasted_GreaterThan_110: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 110
        thresholdType: 'Forecasted'
        contactEmails: allContacts
        contactGroups: actionGroupArray
      }
    }
  }
}

output budgetId string = budget.id
output budgetName string = budget.name
