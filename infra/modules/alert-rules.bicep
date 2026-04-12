// ============================================================
// Scheduled Query Alert Rules Module
// Stage 5b: 3 alert rules against FinOpsInventory_CL table
// HeadUp (60%), Warning (80%), Critical (95%)
// Evaluates hourly, fires via Action Group
// ============================================================

param location string
param tags object = {}

@description('Log Analytics workspace resource ID')
param workspaceId string

@description('Action Group resource ID for alert routing')
param actionGroupId string

// ── HeadUp Alert (60% threshold) ─────────────────────────────
resource alertHeadUp 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'finops-alert-headup'
  location: location
  tags: union(tags, { 'finops-component': 'alert-headup' })
  properties: {
    displayName: 'FinOps HeadUp — RGs at 60%+ budget utilization'
    description: 'Resource groups where amortized spend has reached 60% of budget. Early awareness for FinOps team.'
    severity: 3
    enabled: true
    evaluationFrequency: 'PT1H'
    windowSize: 'PT1H'
    scopes: [
      workspaceId
    ]
    criteria: {
      allOf: [
        {
          query: '''
            FinOpsInventory_CL
            | where actualPct_d >= 60 and actualPct_d < 80
            | where complianceStatus_s != "critical"
            | project resourceGroup_s, actualPct_d, forecastPct_d, amortizedMTD_d, technicalBudget_d, complianceStatus_s, TimeGenerated
            | order by actualPct_d desc
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroupId
      ]
    }
  }
}

// ── Warning Alert (80% threshold) ────────────────────────────
resource alertWarning 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'finops-alert-warning'
  location: location
  tags: union(tags, { 'finops-component': 'alert-warning' })
  properties: {
    displayName: 'FinOps Warning — RGs at 80%+ budget utilization'
    description: 'Resource groups where amortized spend has reached 80% of budget. Action needed to prevent overspend.'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT1H'
    windowSize: 'PT1H'
    scopes: [
      workspaceId
    ]
    criteria: {
      allOf: [
        {
          query: '''
            FinOpsInventory_CL
            | where actualPct_d >= 80 and actualPct_d < 95
            | project resourceGroup_s, actualPct_d, forecastPct_d, amortizedMTD_d, technicalBudget_d, complianceStatus_s, TimeGenerated
            | order by actualPct_d desc
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroupId
      ]
    }
  }
}

// ── Critical Alert (95% threshold) ───────────────────────────
resource alertCritical 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'finops-alert-critical'
  location: location
  tags: union(tags, { 'finops-component': 'alert-critical' })
  properties: {
    displayName: 'FinOps Critical — RGs at 95%+ budget utilization'
    description: 'Resource groups where amortized spend has reached 95% of budget. Immediate action required.'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT1H'
    windowSize: 'PT1H'
    scopes: [
      workspaceId
    ]
    criteria: {
      allOf: [
        {
          query: '''
            FinOpsInventory_CL
            | where actualPct_d >= 95
            | project resourceGroup_s, actualPct_d, forecastPct_d, amortizedMTD_d, technicalBudget_d, complianceStatus_s, TimeGenerated
            | order by actualPct_d desc
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroupId
      ]
    }
  }
}

output alertHeadUpId string = alertHeadUp.id
output alertWarningId string = alertWarning.id
output alertCriticalId string = alertCritical.id
