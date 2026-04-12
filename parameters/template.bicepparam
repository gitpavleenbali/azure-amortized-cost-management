using '../infra/main.bicep'

// ============================================================
// Template parameter file for multi-subscription deployment
// Copy this file and rename for each subscription:
//   qa.bicepparam, staging.bicepparam, prod-hc.bicepparam, etc.
// ============================================================

// ── Required: Set per subscription ──────────────────────────
param environment = 'dev'                        // dev | staging | prod
param location = 'eastus'                       // Azure region
param resourceGroupName = 'rg-finops-budget'    // No env suffix — pipeline adds it
param finopsEmail = 'your-finops-team@example.com' // FinOps team email

// ── Budget defaults ─────────────────────────────────────────
param defaultBudgetAmount = 100                 // EUR 100 per RG
param subscriptionBudgetAmount = 5000           // EUR 5K per subscription

// ── Feature flags ───────────────────────────────────────────
param enableAmortizedPipeline = true            // Enable after cost export created
param enableAutoBudget = true                   // Auto EUR 100 on new RGs
param enableSelfServiceChange = true            // Budget change Logic App
param enablePolicy = true                       // Audit policy for RGs without budgets
param enableRbacAssignment = true               // Assign MI roles (needs User Access Admin)

// ── Tags ────────────────────────────────────────────────────
param tags = {
  'finops-platform': 'budget-alerts-automation'
  'managed-by': 'finops-iac'
  environment: 'qa'
  Owner: 'FinOps-Team'
  CostCenter: 'HybridCloud-FinOps'
}
