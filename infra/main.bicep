// ============================================================
// FinOps Budget Alerts Automation — Main Orchestrator
// Deploys all infrastructure for the budget management platform.
// ============================================================
// Deployment scope: SUBSCRIPTION
// Usage:
//   az deployment sub create --location westeurope \
//     --template-file infra/main.bicep \
//     --parameters parameters/dev.bicepparam
// ============================================================

targetScope = 'subscription'

// ── Parameters ───────────────────────────────────────────────
@description('Environment name — used in resource naming (e.g. dev, staging, prod, uat, sandbox)')
@minLength(2)
@maxLength(10)
param environment string

@description('Azure region for resource deployment')
param location string = 'westeurope'

@description('Resource group for FinOps governance resources')
param resourceGroupName string = 'rg-finops-governance-${environment}'

@description('FinOps team email for alert routing')
param finopsEmail string

@description('Teams incoming webhook URL for budget alert channel')
@secure()
param teamsWebhookUri string = ''

@description('Default budget amount for new resource groups (EUR)')
param defaultBudgetAmount int = 100

@description('Monthly subscription-level budget (EUR)')
param subscriptionBudgetAmount int = 10000

@description('Tags to apply to all resources')
param tags object = {
  'finops-platform': 'budget-alerts-automation'
  'managed-by': 'finops-iac'
  environment: environment
  Owner: 'FinOps-Team'
  CostCenter: 'HybridCloud-FinOps'
}

@description('Enable amortized cost pipeline (Function App, Log Analytics, Alert Rules, Workbook)')
param enableAmortizedPipeline bool = true

@description('Enable auto-budget Logic App for new RG creation')
param enableAutoBudget bool = true

@description('Enable self-service budget change Logic App')
param enableSelfServiceChange bool = true

@description('Enable policy definition and assignment (requires Resource Policy Contributor)')
param enablePolicy bool = true

@description('Enable RBAC role assignments for Logic App managed identities (requires User Access Administrator)')
param enableRbacAssignment bool = true

@description('Function App host key for Cosmos sync from budget-change Logic App (set post-deploy)')
@secure()
param functionAppKey string = ''

@description('Budget start date (first of current month). Once a budget is created, the start date cannot be changed — delete and recreate instead.')
param budgetStartDate string = '2026-04-01T00:00:00Z'

// ── Naming Overrides ─────────────────────────────────────────
@description('Custom name for the Action Group (leave blank for default: ag-finops-budget-alerts)')
param actionGroupNameOverride string = ''

@description('Custom name for the Cosmos DB account (leave blank for auto-generated unique name)')
param cosmosAccountNameOverride string = ''

@description('Custom name for the Storage Account (leave blank for auto-generated unique name)')
param storageAccountNameOverride string = ''

@description('Custom name for the Function App (leave blank for auto-generated unique name)')
param functionAppNameOverride string = ''

@description('Custom name for the Auto-Budget Logic App (leave blank for default: la-finops-auto-budget)')
param logicAppAutoBudgetNameOverride string = ''

@description('Custom name for the Budget Change Logic App (leave blank for default: la-finops-budget-change)')
param logicAppBudgetChangeNameOverride string = ''

@description('Custom name for the Backfill Logic App (leave blank for default: la-finops-backfill)')
param logicAppBackfillNameOverride string = ''

// ── Networking (v2) ──────────────────────────────────────────
@description('Enable private networking — deploys VNet, private endpoints for Cosmos DB & Storage, and Function App VNet integration')
param enablePrivateNetworking bool = false

@description('VNet name (only used when enablePrivateNetworking = true)')
param vnetName string = 'vnet-finops-governance'

@description('VNet address space (only used when enablePrivateNetworking = true)')
param vnetAddressPrefix string = '10.100.0.0/24'

// ── Computed Names ───────────────────────────────────────────
var actionGroupName = empty(actionGroupNameOverride) ? 'ag-finops-budget-alerts' : actionGroupNameOverride
var cosmosAccountName = empty(cosmosAccountNameOverride) ? 'cosmos-finops-${uniqueString(rg.id)}' : cosmosAccountNameOverride
var storageAccountComputedName = empty(storageAccountNameOverride) ? 'sa${environment}${uniqueString(rg.id, subscription().subscriptionId)}' : storageAccountNameOverride
var functionAppComputedName = empty(functionAppNameOverride) ? 'func-finops-amortized-${uniqueString(rg.id)}' : functionAppNameOverride
var logicAppAutoBudgetName = empty(logicAppAutoBudgetNameOverride) ? 'la-finops-auto-budget' : logicAppAutoBudgetNameOverride
var logicAppBudgetChangeName = empty(logicAppBudgetChangeNameOverride) ? 'la-finops-budget-change' : logicAppBudgetChangeNameOverride
var logicAppBackfillName = empty(logicAppBackfillNameOverride) ? 'la-finops-backfill' : logicAppBackfillNameOverride

// ── Resource Group ───────────────────────────────────────────
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ── Module 1: Action Group (QW-01) ──────────────────────────
module actionGroup 'modules/action-group.bicep' = {
  name: 'deploy-action-group'
  scope: rg
  params: {
    location: 'Global'
    actionGroupName: actionGroupName
    finopsEmail: finopsEmail
    teamsWebhookUri: teamsWebhookUri
    tags: tags
  }
}

// ── Module 2: Subscription Budget (QW-02) ────────────────────
module subscriptionBudget 'modules/budget.bicep' = {
  name: 'deploy-subscription-budget-${location}'
  params: {
    budgetName: 'finops-sub-budget-${environment}'
    budgetAmount: subscriptionBudgetAmount
    scope: 'subscription'
    finopsEmail: finopsEmail
    actionGroupId: actionGroup.outputs.actionGroupId
    startDate: budgetStartDate
    tags: tags
  }
}

// ── Module 3: Policy Definition (QW-04) ──────────────────────
module policyDefinition 'modules/policy-definition.bicep' = if (enablePolicy) {
  name: 'deploy-policy-definition-${location}'
  params: {
    environment: environment
  }
}

// ── Module 4: Policy Assignment (QW-04) ──────────────────────
module policyAssignment 'modules/policy-assignment.bicep' = if (enablePolicy) {
  name: 'deploy-policy-assignment-${location}'
  params: {
    policyDefinitionId: policyDefinition.outputs.policyDefinitionId
    environment: environment
  }
  dependsOn: [
    policyDefinition
  ]
}

// ── Module 5: Storage Account (LT-03 + QW-05) ───────────────
module storageAccount 'modules/storage-account.bicep' = {
  name: 'deploy-storage-account'
  scope: rg
  params: {
    location: location
    environment: environment
    storageAccountName: storageAccountComputedName
    tags: tags
  }
}

// ── Module 5b: Cosmos DB — FinOps Inventory ──────────────────
module cosmosDb 'modules/cosmos-db.bicep' = {
  name: 'deploy-cosmos-db'
  scope: rg
  params: {
    location: location
    cosmosAccountName: cosmosAccountName
    tags: tags
  }
}

// ── Module 6: Auto-Budget Logic App (MT-01) ──────────────────
module autoBudgetLogicApp 'modules/logic-app-auto-budget.bicep' = if (enableAutoBudget) {
  name: 'deploy-auto-budget-logic-app'
  scope: rg
  params: {
    location: location
    logicAppName: logicAppAutoBudgetName
    finopsEmail: finopsEmail
    defaultBudgetAmount: defaultBudgetAmount
    teamsWebhookUri: teamsWebhookUri
    tags: tags
    enableRbacAssignment: enableRbacAssignment
  }
}

// ── Module 7: Self-Service Budget Change Logic App (MT-02) ───
module budgetChangeLogicApp 'modules/logic-app-budget-change.bicep' = if (enableSelfServiceChange) {
  name: 'deploy-budget-change-logic-app'
  scope: rg
  params: {
    location: location
    logicAppName: logicAppBudgetChangeName
    finopsEmail: finopsEmail
    teamsWebhookUri: teamsWebhookUri
    functionAppName: enableAmortizedPipeline ? functionApp.outputs.functionAppName : ''
    functionAppKey: functionAppKey
    tags: tags
    enableRbacAssignment: enableRbacAssignment
  }
}

// ── Module 7b: Backfill Logic App (Scheduled — existing RGs) ─
module backfillLogicApp 'modules/logic-app-backfill.bicep' = if (enableAmortizedPipeline && enableAutoBudget) {
  name: 'deploy-backfill-logic-app'
  scope: rg
  params: {
    location: location
    logicAppName: logicAppBackfillName
    functionAppName: functionApp.outputs.functionAppName
    subscriptionId: subscription().subscriptionId
    tags: tags
    enableRbacAssignment: enableRbacAssignment
  }
  dependsOn: [
    functionApp
  ]
}

// ── Module 8: Event Grid Subscription (MT-01 trigger) ────────
// NOTE: Event Grid subscription requires the Logic App callback URL.
// This is set to a placeholder during initial deployment.
// After deployment, update via: az eventgrid event-subscription create
// The pipeline handles this in the post-deployment step.
module eventGrid 'modules/event-grid.bicep' = if (enableAutoBudget) {
  name: 'deploy-event-grid-${location}'
  params: {
    logicAppCallbackUrl: 'https://placeholder-configure-post-deploy'
  }
  dependsOn: [
    autoBudgetLogicApp
  ]
}

// ── Module 9: Function App for Amortized Pipeline (LT-01) ───
module functionApp 'modules/function-app.bicep' = if (enableAmortizedPipeline) {
  name: 'deploy-function-app'
  scope: rg
  params: {
    location: location
    functionAppName: functionAppComputedName
    storageAccountName: storageAccount.outputs.storageAccountName
    cosmosEndpoint: cosmosDb.outputs.cosmosEndpoint
    cosmosDatabaseName: cosmosDb.outputs.cosmosDatabaseName
    cosmosContainerName: cosmosDb.outputs.cosmosContainerName
    teamsWebhookUri: teamsWebhookUri
    finopsEmail: finopsEmail
    tags: tags
    enableRbacAssignment: enableRbacAssignment
  }
}

// ── Module 10: Networking (v2 — Private Endpoints) ─────────────
module networking 'modules/networking.bicep' = if (enablePrivateNetworking) {
  name: 'deploy-networking'
  scope: rg
  params: {
    location: location
    vnetName: vnetName
    vnetAddressPrefix: vnetAddressPrefix
    cosmosAccountId: cosmosDb.outputs.cosmosAccountId
    cosmosAccountName: cosmosDb.outputs.cosmosAccountName
    storageAccountId: storageAccount.outputs.storageAccountId
    storageAccountName: storageAccount.outputs.storageAccountName
    functionAppId: enableAmortizedPipeline ? functionApp.outputs.functionAppId : ''
    functionAppName: enableAmortizedPipeline ? functionApp.outputs.functionAppName : ''
    tags: tags
  }
  dependsOn: [
    cosmosDb
    storageAccount
  ]
}

// ── Outputs ──────────────────────────────────────────────────
output resourceGroupName string = rg.name
output actionGroupId string = actionGroup.outputs.actionGroupId
output storageAccountName string = storageAccount.outputs.storageAccountName
output subscriptionBudgetId string = subscriptionBudget.outputs.budgetId
output policyDefinitionId string = enablePolicy ? policyDefinition.outputs.policyDefinitionId : 'disabled'
output autoBudgetLogicAppUrl string = enableAutoBudget ? autoBudgetLogicApp.outputs.logicAppId : 'disabled'
output budgetChangeLogicAppUrl string = enableSelfServiceChange ? budgetChangeLogicApp.outputs.triggerUrl : 'disabled'
output cosmosEndpoint string = cosmosDb.outputs.cosmosEndpoint
output cosmosAccountName string = cosmosDb.outputs.cosmosAccountName
