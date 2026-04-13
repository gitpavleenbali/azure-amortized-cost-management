// ============================================================
// Data Collection Rule (DCR) for Log Analytics
// Enables MI-authenticated log ingestion (no shared keys).
// Uses Logs Ingestion API instead of HTTP Data Collector API.
// ============================================================

param location string
param workspaceId string
param tags object = {}

@description('Name of the Data Collection Endpoint')
param dceName string = 'dce-finops-inventory'

@description('Name of the Data Collection Rule')
param dcrName string = 'dcr-finops-inventory'

// Data Collection Endpoint — provides the ingestion URL
resource dce 'Microsoft.Insights/dataCollectionEndpoints@2023-03-11' = {
  name: dceName
  location: location
  tags: tags
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

// Custom table definition in the LAW workspace
// The table schema for FinOpsInventory_CL
resource customTable 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  name: '${split(workspaceId, '/')[8]}/FinOpsInventory_CL'
  properties: {
    schema: {
      name: 'FinOpsInventory_CL'
      columns: [
        { name: 'TimeGenerated', type: 'datetime' }
        { name: 'resourceGroup', type: 'string' }
        { name: 'subscriptionId', type: 'string' }
        { name: 'technicalBudget', type: 'real' }
        { name: 'financeBudget', type: 'real' }
        { name: 'amortizedMTD', type: 'real' }
        { name: 'forecastEOM', type: 'real' }
        { name: 'actualPct', type: 'real' }
        { name: 'forecastPct', type: 'real' }
        { name: 'burnRateDaily', type: 'real' }
        { name: 'complianceStatus', type: 'string' }
        { name: 'costCenter', type: 'string' }
        { name: 'ownerEmail', type: 'string' }
        { name: 'technicalContact1', type: 'string' }
        { name: 'technicalContact2', type: 'string' }
        { name: 'billingContact', type: 'string' }
        { name: 'spendTier', type: 'string' }
        { name: 'governanceTagValue', type: 'string' }
        { name: 'lastEvaluated', type: 'string' }
      ]
    }
    retentionInDays: 90
  }
}

// Data Collection Rule — defines the stream, destination, and data flow
resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: dcrName
  location: location
  tags: tags
  properties: {
    dataCollectionEndpointId: dce.id
    streamDeclarations: {
      'Custom-FinOpsInventory_CL': {
        columns: [
          { name: 'TimeGenerated', type: 'datetime' }
          { name: 'resourceGroup', type: 'string' }
          { name: 'subscriptionId', type: 'string' }
          { name: 'technicalBudget', type: 'real' }
          { name: 'financeBudget', type: 'real' }
          { name: 'amortizedMTD', type: 'real' }
          { name: 'forecastEOM', type: 'real' }
          { name: 'actualPct', type: 'real' }
          { name: 'forecastPct', type: 'real' }
          { name: 'burnRateDaily', type: 'real' }
          { name: 'complianceStatus', type: 'string' }
          { name: 'costCenter', type: 'string' }
          { name: 'ownerEmail', type: 'string' }
          { name: 'technicalContact1', type: 'string' }
          { name: 'technicalContact2', type: 'string' }
          { name: 'billingContact', type: 'string' }
          { name: 'spendTier', type: 'string' }
          { name: 'governanceTagValue', type: 'string' }
          { name: 'lastEvaluated', type: 'string' }
        ]
      }
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: workspaceId
          name: 'finopsLAW'
        }
      ]
    }
    dataFlows: [
      {
        streams: ['Custom-FinOpsInventory_CL']
        destinations: ['finopsLAW']
        transformKql: 'source'
        outputStream: 'Custom-FinOpsInventory_CL'
      }
    ]
  }
  dependsOn: [
    customTable
  ]
}

output dceEndpoint string = dce.properties.logsIngestion.endpoint
output dcrRuleId string = dcr.properties.immutableId
output dcrId string = dcr.id
