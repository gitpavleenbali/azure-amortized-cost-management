// ============================================================
// Policy Definition Module (QW-04)
// AuditIfNotExists: flags RGs without a budget.
// ============================================================

targetScope = 'subscription'

param environment string

resource policyDefinition 'Microsoft.Authorization/policyDefinitions@2021-06-01' = {
  name: 'finops-audit-rg-without-budget'
  properties: {
    displayName: 'FinOps: Audit Resource Groups Without Budget'
    description: 'Flags resource groups that do not have a Microsoft.Consumption/budgets resource. FinOps baseline requirement for cost governance.'
    policyType: 'Custom'
    mode: 'All'
    metadata: {
      category: 'FinOps'
      version: '1.0.0'
      environment: environment
    }
    parameters: {
      effect: {
        type: 'String'
        metadata: {
          displayName: 'Effect'
          description: 'AuditIfNotExists flags non-compliance without blocking.'
        }
        allowedValues: [
          'AuditIfNotExists'
          'Disabled'
        ]
        defaultValue: 'AuditIfNotExists'
      }
    }
    policyRule: {
      if: {
        field: 'type'
        equals: 'Microsoft.Resources/subscriptions/resourceGroups'
      }
      then: {
        effect: '[parameters(\'effect\')]'
        details: {
          type: 'Microsoft.Consumption/budgets'
          existenceCondition: {
            field: 'Microsoft.Consumption/budgets/amount'
            greater: 0
          }
        }
      }
    }
  }
}

output policyDefinitionId string = policyDefinition.id
output policyDefinitionName string = policyDefinition.name
