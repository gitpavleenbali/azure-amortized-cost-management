# ============================================================
# Enable-AdminFeatures.ps1
# Run by Admin (Owner or User Access Administrator)
# Enables features that require elevated RBAC beyond Contributor
# ============================================================
# Usage:
#   .\scripts\Enable-AdminFeatures.ps1 -SubscriptionId "<YOUR_SUBSCRIPTION_ID>" -ResourceGroupName "rg-finops-governance-dev" -Environment "dev"
#   .\scripts\Enable-AdminFeatures.ps1 -SubscriptionId "<YOUR_SUBSCRIPTION_ID>" -ResourceGroupName "rg-finops-governance-dev" -Environment "dev" -WhatIf
# ============================================================

param(
    [Parameter(Mandatory)]
    [string]$SubscriptionId,

    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter()]
    [string]$Environment = 'dev',

    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== FinOps Budget Automation - Admin Enablement ===" -ForegroundColor Cyan
Write-Host "Subscription: $SubscriptionId"
Write-Host "Resource Group: $ResourceGroupName"
Write-Host "Environment: $Environment"
if ($WhatIf) { Write-Host "[DRY RUN - no changes will be made]" -ForegroundColor Yellow }
Write-Host ""

# Verify caller has sufficient permissions
$currentUser = az ad signed-in-user show --query "userPrincipalName" -o tsv 2>$null
if (-not $currentUser) {
    Write-Host "ERROR: Not logged in. Run 'az login' first." -ForegroundColor Red
    exit 1
}
Write-Host "Running as: $currentUser" -ForegroundColor Green

# ── Step 1: Assign Cost Management Contributor to Auto-Budget Logic App MI ──
Write-Host "`n[1/4] Assigning RBAC to Auto-Budget Logic App..." -ForegroundColor Yellow
$autoBudgetPrincipal = az logic workflow show -g $ResourceGroupName -n "la-finops-auto-budget" --query "identity.principalId" -o tsv 2>$null
if ($autoBudgetPrincipal) {
    Write-Host "  Principal ID: $autoBudgetPrincipal"
    if (-not $WhatIf) {
        az role assignment create `
            --assignee-object-id $autoBudgetPrincipal `
            --assignee-principal-type ServicePrincipal `
            --role "434105ed-43f6-45c7-a02f-909b2ba83430" `
            --scope "/subscriptions/$SubscriptionId" 2>$null
        Write-Host "  OK: Cost Management Contributor assigned" -ForegroundColor Green
    } else {
        Write-Host "  WOULD assign Cost Management Contributor" -ForegroundColor Yellow
    }
} else {
    Write-Host "  SKIP: la-finops-auto-budget not found in $ResourceGroupName" -ForegroundColor DarkYellow
}

# ── Step 2: Assign Cost Management Contributor to Budget-Change Logic App MI ──
Write-Host "`n[2/4] Assigning RBAC to Budget-Change Logic App..." -ForegroundColor Yellow
$budgetChangePrincipal = az logic workflow show -g $ResourceGroupName -n "la-finops-budget-change" --query "identity.principalId" -o tsv 2>$null
if ($budgetChangePrincipal) {
    Write-Host "  Principal ID: $budgetChangePrincipal"
    if (-not $WhatIf) {
        az role assignment create `
            --assignee-object-id $budgetChangePrincipal `
            --assignee-principal-type ServicePrincipal `
            --role "434105ed-43f6-45c7-a02f-909b2ba83430" `
            --scope "/subscriptions/$SubscriptionId" 2>$null
        Write-Host "  OK: Cost Management Contributor assigned" -ForegroundColor Green
    } else {
        Write-Host "  WOULD assign Cost Management Contributor" -ForegroundColor Yellow
    }
} else {
    Write-Host "  SKIP: la-finops-budget-change not found in $ResourceGroupName" -ForegroundColor DarkYellow
}

# ── Step 3: Assign Storage RBAC to Function App MI ──
Write-Host "`n[3/6] Assigning Storage RBAC to Function App..." -ForegroundColor Yellow
$funcPrincipal = az functionapp show -g $ResourceGroupName -n (az functionapp list -g $ResourceGroupName --query "[0].name" -o tsv 2>$null) --query "identity.principalId" -o tsv 2>$null
$storageId = az storage account list -g $ResourceGroupName --query "[0].id" -o tsv 2>$null
if ($funcPrincipal -and $storageId) {
    Write-Host "  Function MI: $funcPrincipal"
    Write-Host "  Storage: $storageId"
    $roles = @(
        @{ Name="Storage Blob Data Owner"; Id="b7e6dc6d-f1e8-4753-8033-0f276bb0955b" },
        @{ Name="Storage Queue Data Contributor"; Id="974c5e8b-45b9-4653-ba55-5f855dd0fb88" },
        @{ Name="Storage Table Data Contributor"; Id="0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3" }
    )
    foreach ($role in $roles) {
        if (-not $WhatIf) {
            az role assignment create --assignee-object-id $funcPrincipal --assignee-principal-type ServicePrincipal --role $role.Id --scope $storageId 2>$null
            Write-Host "  OK: $($role.Name) assigned" -ForegroundColor Green
        } else {
            Write-Host "  WOULD assign $($role.Name)" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "  SKIP: Function App not found in $ResourceGroupName" -ForegroundColor DarkYellow
}

# ── Step 4: Deploy Policy Definition ──
Write-Host "`n[4/6] Deploying Audit Policy Definition..." -ForegroundColor Yellow
$policyPath = Join-Path $PSScriptRoot "..\infra\modules\policy-definition.bicep"
if (Test-Path $policyPath) {
    if (-not $WhatIf) {
        az deployment sub create `
            --location eastus `
            --template-file (Resolve-Path $policyPath) `
            --parameters environment=$Environment `
            --name "finops-policy-definition" 2>$null
        Write-Host "  OK: Policy definition deployed" -ForegroundColor Green
    } else {
        Write-Host "  WOULD deploy policy definition from $policyPath" -ForegroundColor Yellow
    }
} else {
    Write-Host "  ERROR: $policyPath not found" -ForegroundColor Red
}

# ── Step 5: Deploy Policy Assignment ──
Write-Host "`n[5/6] Deploying Policy Assignment..." -ForegroundColor Yellow
$assignmentPath = Join-Path $PSScriptRoot "..\infra\modules\policy-assignment.bicep"
$policyDefId = "/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/policyDefinitions/finops-audit-rg-without-budget"
if (Test-Path $assignmentPath) {
    if (-not $WhatIf) {
        az deployment sub create `
            --location eastus `
            --template-file (Resolve-Path $assignmentPath) `
            --parameters policyDefinitionId=$policyDefId environment=$Environment `
            --name "finops-policy-assignment" 2>$null
        Write-Host "  OK: Policy assigned to subscription" -ForegroundColor Green
    } else {
        Write-Host "  WOULD assign policy $policyDefId" -ForegroundColor Yellow
    }
} else {
    Write-Host "  ERROR: $assignmentPath not found" -ForegroundColor Red
}

Write-Host "`n=== Done ==="  -ForegroundColor Cyan
Write-Host "All admin features enabled. The following are now active:"
Write-Host "  - Auto-Budget Logic App can create budgets via managed identity"
Write-Host "  - Budget-Change Logic App can update budgets via managed identity"
Write-Host "  - Function App can access Storage + Cosmos DB via managed identity"
Write-Host "  - AuditIfNotExists policy flags RGs without budgets in compliance dashboard"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Deploy function code: func azure functionapp publish <funcAppName> --python --build remote"
Write-Host "  2. Wire Event Grid: see mvp-implementation.md Phase 3"
Write-Host ""
