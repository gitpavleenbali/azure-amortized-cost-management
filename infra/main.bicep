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
@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
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

@description('Enable amortized cost pipeline (requires Function App)')
param enableAmortizedPipeline bool = false

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
    finopsEmail: finopsEmail
    teamsWebhookUri: teamsWebhookUri
    tags: tags
  }
}

// ── Module 2: Subscription Budget (QW-02) ────────────────────
module subscriptionBudget 'modules/budget.bicep' = {
  name: 'deploy-subscription-budget'
  params: {
    budgetName: 'finops-sub-budget-${environment}'
    budgetAmount: subscriptionBudgetAmount
    scope: 'subscription'
    finopsEmail: finopsEmail
    actionGroupId: actionGroup.outputs.actionGroupId
    tags: tags
  }
}

// ── Module 3: Policy Definition (QW-04) ──────────────────────
module policyDefinition 'modules/policy-definition.bicep' = if (enablePolicy) {
  name: 'deploy-policy-definition'
  params: {
    environment: environment
  }
}

// ── Module 4: Policy Assignment (QW-04) ──────────────────────
module policyAssignment 'modules/policy-assignment.bicep' = if (enablePolicy) {
  name: 'deploy-policy-assignment'
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
    tags: tags
  }
}

// ── Module 5b: Cosmos DB — FinOps Inventory ──────────────────
module cosmosDb 'modules/cosmos-db.bicep' = {
  name: 'deploy-cosmos-db'
  scope: rg
  params: {
    location: location
    cosmosAccountName: 'cosmos-finops-${uniqueString(rg.id)}'
    tags: tags
  }
}

// ── Module 6: Auto-Budget Logic App (MT-01) ──────────────────
module autoBudgetLogicApp 'modules/logic-app-auto-budget.bicep' = if (enableAutoBudget) {
  name: 'deploy-auto-budget-logic-app'
  scope: rg
  params: {
    location: location
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
  name: 'deploy-event-grid'
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
