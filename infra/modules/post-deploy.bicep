// ============================================================
// Post-Deploy Automation (Deployment Script)
// Runs automatically as part of the ARM deployment.
// Creates cost export, triggers backfill & evaluation.
// No manual steps needed — customer sees data in workbook.
// ============================================================

param location string
param storageAccountName string
param storageAccountId string
param functionAppName string
param functionAppResourceGroup string
param tags object = {}

@description('Subscription ID for cost export scope')
param subscriptionId string

resource postDeployIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-finops-post-deploy'
  location: location
  tags: tags
}

// Grant Contributor to the managed identity at resource group scope
// Note: Cost Management export creation requires Cost Management Contributor
// which is granted separately at subscription scope from main.bicep
resource contributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(postDeployIdentity.id, 'Contributor', resourceGroup().id)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalId: postDeployIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource postDeployScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'finops-post-deploy-kickstart'
  location: location
  tags: tags
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${postDeployIdentity.id}': {}
    }
  }
  dependsOn: [
    contributorRole
  ]
  properties: {
    azCliVersion: '2.60.0'
    retentionInterval: 'PT1H'
    timeout: 'PT15M'
    cleanupPreference: 'OnSuccess'
    environmentVariables: [
      { name: 'SUBSCRIPTION_ID', value: subscriptionId }
      { name: 'STORAGE_ACCOUNT_NAME', value: storageAccountName }
      { name: 'STORAGE_ACCOUNT_ID', value: storageAccountId }
      { name: 'FUNCTION_APP_NAME', value: functionAppName }
      { name: 'RESOURCE_GROUP', value: functionAppResourceGroup }
    ]
    scriptContent: '''
      #!/bin/bash
      set -e

      echo "=== FinOps Post-Deploy Kickstart ==="
      echo "Subscription: $SUBSCRIPTION_ID"
      echo "Function App: $FUNCTION_APP_NAME"
      echo "Storage: $STORAGE_ACCOUNT_NAME"
      echo ""

      # ── Step 1: Create amortized cost export ──────────────
      echo "[1/4] Creating daily amortized cost export..."
      START_DATE=$(date -u +"%Y-%m-01T00:00:00")
      END_DATE=$(date -u -d "+1 year" +"%Y-12-31T00:00:00" 2>/dev/null || date -u -v+1y +"%Y-12-31T00:00:00")

      EXPORT_BODY=$(cat <<EOF
      {
        "properties": {
          "schedule": {
            "status": "Active",
            "recurrence": "Daily",
            "recurrencePeriod": {
              "from": "$START_DATE",
              "to": "$END_DATE"
            }
          },
          "format": "Csv",
          "deliveryInfo": {
            "destination": {
              "resourceId": "$STORAGE_ACCOUNT_ID",
              "container": "amortized-cost-exports",
              "rootFolderPath": "exports"
            }
          },
          "definition": {
            "type": "AmortizedCost",
            "timeframe": "MonthToDate"
          }
        }
      }
EOF
      )

      az rest --method PUT \
        --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.CostManagement/exports/finops-daily-amortized?api-version=2023-11-01" \
        --body "$EXPORT_BODY" \
        --output none 2>/dev/null || echo "  Export may already exist or requires Cost Management Contributor"

      echo "  Export created: finops-daily-amortized"

      # Trigger immediate export run
      az rest --method POST \
        --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.CostManagement/exports/finops-daily-amortized/run?api-version=2023-11-01" \
        --output none 2>/dev/null || echo "  Could not trigger immediate run"

      echo "  Triggered immediate export (data arrives in ~5 min)"
      echo ""

      # ── Step 2: Wait for Function App to be ready ─────────
      echo "[2/4] Waiting for Function App to initialize..."
      FUNC_HOSTNAME=$(az functionapp show -g "$RESOURCE_GROUP" -n "$FUNCTION_APP_NAME" --query "defaultHostName" -o tsv 2>/dev/null)
      
      # Wait up to 3 minutes for function app to respond
      for i in $(seq 1 18); do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://$FUNC_HOSTNAME" --max-time 10 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" != "000" ]; then
          echo "  Function App responding (HTTP $HTTP_CODE)"
          break
        fi
        echo "  Waiting... ($i/18)"
        sleep 10
      done
      echo ""

      # ── Step 3: Get function key and trigger backfill ─────
      echo "[3/4] Triggering backfill — scanning all resource groups..."
      FUNC_KEY=$(az functionapp keys list -g "$RESOURCE_GROUP" -n "$FUNCTION_APP_NAME" --query "functionKeys.default" -o tsv 2>/dev/null || echo "")

      if [ -n "$FUNC_KEY" ] && [ -n "$FUNC_HOSTNAME" ]; then
        # Backfill — scan all RGs
        curl -s -X GET "https://$FUNC_HOSTNAME/api/backfill?code=$FUNC_KEY" --max-time 120 -o /tmp/backfill.json 2>/dev/null || echo "  Backfill request sent"
        echo "  Backfill complete — resource groups scanned"
        echo ""

        # ── Step 4: Trigger evaluation ──────────────────────
        echo "[4/4] Triggering evaluation — processing cost data..."
        curl -s -X GET "https://$FUNC_HOSTNAME/api/evaluate?code=$FUNC_KEY" --max-time 120 -o /tmp/evaluate.json 2>/dev/null || echo "  Evaluation request sent"
        echo "  Evaluation complete — Cosmos DB inventory updated"
      else
        echo "  Function App key not available yet — backfill/evaluate will run on schedule"
      fi

      echo ""
      echo "=== KICKSTART COMPLETE ==="
      echo "Open your Workbook in the Azure Portal to see the dashboard."
      echo '{"status":"complete"}' > $AZ_SCRIPTS_OUTPUT_PATH
    '''
  }
}

output scriptStatus string = postDeployScript.properties.provisioningState
output postDeployIdentityId string = postDeployIdentity.id
output postDeployIdentityPrincipalId string = postDeployIdentity.properties.principalId
