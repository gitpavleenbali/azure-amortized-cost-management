<#
.SYNOPSIS
    Post-deployment validation tests (Pester).
    Verifies all FinOps budget infrastructure exists and is configured correctly.

.EXAMPLE
    Invoke-Pester .\tests\infra\Validate-Deployment.Tests.ps1 -Output Detailed
#>

param(
    [string]$Environment = "dev",
    [string]$ResourceGroupName = "rg-finops-governance-$Environment"
)

Describe "FinOps Budget Infrastructure — $Environment" {

    Context "Action Group (QW-01)" {
        It "Action Group 'ag-finops-budget-alerts' exists and is enabled" {
            $ag = az monitor action-group show --resource-group $ResourceGroupName --name "ag-finops-budget-alerts" -o json 2>$null | ConvertFrom-Json
            $ag | Should -Not -BeNullOrEmpty
            $ag.enabled | Should -Be $true
        }

        It "Action Group has at least 1 email receiver" {
            $ag = az monitor action-group show --resource-group $ResourceGroupName --name "ag-finops-budget-alerts" -o json 2>$null | ConvertFrom-Json
            $ag.emailReceivers.Count | Should -BeGreaterThan 0
        }
    }

    Context "Subscription Budget (QW-02)" {
        It "Subscription budget 'finops-sub-budget-$Environment' exists" {
            $budgets = az consumption budget list --query "[?name=='finops-sub-budget-$Environment']" -o json 2>$null | ConvertFrom-Json
            $budgets.Count | Should -BeGreaterThan 0
        }

        It "Subscription budget has 5 notification thresholds" {
            $budgets = az consumption budget list --query "[?name=='finops-sub-budget-$Environment']" -o json 2>$null | ConvertFrom-Json
            $notifCount = ($budgets[0].notifications.PSObject.Properties | Measure-Object).Count
            $notifCount | Should -Be 5
        }
    }

    Context "Policy (QW-04)" {
        It "Policy definition 'finops-audit-rg-without-budget' exists" {
            $pol = az policy definition show --name "finops-audit-rg-without-budget" -o json 2>$null | ConvertFrom-Json
            $pol | Should -Not -BeNullOrEmpty
            $pol.policyType | Should -Be "Custom"
        }

        It "Policy assignment is active on subscription" {
            $assign = az policy assignment list --query "[?contains(name, 'finops-audit-rg-budgets')]" -o json 2>$null | ConvertFrom-Json
            $assign.Count | Should -BeGreaterThan 0
        }
    }

    Context "Storage Account (LT-03)" {
        It "Storage account exists in resource group" {
            $sa = az storage account list --resource-group $ResourceGroupName --query "[?tags.\"finops-platform\"=='budget-alerts-automation']" -o json 2>$null | ConvertFrom-Json
            $sa.Count | Should -BeGreaterThan 0
        }

        It "Budget table 'finopsBudgets' exists" {
            $sa = az storage account list --resource-group $ResourceGroupName --query "[0].name" -o tsv 2>$null
            $tables = az storage table list --account-name $sa --query "[?name=='finopsBudgets']" -o json 2>$null | ConvertFrom-Json
            $tables.Count | Should -BeGreaterThan 0
        }
    }

    Context "Logic Apps (MT-01, MT-02)" {
        It "Auto-budget Logic App exists" -Skip:($Environment -eq "dev" -and -not $env:ENABLE_LOGICAPP_TEST) {
            $la = az logic workflow show --resource-group $ResourceGroupName --name "la-finops-auto-budget" -o json 2>$null | ConvertFrom-Json
            $la | Should -Not -BeNullOrEmpty
            $la.state | Should -Be "Enabled"
        }

        It "Budget-change Logic App exists" -Skip:($Environment -eq "dev" -and -not $env:ENABLE_LOGICAPP_TEST) {
            $la = az logic workflow show --resource-group $ResourceGroupName --name "la-finops-budget-change" -o json 2>$null | ConvertFrom-Json
            $la | Should -Not -BeNullOrEmpty
        }
    }
}
