using '../infra/main.bicep'

param environment = 'staging'
param location = 'westeurope'
param resourceGroupName = 'rg-finops-governance-staging'
param finopsEmail = 'your-finops-team@example.com'
param defaultBudgetAmount = 100
param subscriptionBudgetAmount = 25000
param enableAmortizedPipeline = false  // Enable after dev validation
param enableAutoBudget = true
param enableSelfServiceChange = true
param enablePolicy = true
param enableRbacAssignment = true
param enableFinanceBudget = false      // Enable if finance provides separate budgets per RG
param tags = {
  'finops-platform': 'budget-alerts-automation'
  'managed-by': 'finops-iac'
  environment: 'staging'
  Owner: 'FinOps-Team'
  CostCenter: 'HybridCloud-FinOps'
}
