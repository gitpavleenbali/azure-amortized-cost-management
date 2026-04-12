using '../infra/main.bicep'

param environment = 'prod'
param location = 'westeurope'
param resourceGroupName = 'rg-finops-governance-prod'
param finopsEmail = 'your-finops-team@example.com'
param defaultBudgetAmount = 100
param subscriptionBudgetAmount = 50000
param enableAmortizedPipeline = true
param enableAutoBudget = true
param enableSelfServiceChange = true
param tags = {
  'finops-platform': 'budget-alerts-automation'
  'managed-by': 'finops-iac'
  environment: 'prod'
  Owner: 'FinOps-Team'
  CostCenter: 'HybridCloud-FinOps'
}
