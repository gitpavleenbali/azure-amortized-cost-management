"""
Sync FinOps Inventory from Cosmos DB (via Function API) to Log Analytics.

Usage:
  python Sync-InventoryToLAW.py --workspace-id <GUID> --shared-key <KEY> --func-url <URL>

Or set environment variables:
  LAW_WORKSPACE_ID, LAW_SHARED_KEY, FUNC_INVENTORY_URL

This runs after each daily Function App evaluation to keep Log Analytics
in sync with Cosmos DB. The Azure Workbook reads from Log Analytics.

Schedule: Add to Function App timer OR run via pipeline after /api/evaluate.
"""

import json
import hashlib
import hmac
import base64
import datetime
import os
import sys
import argparse
import requests


def build_signature(customer_id: str, shared_key: str, date: str,
                    content_length: int, method: str, content_type: str,
                    resource: str) -> str:
    x_headers = f"x-ms-date:{date}"
    string_to_hash = f"{method}\n{content_length}\n{content_type}\n{x_headers}\n{resource}"
    decoded_key = base64.b64decode(shared_key)
    encoded_hash = base64.b64encode(
        hmac.new(decoded_key, string_to_hash.encode("utf-8"), digestmod=hashlib.sha256).digest()
    ).decode("utf-8")
    return f"SharedKey {customer_id}:{encoded_hash}"


def post_data(customer_id: str, shared_key: str, body: str, log_type: str) -> int:
    rfc1123date = datetime.datetime.utcnow().strftime("%a, %d %b %Y %H:%M:%S GMT")
    content_length = len(body)
    signature = build_signature(
        customer_id, shared_key, rfc1123date, content_length,
        "POST", "application/json", "/api/logs"
    )
    uri = f"https://{customer_id}.ods.opinsights.azure.com/api/logs?api-version=2016-04-01"
    headers = {
        "content-type": "application/json",
        "Authorization": signature,
        "Log-Type": log_type,
        "x-ms-date": rfc1123date,
    }
    response = requests.post(uri, data=body, headers=headers, timeout=30)
    return response.status_code


def main():
    parser = argparse.ArgumentParser(description="Sync FinOps Inventory to Log Analytics")
    parser.add_argument("--workspace-id", default=os.environ.get("LAW_WORKSPACE_ID", ""))
    parser.add_argument("--shared-key", default=os.environ.get("LAW_SHARED_KEY", ""))
    parser.add_argument("--func-url", default=os.environ.get("FUNC_INVENTORY_URL", ""))
    parser.add_argument("--log-type", default="FinOpsInventory")
    args = parser.parse_args()

    if not args.workspace_id or not args.shared_key or not args.func_url:
        print("ERROR: --workspace-id, --shared-key, and --func-url are required")
        print("  Or set LAW_WORKSPACE_ID, LAW_SHARED_KEY, FUNC_INVENTORY_URL env vars")
        sys.exit(1)

    print(f"Reading inventory from {args.func_url[:60]}...")
    resp = requests.get(args.func_url, timeout=60)
    resp.raise_for_status()
    data = resp.json()
    print(f"Got {len(data)} records")

    clean = []
    for d in data:
        clean.append({
            "resourceGroup": d.get("resourceGroup", ""),
            "subscriptionId": d.get("subscriptionId", ""),
            "technicalBudget": d.get("technicalBudget", 0),
            "financeBudget": d.get("financeBudget", 0),
            "amortizedMTD": d.get("amortizedMTD", 0),
            "forecastEOM": d.get("forecastEOM", 0),
            "actualPct": d.get("actualPct", 0),
            "forecastPct": d.get("forecastPct", 0),
            "burnRateDaily": d.get("burnRateDaily", 0),
            "complianceStatus": d.get("complianceStatus", "not_evaluated"),
            "costCenter": d.get("costCenter", ""),
            "ownerEmail": d.get("ownerEmail", ""),
            "lastEvaluated": d.get("lastEvaluated", ""),
        })

    body = json.dumps(clean)
    print(f"Pushing {len(clean)} records ({len(body)} bytes) to LAW table {args.log_type}_CL...")
    status = post_data(args.workspace_id, args.shared_key, body, args.log_type)
    print(f"Response: {status} ({'OK' if status in (200, 202) else 'ERROR'})")
    sys.exit(0 if status in (200, 202) else 1)


if __name__ == "__main__":
    main()
