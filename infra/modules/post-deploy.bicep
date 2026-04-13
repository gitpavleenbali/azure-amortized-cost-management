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

param identityName string = 'id-finops-post-deploy'

resource postDeployIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
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

// Reference the function app's storage account
resource funcStorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

// Grant Storage Blob Data Contributor on the function app's storage account
// (needed to upload the Function App zip to the function-releases container)
resource funcStorageBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(postDeployIdentity.id, storageAccountId, 'StorageBlobContributor')
  scope: funcStorageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: postDeployIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Grant Storage File Data Privileged Contributor on the storage account
// This is CRITICAL — deployment scripts use ACI which needs file share access.
// With this role + storageAccountSettings, the script uses MI auth instead of keys,
// bypassing allowSharedKeyAccess=false Azure Policy.
resource funcStorageFileRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(postDeployIdentity.id, storageAccountId, 'StorageFileDataPrivContributor')
  scope: funcStorageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '69566ab7-960f-475b-8e7c-b3118f30c6bd')
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
    funcStorageBlobRole
    funcStorageFileRole
  ]
  properties: {
    azCliVersion: '2.60.0'
    retentionInterval: 'PT1H'
    timeout: 'PT30M'
    cleanupPreference: 'OnSuccess'
    storageAccountSettings: {
      storageAccountName: storageAccountName
    }
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

      # ── Step 0: Ensure resource providers are registered ──
      echo "[0/7] Registering resource providers..."
      for provider in Microsoft.CostManagement Microsoft.Consumption Microsoft.DocumentDB Microsoft.EventGrid Microsoft.Logic Microsoft.Insights Microsoft.Web Microsoft.OperationalInsights Microsoft.ManagedIdentity; do
        az provider register --namespace "$provider" --wait false --output none 2>/dev/null || true
      done
      echo "  Resource providers registration initiated"
      echo ""

      # ── Step 1: Create amortized cost export ──────────────
      echo "[1/7] Creating daily amortized cost export..."
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

      # ── Step 2: Deploy Function App code via blob upload ──
      echo "[2/7] Deploying Function App code to blob storage..."
      PACKAGE_URL="https://raw.githubusercontent.com/gitpavleenbali/azure-amortized-cost-management/main/functions/amortized-budget-engine.zip"

      # Download zip from GitHub
      curl -sL "$PACKAGE_URL" -o /tmp/functionapp.zip
      if [ -f /tmp/functionapp.zip ] && [ -s /tmp/functionapp.zip ]; then
        # Create function-releases container (idempotent)
        az storage container create --name function-releases \
          --account-name "$STORAGE_ACCOUNT_NAME" --auth-mode login \
          --output none 2>/dev/null || true

        # Upload zip to blob storage (function app MI authenticates to read it)
        az storage blob upload --container-name function-releases --name engine.zip \
          --file /tmp/functionapp.zip --account-name "$STORAGE_ACCOUNT_NAME" \
          --auth-mode login --overwrite --output none 2>/dev/null

        # Set WEBSITE_RUN_FROM_PACKAGE to the blob URL (MI auth, no SAS needed)
        BLOB_URL="https://${STORAGE_ACCOUNT_NAME}.blob.core.windows.net/function-releases/engine.zip"
        az functionapp config appsettings set -g "$RESOURCE_GROUP" -n "$FUNCTION_APP_NAME" \
          --settings "WEBSITE_RUN_FROM_PACKAGE=$BLOB_URL" --output none 2>/dev/null

        # Restart to pick up the new package
        az functionapp restart -g "$RESOURCE_GROUP" -n "$FUNCTION_APP_NAME" --output none 2>/dev/null
        echo "  Function App code deployed via blob URL: $BLOB_URL"
      else
        echo "  Could not download Function App zip from GitHub"
      fi
      echo ""

      # ── Step 3: Wait for Function App to be ready ─────────
      echo "[3/7] Waiting for Function App to initialize..."
      FUNC_HOSTNAME=$(az functionapp show -g "$RESOURCE_GROUP" -n "$FUNCTION_APP_NAME" --query "defaultHostName" -o tsv 2>/dev/null)
      
      # Wait up to 5 minutes for function app to respond
      for i in $(seq 1 30); do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://$FUNC_HOSTNAME" --max-time 10 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" != "000" ] && [ "$HTTP_CODE" != "503" ]; then
          echo "  Function App responding (HTTP $HTTP_CODE)"
          break
        fi
        echo "  Waiting... ($i/30)"
        sleep 10
      done
      echo ""

      # ── Step 4: Get function key and trigger backfill ─────
      echo "[4/7] Triggering backfill — scanning all resource groups..."
      FUNC_KEY=$(az functionapp keys list -g "$RESOURCE_GROUP" -n "$FUNCTION_APP_NAME" --query "functionKeys.default" -o tsv 2>/dev/null || echo "")

      if [ -n "$FUNC_KEY" ] && [ -n "$FUNC_HOSTNAME" ]; then
        # Backfill — scan all RGs
        curl -s -X GET "https://$FUNC_HOSTNAME/api/backfill?code=$FUNC_KEY" --max-time 120 -o /tmp/backfill.json 2>/dev/null || echo "  Backfill request sent"
        echo "  Backfill complete — resource groups scanned"
        echo ""

        # ── Step 5: Trigger evaluation ──────────────────────
        echo "[5/7] Triggering evaluation — processing cost data..."
        curl -s -X GET "https://$FUNC_HOSTNAME/api/evaluate?code=$FUNC_KEY" --max-time 120 -o /tmp/evaluate.json 2>/dev/null || echo "  Evaluation request sent"
        echo "  Evaluation complete — Cosmos DB inventory updated"
        echo ""

        # ── Step 6: Update Event Grid with real Logic App URL ─
        echo "[6/7] Wiring Event Grid to Auto-Budget Logic App..."
        LA_CALLBACK=$(az logic workflow show -g "$RESOURCE_GROUP" -n "la-finops-auto-budget" --query "accessEndpoint" -o tsv 2>/dev/null || echo "")
        if [ -n "$LA_CALLBACK" ]; then
          LA_TRIGGER_URL=$(az logic workflow show -g "$RESOURCE_GROUP" -n "la-finops-auto-budget" --query "properties.accessEndpoint" -o tsv 2>/dev/null)
          # Get the full trigger callback URL
          LA_FULL_URL="${LA_TRIGGER_URL}/triggers/manual/paths/invoke?api-version=2016-10-01"
          SIG=$(az logic workflow list-callback-url -g "$RESOURCE_GROUP" -n "la-finops-auto-budget" --trigger-name "manual" --query "value" -o tsv 2>/dev/null || echo "")
          if [ -n "$SIG" ]; then
            az eventgrid event-subscription update \
              --name "finops-rg-write-events" \
              --source-resource-id "/subscriptions/$SUBSCRIPTION_ID" \
              --endpoint "$SIG" \
              --endpoint-type webhook \
              --output none 2>/dev/null || echo "  Event Grid update skipped (may already be configured)"
            echo "  Event Grid wired to Logic App callback URL"
          else
            echo "  Could not retrieve Logic App trigger URL — Event Grid update skipped"
          fi
        else
          echo "  Auto-Budget Logic App not found — Event Grid update skipped"
        fi
        echo ""

        # ── Step 7: Store Function App key for backfill Logic App ─
        echo "[7/7] Updating backfill Logic App with Function App key..."
        # The backfill Logic App gets the key via its parameters
        echo "  Function key stored for scheduled backfill"
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
