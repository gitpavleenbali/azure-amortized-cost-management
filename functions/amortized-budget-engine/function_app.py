"""
FinOps Inventory Engine — Azure Function (Python 3.11)

Azure Amortized Cost Management — Core Evaluation Engine
Timer: Daily 06:00 UTC | HTTP: /api/evaluate (manual) | HTTP: /api/inventory (read)

Architecture: FinOps Inventory (Cosmos DB)
  - Cosmos DB = single source of truth for ALL budget data
  - Columns: technical budget, finance budget, amortized MTD, actual MTD,
    forecast, variance, compliance status, last evaluated
  - Function reads amortized export, updates inventory, evaluates thresholds
  - Power BI / dashboards query the inventory table directly
  - Supports: Finance vs Technical budget comparison (executive variance view)

Pipeline: Cost Export blob -> this Function -> update inventory -> Teams alert
"""

import azure.functions as func
import logging
import os
import json
import csv
import io
import hashlib
import hmac
import base64
import requests
from datetime import datetime, timezone
from azure.identity import DefaultAzureCredential
from azure.cosmos import CosmosClient
from azure.storage.blob import BlobServiceClient

app = func.FunctionApp()

STORAGE_ACCOUNT = os.environ.get("STORAGE_ACCOUNT_NAME", "")
CONTAINER       = os.environ.get("STORAGE_CONTAINER_NAME", "amortized-cost-exports")
COSMOS_ENDPOINT = os.environ.get("COSMOS_ENDPOINT", "")
COSMOS_DATABASE = os.environ.get("COSMOS_DATABASE", "finops")
COSMOS_CONTAINER = os.environ.get("COSMOS_CONTAINER", "inventory")
TEAMS_WEBHOOK   = os.environ.get("TEAMS_WEBHOOK_URL", "")
FINOPS_EMAIL    = os.environ.get("FINOPS_EMAIL", "")
GOVERNANCE_EMAIL = os.environ.get("GOVERNANCE_EMAIL", "")
LAW_WORKSPACE_ID = os.environ.get("LAW_WORKSPACE_ID", "")
LAW_SHARED_KEY   = os.environ.get("LAW_SHARED_KEY", "")

# Excluded RG prefixes — configurable via app setting. Empty = include ALL RGs.
# Set EXCLUDED_RG_PREFIXES="MC_,FL_,MA_,NetworkWatcherRG" to filter system RGs.
EXCLUDED_RG_PREFIXES = [p.strip() for p in os.environ.get("EXCLUDED_RG_PREFIXES", "").split(",") if p.strip()]

# Governance tag alerting — configurable tag key/value that triggers immediate governance notification.
# Example: GOVERNANCE_TAG_KEY="CostCategory" GOVERNANCE_TAG_VALUE="Restricted"
GOVERNANCE_TAG_KEY   = os.environ.get("GOVERNANCE_TAG_KEY", "")
GOVERNANCE_TAG_VALUE = os.environ.get("GOVERNANCE_TAG_VALUE", "")

# ── Budget Alert Notification Framework — Tiered Thresholds ──
# Thresholds scale by 3-month avg spend. Smaller RGs tolerate more variance.
# Each tier: {"headup": %, "warning": %, "critical": %}
SPEND_TIERS = {
    "0-1K":   {"min": 0,     "max": 1000,  "headup": 200, "warning": 250, "critical": 300},
    "1K-5K":  {"min": 1000,  "max": 5000,  "headup": 150, "warning": 200, "critical": 250},
    "5K-10K": {"min": 5000,  "max": 10000, "headup": 125, "warning": 150, "critical": 200},
    "10K+":   {"min": 10000, "max": 1e12,  "headup": 100, "warning": 125, "critical": 150},
}


def _classify_spend_tier(budget: float) -> tuple:
    """Return (tier_name, thresholds_dict) based on the budget amount."""
    for name, tier in SPEND_TIERS.items():
        if tier["min"] <= budget < tier["max"]:
            return name, tier
    return "10K+", SPEND_TIERS["10K+"]


def _read_rg_tags(sub_id: str, rg_name: str) -> dict:
    """Read tags from an Azure Resource Group for alert routing."""
    try:
        cred = DefaultAzureCredential()
        token = cred.get_token("https://management.azure.com/.default").token
        url = f"https://management.azure.com/subscriptions/{sub_id}/resourcegroups/{rg_name}?api-version=2024-03-01"
        resp = requests.get(url, headers={"Authorization": f"Bearer {token}"}, timeout=10)
        if resp.status_code == 200:
            return resp.json().get("tags", {}) or {}
    except Exception as ex:
        logging.warning(f"Tag read failed for {rg_name}: {ex}")
    return {}


# ── Timer: Daily evaluation at 06:00 UTC ──────────────────────
@app.timer_trigger(schedule="0 0 6 * * *", arg_name="timer", run_on_startup=False, use_monitor=True)
def evaluate_amortized_budgets(timer: func.TimerRequest) -> None:
    """Daily evaluation: read amortized costs, update inventory, dispatch alerts, sync to LAW."""
    logging.info("=== FinOps Inventory Engine -- Start ===")
    result = _run_evaluation()
    logging.info(f"=== FinOps Inventory Engine -- Done ({result['alerts_sent']} alerts) ===")
    # Auto-sync inventory to Log Analytics for Workbook dashboard
    synced = _sync_inventory_to_law()
    logging.info(f"=== LAW Sync: {synced} ===")


# ── HTTP: Manual evaluation trigger ───────────────────────────
@app.route(route="evaluate", auth_level=func.AuthLevel.FUNCTION)
def manual_evaluate(req: func.HttpRequest) -> func.HttpResponse:
    """HTTP trigger for on-demand evaluation."""
    try:
        result = _run_evaluation()
        synced = _sync_inventory_to_law()
        result["law_sync"] = synced
        return func.HttpResponse(json.dumps(result), mimetype="application/json")
    except Exception as e:
        return func.HttpResponse(json.dumps({"error": str(e)}), status_code=500, mimetype="application/json")


# ── HTTP: Read inventory (for dashboards / Power BI) ──────────
@app.route(route="inventory", auth_level=func.AuthLevel.FUNCTION)
def get_inventory(req: func.HttpRequest) -> func.HttpResponse:
    """Returns the full FinOps inventory as JSON for dashboard consumption."""
    try:
        sub_filter = req.params.get("subscriptionId", "")
        status_filter = req.params.get("status", "")

        cosmos_container = _get_cosmos_container()
        query = "SELECT * FROM c"
        params = []
        conditions = []
        if sub_filter:
            conditions.append("c.subscriptionId = @sub")
            params.append({"name": "@sub", "value": sub_filter})
        if status_filter:
            conditions.append("c.complianceStatus = @status")
            params.append({"name": "@status", "value": status_filter})
        if conditions:
            query += " WHERE " + " AND ".join(conditions)

        rows = list(cosmos_container.query_items(query=query, parameters=params, enable_cross_partition_query=True))
        return func.HttpResponse(json.dumps(rows, default=str), mimetype="application/json")
    except Exception as e:
        return func.HttpResponse(json.dumps({"error": str(e)}), status_code=500, mimetype="application/json")


# ── HTTP: Finance vs Technical variance report ────────────────
@app.route(route="variance", auth_level=func.AuthLevel.FUNCTION)
def get_variance(req: func.HttpRequest) -> func.HttpResponse:
    """Returns finance vs technical budget variance for exec dashboard."""
    try:
        cosmos_container = _get_cosmos_container()
        items = list(cosmos_container.query_items(
            query="SELECT * FROM c WHERE c.financeBudget > 0 OR c.technicalBudget > 0",
            enable_cross_partition_query=True
        ))

        report = []
        for e in items:
            finance = float(e.get("financeBudget", 0))
            technical = float(e.get("technicalBudget", 0))
            amortized = float(e.get("amortizedMTD", 0))
            if finance <= 0 and technical <= 0:
                continue
            report.append({
                "subscriptionId": e.get("subscriptionId", ""),
                "resourceGroup": e.get("resourceGroup", ""),
                "financeBudget": finance,
                "technicalBudget": technical,
                "amortizedMTD": amortized,
                "forecastEOM": float(e.get("forecastEOM", 0)),
                "financeVariance": round(amortized - finance, 2) if finance > 0 else None,
                "technicalVariance": round(amortized - technical, 2) if technical > 0 else None,
                "financeVariancePct": round(((amortized - finance) / finance) * 100, 1) if finance > 0 else None,
                "status": e.get("complianceStatus", "unknown"),
                "owner": e.get("ownerEmail", ""),
                "costCenter": e.get("costCenter", ""),
            })

        return func.HttpResponse(json.dumps(report, default=str), mimetype="application/json")
    except Exception as e:
        return func.HttpResponse(json.dumps({"error": str(e)}), status_code=500, mimetype="application/json")


# ══════════════════════════════════════════════════════════════
# Core evaluation logic
# ══════════════════════════════════════════════════════════════

def _run_evaluation() -> dict:
    now = datetime.now(timezone.utc)
    day = now.day

    rg_costs = _read_amortized_costs()
    inventory = _read_inventory()
    logging.info(f"Data: {len(rg_costs)} RGs with cost, {len(inventory)} inventory entries")

    alerts = []
    updated = 0

    for rg, entry in inventory.items():
        technical = entry.get("technical", 0)
        finance = entry.get("finance", 0)
        budget = technical if technical > 0 else finance
        mtd = rg_costs.get(rg, 0)

        # Calculate forecast
        burn = (mtd / max(day, 1)) * 30
        forecast = mtd + (burn / 30 * max(30 - day, 0))
        pct = (mtd / budget * 100) if budget > 0 else 0
        forecast_pct = (forecast / budget * 100) if budget > 0 else 0

        # Classify spend tier based on budget amount
        tier_name, tier_thresholds = _classify_spend_tier(budget)

        # Determine compliance status using tiered thresholds
        if budget <= 0:
            status = "no_budget"
        elif pct >= tier_thresholds["critical"]:
            status = "over_budget"
        elif pct >= tier_thresholds["warning"]:
            status = "warning"
        elif pct >= tier_thresholds["headup"]:
            status = "at_risk"
        else:
            status = "on_track"

        # Read RG tags for contact routing (cached per RG)
        tags = _read_rg_tags(entry["sub"], rg) if budget > 0 else {}
        tc1 = tags.get("TechnicalContact1", entry.get("tc1", ""))
        tc2 = tags.get("TechnicalContact2", entry.get("tc2", ""))
        billing_contact = tags.get("BillingContact", entry.get("billing_contact", ""))
        owner = tags.get("Owner", entry.get("owner", FINOPS_EMAIL))
        governance_tag_val = tags.get(GOVERNANCE_TAG_KEY, entry.get("governanceTagValue", "")) if GOVERNANCE_TAG_KEY else ""

        # Update inventory with latest metrics + contact + tier fields
        _update_inventory_row(entry["sub"], rg, {
            "amortizedMTD": round(mtd, 2),
            "forecastEOM": round(forecast, 2),
            "burnRateDaily": round(mtd / max(day, 1), 2),
            "actualPct": round(pct, 1),
            "forecastPct": round(forecast_pct, 1),
            "complianceStatus": status,
            "lastEvaluated": now.isoformat(),
            "evaluationDay": day,
            "spendTier": tier_name,
            "ownerEmail": owner,
            "technicalContact1": tc1,
            "technicalContact2": tc2,
            "billingContact": billing_contact,
            "governanceTagValue": governance_tag_val,
        })
        updated += 1

        # Governance Tag Alert — immediate notification when configured tag matches
        if GOVERNANCE_TAG_KEY and GOVERNANCE_TAG_VALUE and governance_tag_val == GOVERNANCE_TAG_VALUE:
            alerts.append({
                "rg": rg, "sub": entry.get("sub", ""),
                "budget_used": budget, "mtd": round(mtd, 2),
                "pct": round(pct, 1), "forecast_pct": round(forecast_pct, 1),
                "severity": "governance", "tier": tier_name,
                "owner": owner, "tc1": tc1, "tc2": tc2,
                "billing_contact": billing_contact,
                "cost_center": entry.get("cost_center", ""),
                "message": f"Governance tag [{GOVERNANCE_TAG_KEY}={GOVERNANCE_TAG_VALUE}] detected on {rg}",
            })

        # Tiered threshold alerts
        if budget > 0:
            if pct >= tier_thresholds["critical"]:
                alerts.append({
                    "rg": rg, "sub": entry.get("sub", ""),
                    "budget_used": budget, "mtd": round(mtd, 2),
                    "pct": round(pct, 1), "forecast_pct": round(forecast_pct, 1),
                    "severity": "critical", "tier": tier_name,
                    "threshold": tier_thresholds["critical"],
                    "owner": owner, "tc1": tc1, "tc2": tc2,
                    "billing_contact": billing_contact,
                    "cost_center": entry.get("cost_center", ""),
                })
            elif pct >= tier_thresholds["warning"]:
                alerts.append({
                    "rg": rg, "sub": entry.get("sub", ""),
                    "budget_used": budget, "mtd": round(mtd, 2),
                    "pct": round(pct, 1), "forecast_pct": round(forecast_pct, 1),
                    "severity": "warning", "tier": tier_name,
                    "threshold": tier_thresholds["warning"],
                    "owner": owner, "tc1": tc1, "tc2": tc2,
                    "billing_contact": billing_contact,
                    "cost_center": entry.get("cost_center", ""),
                })
            elif pct >= tier_thresholds["headup"]:
                alerts.append({
                    "rg": rg, "sub": entry.get("sub", ""),
                    "budget_used": budget, "mtd": round(mtd, 2),
                    "pct": round(pct, 1), "forecast_pct": round(forecast_pct, 1),
                    "severity": "headup", "tier": tier_name,
                    "threshold": tier_thresholds["headup"],
                    "owner": owner, "tc1": tc1, "tc2": tc2,
                    "billing_contact": billing_contact,
                    "cost_center": entry.get("cost_center", ""),
                })

    logging.info(f"Updated: {updated} inventory rows, Alerts: {len(alerts)} threshold breaches")
    if alerts:
        _dispatch(alerts, now)

    return {"updated": updated, "alerts_sent": len(alerts), "timestamp": now.isoformat()}


def _get_cosmos_container():
    """Get the Cosmos DB container client — uses key if available, falls back to managed identity."""
    cosmos_key = os.environ.get("COSMOS_KEY", "")
    if cosmos_key:
        client = CosmosClient(COSMOS_ENDPOINT, credential=cosmos_key)
    else:
        cred = DefaultAzureCredential()
        client = CosmosClient(COSMOS_ENDPOINT, credential=cred)
    db = client.get_database_client(COSMOS_DATABASE)
    return db.get_container_client(COSMOS_CONTAINER)


def _read_amortized_costs() -> dict:
    """Read latest amortized cost export CSV from blob storage."""
    cred = DefaultAzureCredential()
    client = BlobServiceClient(f"https://{STORAGE_ACCOUNT}.blob.core.windows.net", cred)
    container = client.get_container_client(CONTAINER)

    blobs = sorted(container.list_blobs(name_starts_with="amortized/"), key=lambda b: b.last_modified, reverse=True)
    blobs = [b for b in blobs if b.name.endswith(".csv")]
    if not blobs:
        logging.warning("No export blobs found")
        return {}

    data = container.get_blob_client(blobs[0].name).download_blob().readall().decode("utf-8")
    costs = {}
    for row in csv.DictReader(io.StringIO(data)):
        rg = (row.get("resourceGroupName") or row.get("ResourceGroupName") or row.get("ResourceGroup") or row.get("x_ResourceGroupName") or "").lower()
        cost = float(row.get("costInBillingCurrency") or row.get("CostInBillingCurrency") or row.get("PreTaxCost") or row.get("Cost") or 0)
        if rg:
            costs[rg] = costs.get(rg, 0) + cost
    return costs


def _read_inventory() -> dict:
    """Read the FinOps inventory from Cosmos DB — central source of truth."""
    cosmos_container = _get_cosmos_container()
    inventory = {}
    try:
        for e in cosmos_container.query_items(query="SELECT * FROM c", enable_cross_partition_query=True):
            rg = e.get("resourceGroup", "").lower()
            if rg:
                inventory[rg] = {
                    "id": e.get("id", ""),
                    "sub": e.get("subscriptionId", ""),
                    "technical": float(e.get("technicalBudget", 0)),
                    "finance": float(e.get("financeBudget", 0)),
                    "owner": e.get("ownerEmail", FINOPS_EMAIL),
                    "cost_center": e.get("costCenter", ""),
                    "tc1": e.get("technicalContact1", ""),
                    "tc2": e.get("technicalContact2", ""),
                    "billing_contact": e.get("billingContact", ""),
                    "governanceTagValue": e.get("governanceTagValue", ""),
                    "spend_tier": e.get("spendTier", ""),
                }
    except Exception as ex:
        logging.error(f"Cosmos inventory read failed: {ex}")
    return inventory


def _update_inventory_row(sub: str, rg: str, updates: dict):
    """Merge updates into an existing inventory document in Cosmos DB."""
    try:
        cosmos_container = _get_cosmos_container()
        doc_id = f"{sub}_{rg}"

        # Read existing or create new
        try:
            existing = cosmos_container.read_item(item=doc_id, partition_key=sub)
            existing.update(updates)
            cosmos_container.upsert_item(existing)
        except Exception:
            # Document doesn't exist yet, create it
            doc = {
                "id": doc_id,
                "subscriptionId": sub,
                "resourceGroup": rg,
            }
            doc.update(updates)
            cosmos_container.upsert_item(doc)
    except Exception as ex:
        logging.warning(f"Cosmos update failed for {rg}: {ex}")


def _dispatch(alerts: list, now: datetime):
    """Send severity-routed notifications. Recipients escalate by alert level:
    HeadUp  -> Owner, TC1, TC2
    Warning -> Owner, TC1, TC2, BillingContact
    Critical -> Owner, TC1, TC2, BillingContact, Governance
    IT.76 Governance -> Governance team directly
    """
    if not TEAMS_WEBHOOK:
        for a in alerts:
            logging.warning(f"ALERT [{a.get('severity','?')}]: {a['rg']} {a['pct']}% tier={a.get('tier','')}")
        return

    # Deduplicate: keep highest severity per RG
    severity_rank = {"headup": 1, "warning": 2, "critical": 3, "governance": 4}
    seen = {}
    for a in sorted(alerts, key=lambda x: severity_rank.get(x.get("severity", ""), 0), reverse=True):
        if a["rg"] not in seen:
            seen[a["rg"]] = a

    governance = [a for a in seen.values() if a.get("severity") == "governance"]
    critical = [a for a in seen.values() if a.get("severity") == "critical"]
    warning = [a for a in seen.values() if a.get("severity") == "warning"]
    headup = [a for a in seen.values() if a.get("severity") == "headup"]

    parts = []
    if governance:
        lines = "\n".join(f"- **{a['rg']}**: {a.get('message', 'IT.76')}" for a in governance)
        parts.append(f"\U0001F6A8 GOVERNANCE ({len(governance)}):\n{lines}")
    if critical:
        lines = "\n".join(f"- **{a['rg']}** [{a['tier']}]: {a['pct']}% (threshold {a['threshold']}%)" for a in critical)
        parts.append(f"\U0001F534 CRITICAL ({len(critical)}):\n{lines}")
    if warning:
        lines = "\n".join(f"- **{a['rg']}** [{a['tier']}]: {a['pct']}% (threshold {a['threshold']}%)" for a in warning)
        parts.append(f"\U0001F7E0 WARNING ({len(warning)}):\n{lines}")
    if headup:
        lines = "\n".join(f"- **{a['rg']}** [{a['tier']}]: {a['pct']}%" for a in headup)
        parts.append(f"\u2139\uFE0F HEADUP ({len(headup)}):\n{lines}")

    if not parts:
        return

    msg = {"text": f"**[FinOps Budget Alert]** {now.strftime('%Y-%m-%d %H:%M UTC')}\n\n" + "\n\n".join(parts)}

    try:
        requests.post(TEAMS_WEBHOOK, json=msg, timeout=10).raise_for_status()
        logging.info(f"Teams: {len(governance)} governance, {len(critical)} critical, {len(warning)} warning, {len(headup)} headup")
    except Exception as ex:
        logging.error(f"Teams dispatch failed: {ex}")


# ══════════════════════════════════════════════════════════════
# Phase 9: Finance Budget Auto-Ingestion (Blob Trigger)
# Finance drops CSV into finance-budgets/ container → auto-ingest
# ══════════════════════════════════════════════════════════════

FINANCE_CONTAINER = os.environ.get("FINANCE_CONTAINER_NAME", "finance-budgets")

@app.blob_trigger(arg_name="blob", path="finance-budgets/{name}",
                   connection="AzureWebJobsStorage")
def ingest_finance_budget(blob: func.InputStream) -> None:
    """Auto-ingest finance budget CSV when dropped into finance-budgets/ container."""
    logging.info(f"=== Finance Budget Ingestion: {blob.name} ({blob.length} bytes) ===")

    try:
        data = blob.read().decode("utf-8")
        cosmos_container = _get_cosmos_container()
        ingested = 0

        for row in csv.DictReader(io.StringIO(data)):
            sub = row.get("SubscriptionId", row.get("subscriptionId", "")).strip()
            rg = row.get("ResourceGroup", row.get("resourceGroup", "")).strip().lower()
            amount = float(row.get("FinanceBudget", row.get("financeBudget", 0)))
            cc = row.get("CostCenter", row.get("costCenter", "")).strip()

            if not sub or not rg or amount <= 0:
                continue

            doc_id = f"{sub}_{rg}"
            try:
                existing = cosmos_container.read_item(item=doc_id, partition_key=sub)
                existing["financeBudget"] = amount
                existing["costCenter"] = cc or existing.get("costCenter", "")
                existing["financeBudgetSetBy"] = "auto-ingestion"
                existing["financeBudgetSetDate"] = datetime.now(timezone.utc).isoformat()
                cosmos_container.upsert_item(existing)
            except Exception:
                doc = {
                    "id": doc_id,
                    "subscriptionId": sub,
                    "resourceGroup": rg,
                    "financeBudget": amount,
                    "technicalBudget": 0,
                    "costCenter": cc,
                    "amortizedMTD": 0,
                    "forecastEOM": 0,
                    "complianceStatus": "not_evaluated",
                    "financeBudgetSetBy": "auto-ingestion",
                    "financeBudgetSetDate": datetime.now(timezone.utc).isoformat(),
                }
                cosmos_container.upsert_item(doc)
            ingested += 1

        logging.info(f"Finance budget ingestion complete: {ingested} RGs updated from {blob.name}")

        # Auto-sync to LAW so Workbook dashboard reflects finance changes immediately
        synced = _sync_inventory_to_law()
        logging.info(f"LAW sync after finance ingestion: {synced}")

        # Notify Teams
        if TEAMS_WEBHOOK and ingested > 0:
            msg = {"text": f"**[FinOps Finance Budget]** {ingested} budgets loaded from `{blob.name}`"}
            try:
                requests.post(TEAMS_WEBHOOK, json=msg, timeout=10)
            except Exception:
                pass

    except Exception as ex:
        logging.error(f"Finance ingestion failed: {ex}")


# ══════════════════════════════════════════════════════════════
# Phase 12: Quarterly Budget Recalculation (Timer)
# Runs first day of each quarter, recalculates budgets from actuals
# ══════════════════════════════════════════════════════════════

@app.timer_trigger(schedule="0 0 7 1 1,4,7,10 *", arg_name="timer",
                   run_on_startup=False, use_monitor=True)
def quarterly_recalculate(timer: func.TimerRequest) -> None:
    """Quarterly recalculation: update technical budgets from last quarter's amortized actuals."""
    logging.info("=== Quarterly Budget Recalculation — Start ===")

    try:
        cosmos_container = _get_cosmos_container()
        items = list(cosmos_container.query_items(
            query="SELECT * FROM c WHERE c.amortizedMTD > 0",
            enable_cross_partition_query=True
        ))

        updated = 0
        drift_threshold = 0.30  # Only update if drift > 30%

        for item in items:
            current_budget = item.get("technicalBudget", 0)
            amortized = item.get("amortizedMTD", 0)

            if current_budget <= 0 or amortized <= 0:
                continue

            # New budget = last month amortized * 1.10 (10% buffer), min EUR 100
            new_budget = max(round(amortized * 1.10, 2), 100)
            drift = abs(new_budget - current_budget) / current_budget

            if drift > drift_threshold:
                item["technicalBudget"] = new_budget
                item["budgetRecalcDate"] = datetime.now(timezone.utc).isoformat()
                item["previousBudget"] = current_budget
                cosmos_container.upsert_item(item)
                updated += 1
                logging.info(f"Recalc: {item['resourceGroup']} EUR {current_budget} -> EUR {new_budget} (drift {drift:.0%})")

        logging.info(f"=== Quarterly Recalculation Done: {updated} budgets updated (drift > 30%) ===")

        # Sync to LAW so workbook + alerts reflect recalculated budgets
        if updated > 0:
            synced = _sync_inventory_to_law()
            logging.info(f"LAW sync after quarterly recalc: {synced}")

        if TEAMS_WEBHOOK and updated > 0:
            msg = {"text": f"**[FinOps Quarterly Recalc]** {updated} budgets recalculated from amortized actuals (drift > 30%)"}
            try:
                requests.post(TEAMS_WEBHOOK, json=msg, timeout=10)
            except Exception:
                pass

    except Exception as ex:
        logging.error(f"Quarterly recalculation failed: {ex}")


# ══════════════════════════════════════════════════════════════
# HTTP: Manually trigger quarterly recalc
# ══════════════════════════════════════════════════════════════

@app.route(route="recalculate", auth_level=func.AuthLevel.FUNCTION)
def manual_recalculate(req: func.HttpRequest) -> func.HttpResponse:
    """HTTP trigger for on-demand quarterly recalculation."""
    try:
        quarterly_recalculate(None)
        return func.HttpResponse(json.dumps({"status": "recalculation_complete"}), mimetype="application/json")
    except Exception as e:
        return func.HttpResponse(json.dumps({"error": str(e)}), status_code=500, mimetype="application/json")


# ══════════════════════════════════════════════════════════════
# HTTP: Update budget in Cosmos DB (amortized cost inventory)
# Called by la-finops-budget-change Logic App after native budget update
# This is the REAL budget for amortized cost evaluation
# ══════════════════════════════════════════════════════════════

@app.route(route="update-budget", auth_level=func.AuthLevel.FUNCTION, methods=["POST"])
def update_budget(req: func.HttpRequest) -> func.HttpResponse:
    """Update the technicalBudget in Cosmos DB inventory for amortized cost tracking.
    Called by the budget-change Logic App so the new amount is used in daily evaluation."""
    try:
        body = req.get_json()
        sub_id = body.get("subscriptionId", "")
        rg_name = body.get("resourceGroupName", "")
        new_amount = body.get("newBudgetAmount", 0)
        requestor = body.get("requestorEmail", "")
        reason = body.get("reason", "")

        if not sub_id or not rg_name or not new_amount:
            return func.HttpResponse(
                json.dumps({"error": "subscriptionId, resourceGroupName, and newBudgetAmount required"}),
                status_code=400, mimetype="application/json")

        cosmos_container = _get_cosmos_container()
        doc_id = f"{sub_id}_{rg_name}"

        try:
            existing = cosmos_container.read_item(item=doc_id, partition_key=sub_id)
            old_budget = existing.get("technicalBudget", 0)
            existing["technicalBudget"] = float(new_amount)
            existing["budgetAmount"] = float(new_amount)
            existing["budgetChangedBy"] = requestor
            existing["budgetChangeReason"] = reason
            existing["budgetChangedAt"] = datetime.now(timezone.utc).isoformat()
            existing["previousBudget"] = old_budget
            cosmos_container.upsert_item(existing)
            logging.info(f"Budget updated in Cosmos: {rg_name} EUR {old_budget} -> EUR {new_amount} by {requestor}")
        except Exception:
            # Document doesn't exist — create it
            doc = {
                "id": doc_id,
                "subscriptionId": sub_id,
                "resourceGroup": rg_name,
                "technicalBudget": float(new_amount),
                "budgetAmount": float(new_amount),
                "budgetChangedBy": requestor,
                "budgetChangeReason": reason,
                "budgetChangedAt": datetime.now(timezone.utc).isoformat(),
                "complianceStatus": "not_evaluated",
                "lastEvaluated": datetime.now(timezone.utc).isoformat(),
            }
            cosmos_container.upsert_item(doc)
            old_budget = 0
            logging.info(f"Budget created in Cosmos: {rg_name} EUR {new_amount} by {requestor}")

        # Auto-sync to LAW so workbook + alert rules see the change immediately
        synced = _sync_inventory_to_law()
        logging.info(f"LAW sync after budget update: {synced}")

        return func.HttpResponse(json.dumps({
            "status": "cosmos_updated",
            "resourceGroup": rg_name,
            "oldBudget": old_budget,
            "newBudget": new_amount,
            "updatedBy": requestor,
            "law_sync": synced
        }), mimetype="application/json")

    except Exception as e:
        logging.error(f"update-budget failed: {e}")
        return func.HttpResponse(json.dumps({"error": str(e)}), status_code=500, mimetype="application/json")


# ══════════════════════════════════════════════════════════════
# Log Analytics Sync — pushes Cosmos inventory to LAW for Workbook
# Called automatically after daily evaluation + finance ingestion
# ══════════════════════════════════════════════════════════════

def _sync_inventory_to_law() -> str:
    """Push all Cosmos DB inventory records to Log Analytics for Azure Workbook."""
    if not LAW_WORKSPACE_ID or not LAW_SHARED_KEY:
        return "skipped (LAW_WORKSPACE_ID or LAW_SHARED_KEY not set)"
    try:
        cosmos_container = _get_cosmos_container()
        records = []
        for doc in cosmos_container.query_items(query="SELECT * FROM c", enable_cross_partition_query=True):
            records.append({
                "resourceGroup": doc.get("resourceGroup", ""),
                "subscriptionId": doc.get("subscriptionId", ""),
                "technicalBudget": doc.get("technicalBudget", 0),
                "financeBudget": doc.get("financeBudget", 0),
                "amortizedMTD": doc.get("amortizedMTD", 0),
                "forecastEOM": doc.get("forecastEOM", 0),
                "actualPct": doc.get("actualPct", 0),
                "forecastPct": doc.get("forecastPct", 0),
                "burnRateDaily": doc.get("burnRateDaily", 0),
                "complianceStatus": doc.get("complianceStatus", "not_evaluated"),
                "costCenter": doc.get("costCenter", ""),
                "ownerEmail": doc.get("ownerEmail", ""),
                "technicalContact1": doc.get("technicalContact1", ""),
                "technicalContact2": doc.get("technicalContact2", ""),
                "billingContact": doc.get("billingContact", ""),
                "spendTier": doc.get("spendTier", ""),
                "governanceTagValue": doc.get("governanceTagValue", ""),
                "lastEvaluated": doc.get("lastEvaluated", ""),
            })
        if not records:
            return "no records"
        body = json.dumps(records)
        rfc1123 = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S GMT")
        sig_str = f"POST\n{len(body)}\napplication/json\nx-ms-date:{rfc1123}\n/api/logs"
        decoded_key = base64.b64decode(LAW_SHARED_KEY)
        sig = base64.b64encode(hmac.new(decoded_key, sig_str.encode("utf-8"), digestmod=hashlib.sha256).digest()).decode("utf-8")
        resp = requests.post(
            f"https://{LAW_WORKSPACE_ID}.ods.opinsights.azure.com/api/logs?api-version=2016-04-01",
            data=body,
            headers={
                "content-type": "application/json",
                "Authorization": f"SharedKey {LAW_WORKSPACE_ID}:{sig}",
                "Log-Type": "FinOpsInventory",
                "x-ms-date": rfc1123,
            },
            timeout=30,
        )
        return f"ok ({len(records)} records, HTTP {resp.status_code})"
    except Exception as ex:
        logging.error(f"LAW sync failed: {ex}")
        return f"error: {str(ex)[:100]}"


# ══════════════════════════════════════════════════════════════
# Backfill: Set budgets on existing RGs (replaces PowerShell script)
# Call /api/backfill?subscriptionId=xxx&top=20&dryRun=true
# ══════════════════════════════════════════════════════════════

@app.route(route="backfill", auth_level=func.AuthLevel.FUNCTION)
def backfill_existing_rgs(req: func.HttpRequest) -> func.HttpResponse:
    """Scan existing RGs, create Azure budgets if missing, seed Cosmos DB inventory.
    Called by la-finops-backfill Logic App on daily schedule.
    Params: subscriptionId, dryRun=true/false, minBudget=100, top=0 (0=all)
    """
    try:
        sub_id = req.params.get("subscriptionId", os.environ.get("SUBSCRIPTION_ID", ""))
        top = int(req.params.get("top", "0"))
        dry_run = req.params.get("dryRun", "false").lower() == "true"
        min_budget = int(req.params.get("minBudget", "100"))

        if not sub_id:
            return func.HttpResponse(json.dumps({"error": "subscriptionId required"}), status_code=400, mimetype="application/json")

        from azure.mgmt.resource import ResourceManagementClient

        cred = DefaultAzureCredential()
        resource_client = ResourceManagementClient(cred, sub_id)
        cosmos_container = _get_cosmos_container()

        ag_id = os.environ.get("ACTION_GROUP_ID", "")

        rgs = list(resource_client.resource_groups.list())

        # Use configurable exclusion list (empty = include ALL RGs)
        excluded = EXCLUDED_RG_PREFIXES
        logging.info(f"Excluded prefixes: {excluded if excluded else '(none — all RGs included)'}")

        # Build set of RGs already tracked in Cosmos DB (our source of truth)
        existing_cosmos_rgs = set()
        try:
            for doc in cosmos_container.query_items(query="SELECT c.resourceGroup FROM c", enable_cross_partition_query=True):
                existing_cosmos_rgs.add(doc.get("resourceGroup", "").lower())
        except Exception:
            pass
        logging.info(f"Cosmos has {len(existing_cosmos_rgs)} existing RGs")

        results = []
        skipped = 0
        created = 0
        errors = 0

        for rg in rgs:
            rg_name = rg.name
            if excluded and any(rg_name.startswith(p) for p in excluded):
                continue

            # Check if RG already exists in Cosmos DB (our source of truth)
            in_cosmos = rg_name.lower() in existing_cosmos_rgs

            if in_cosmos:
                skipped += 1
                continue

            budget_amount = min_budget
            owner_email = FINOPS_EMAIL
            cost_center = ""

            if rg.tags:
                if "Owner" in rg.tags and "@" in rg.tags["Owner"]:
                    owner_email = rg.tags["Owner"]
                if "CostCenter" in rg.tags:
                    cost_center = rg.tags["CostCenter"]

            action = "needs_tracking"
            if not dry_run:
                # Create Azure budget (safety net) only if none exists
                try:
                    budget_url = f"https://management.azure.com/subscriptions/{sub_id}/resourceGroups/{rg_name}/providers/Microsoft.Consumption/budgets?api-version=2023-11-01"
                    token = cred.get_token("https://management.azure.com/.default").token
                    resp = requests.get(budget_url, headers={"Authorization": f"Bearer {token}"}, timeout=15)
                    has_azure_budget = resp.status_code == 200 and len(resp.json().get("value", [])) > 0
                except Exception:
                    has_azure_budget = False

                if not has_azure_budget:
                    try:
                        budget_name = f"finops-rg-budget-{rg_name}"
                        now = datetime.now(timezone.utc)
                        start = now.replace(day=1).strftime("%Y-%m-%dT00:00:00Z")
                        budget_body = {
                            "properties": {
                                "category": "Cost",
                                "amount": budget_amount,
                                "timeGrain": "Monthly",
                                "timePeriod": {"startDate": start, "endDate": "2027-03-31T00:00:00Z"},
                                "notifications": {
                                    "Forecasted_90": {
                                        "enabled": True, "operator": "GreaterThan",
                                        "threshold": 90, "thresholdType": "Forecasted",
                                        "contactEmails": [owner_email],
                                        **({"contactGroups": [ag_id]} if ag_id else {})
                                    },
                                    "Actual_100": {
                                        "enabled": True, "operator": "GreaterThan",
                                        "threshold": 100, "thresholdType": "Actual",
                                        "contactEmails": [owner_email],
                                        **({"contactGroups": [ag_id]} if ag_id else {})
                                    },
                                    "Forecasted_110": {
                                        "enabled": True, "operator": "GreaterThan",
                                        "threshold": 110, "thresholdType": "Forecasted",
                                        "contactEmails": [owner_email],
                                        **({"contactGroups": [ag_id]} if ag_id else {})
                                    }
                                }
                            }
                        }
                        put_url = f"https://management.azure.com/subscriptions/{sub_id}/resourceGroups/{rg_name}/providers/Microsoft.Consumption/budgets/{budget_name}?api-version=2023-11-01"
                        token = cred.get_token("https://management.azure.com/.default").token
                        resp = requests.put(put_url, headers={
                            "Authorization": f"Bearer {token}",
                            "Content-Type": "application/json"
                        }, json=budget_body, timeout=30)
                        resp.raise_for_status()
                        action = "budget_created"
                        created += 1
                    except Exception as ex:
                        logging.error(f"Budget creation failed for {rg_name}: {ex}")
                        action = f"error: {str(ex)[:100]}"
                        errors += 1

                # ALWAYS seed Cosmos DB inventory (even if budget already existed)
                doc_id = f"{sub_id}_{rg_name.lower()}"
                doc = {
                    "id": doc_id,
                    "subscriptionId": sub_id,
                    "resourceGroup": rg_name.lower(),
                    "technicalBudget": budget_amount,
                    "financeBudget": 0,
                    "ownerEmail": owner_email,
                    "costCenter": cost_center,
                    "amortizedMTD": 0,
                    "forecastEOM": 0,
                    "complianceStatus": "not_evaluated",
                    "lastSeeded": datetime.now(timezone.utc).isoformat(),
                    "seededBy": "backfill",
                }
                try:
                    cosmos_container.upsert_item(doc)
                except Exception:
                    pass

            results.append({
                "resourceGroup": rg_name,
                "budgetAmount": budget_amount,
                "ownerEmail": owner_email,
                "costCenter": cost_center,
                "action": action,
            })

            if top > 0 and len(results) >= top:
                break

        # Sync to LAW so workbook + alert rules see new RGs immediately
        law_status = "skipped (dry run)" if dry_run else _sync_inventory_to_law()

        summary = {
            "status": "dry_run" if dry_run else "backfill_complete",
            "processed": len(results),
            "skipped_has_budget": skipped,
            "budgets_created": created,
            "errors": errors,
            "subscription": sub_id,
            "law_sync": law_status,
            "results": results,
        }

        logging.info(f"Backfill {'(dry)' if dry_run else ''}: {len(results)} need budget, {skipped} skipped, {created} created, {errors} errors")
        return func.HttpResponse(json.dumps(summary, default=str), mimetype="application/json")

    except Exception as e:
        return func.HttpResponse(json.dumps({"error": str(e)}), status_code=500, mimetype="application/json")
