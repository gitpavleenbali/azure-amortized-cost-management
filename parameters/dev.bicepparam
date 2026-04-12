using '../infra/main.bicep'

param environment = 'dev'
param location = 'eastus2'
param resourceGroupName = 'rg-finops-governance-dev'
param finopsEmail = 'your-finops-team@example.com'
param defaultBudgetAmount = 100
param subscriptionBudgetAmount = 5000
param enableAmortizedPipeline = false  // Enable after cost export has 1 week of data
param enableAutoBudget = true
param enableSelfServiceChange = true
param tags = {
  'finops-platform': 'budget-alerts-automation'
  'managed-by': 'finops-iac'
  environment: 'dev'
  Owner: 'FinOps-Team'
  CostCenter: 'HybridCloud-FinOps'
}
