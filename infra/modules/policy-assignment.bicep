// ============================================================
// Policy Assignment Module (QW-04)
// Assigns the audit policy to the subscription scope.
// ============================================================

targetScope = 'subscription'

param policyDefinitionId string
param environment string

resource policyAssignment 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: 'finops-audit-rg-budgets-${environment}'
  properties: {
    displayName: 'FinOps: Audit RGs Without Budget (${environment})'
    policyDefinitionId: policyDefinitionId
    enforcementMode: 'Default'
    metadata: {
      category: 'FinOps'
      environment: environment
    }
  }
}

output assignmentId string = policyAssignment.id
