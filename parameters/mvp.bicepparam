using '../infra/main.bicep'

param environment = 'dev'                              // Bicep enum only allows dev/staging/prod — MVP maps to dev
param location = 'eastus'                              // Match existing QA subscription region
param resourceGroupName = 'rg-finops-budget-mvp'       // Dedicated MVP resource group
param finopsEmail = 'your-finops-team@example.com'        // FinOps team email for alerts
param defaultBudgetAmount = 100                        // EUR 100 default for new RGs
param subscriptionBudgetAmount = 5000                  // EUR 5000 sub-level (QA is low spend)
param enableAmortizedPipeline = true                   // Function App for FinOps Inventory Engine
param enableAutoBudget = true                          // Core MVP feature — auto-budget on new RGs
param enableSelfServiceChange = true                   // Core MVP feature — self-service budget changes
param enablePolicy = false                             // Requires Resource Policy Contributor — Admin enables later
param enableRbacAssignment = false                     // Requires User Access Administrator — Admin assigns post-deploy
param tags = {
  'finops-platform': 'budget-alerts-automation'
  'managed-by': 'finops-iac'
  environment: 'mvp'
  Owner: 'FinOps-Team'
  CostCenter: 'HybridCloud-FinOps'
}
