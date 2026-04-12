// ============================================================
// Log Analytics Workspace Module
// Central workspace for FinOps inventory data, powering
// workbook dashboards and scheduled query alert rules.
// Stage 4 pipeline: Cosmos DB → _sync_to_law() → LAW
// ============================================================

param location string
param workspaceName string = 'law-finops-budget'
param tags object = {}

@description('Retention in days (30 = free tier)')
param retentionInDays int = 30

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  tags: union(tags, { 'finops-component': 'analytics-workspace' })
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

output workspaceId string = workspace.id
output workspaceName string = workspace.name
output customerId string = workspace.properties.customerId
#disable-next-line outputs-should-not-contain-secrets
output primarySharedKey string = workspace.listKeys().primarySharedKey
