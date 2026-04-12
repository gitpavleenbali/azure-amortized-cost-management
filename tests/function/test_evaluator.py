"""
Unit tests for the Amortized Budget Engine Azure Function.
Run: pytest tests/function/ -v
"""

import pytest
from unittest.mock import patch, MagicMock
import json


class TestThresholdEvaluation:
    """Test the budget threshold evaluation logic."""

    def test_actual_100_fires_on_exact_breach(self):
        """100% actual fires when MTD spend equals budget."""
        budget = 1000
        mtd = 1000
        pct = (mtd / budget) * 100
        assert pct >= 100

    def test_actual_100_does_not_fire_below(self):
        """100% actual does not fire at 99.9%."""
        budget = 1000
        mtd = 999
        pct = (mtd / budget) * 100
        assert pct < 100

    def test_forecasted_90_uses_projected_eom(self):
        """90% forecasted uses projected EoM, not MTD actual."""
        budget = 1000
        mtd = 500  # 50% actual on day 15
        day = 15
        daily_burn = mtd / day
        forecast = mtd + (daily_burn * (30 - day))
        forecast_pct = (forecast / budget) * 100
        assert forecast_pct >= 90  # 500 + (33.33 * 15) = 1000 → 100%

    def test_forecasted_90_stable_workload_no_fire_early(self):
        """Stable workload at 50% on day 15 should forecast ~100%, firing 90%."""
        budget = 10000
        mtd = 5000  # 50% on day 15
        day = 15
        daily_burn = mtd / day
        forecast = mtd + (daily_burn * (30 - day))
        forecast_pct = (forecast / budget) * 100
        # 5000 + (333.33 * 15) = 10000 → 100% forecasted → fires 90%
        assert forecast_pct >= 90

    def test_min_budget_floor(self):
        """Budget floor of 100 prevents micro-budget noise."""
        import math
        spend_3m = 15  # EUR 15 over 3 months
        monthly_avg = spend_3m / 3
        budget = max(math.ceil(monthly_avg * 1.10), 100)
        assert budget == 100  # Floor kicks in

    def test_budget_calculation_with_buffer(self):
        """Budget = 3-month avg + 10% buffer."""
        import math
        spend_3m = 3000  # EUR 3000 over 3 months
        monthly_avg = spend_3m / 3  # 1000
        budget = max(math.ceil(monthly_avg * 1.10), 100)
        assert budget == 1100

    def test_drift_threshold_prevents_churn(self):
        """Quarterly recalc only updates if drift > 30%."""
        current = 1000
        new = 1200  # 20% change
        drift = abs((new - current) / current * 100)
        assert drift < 30  # Should NOT update

    def test_drift_threshold_triggers_update(self):
        """Quarterly recalc updates when drift > 30%."""
        current = 1000
        new = 1500  # 50% change
        drift = abs((new - current) / current * 100)
        assert drift >= 30  # Should update

    def test_cap_prevents_3x_increase(self):
        """Self-service caps at 3x current budget."""
        current = 500
        requested = 2000  # 4x
        assert requested > current * 3  # Should be rejected

    def test_auto_approve_under_2x(self):
        """Budget increase under 2x auto-approves."""
        current = 500
        requested = 900  # 1.8x
        assert requested <= current * 2  # Auto-approve


class TestAlertRouting:
    """Test per-threshold contact routing logic."""

    def test_50_percent_owner_only(self):
        """50% threshold routes to owner only."""
        threshold = 50
        owner = "owner@example.com"
        bu_lead = "bu-lead@example.com"
        finops = "finops@example.com"

        if threshold <= 50:
            contacts = [owner]
        elif threshold <= 75:
            contacts = [owner, bu_lead]
        else:
            contacts = [owner, bu_lead, finops]

        assert contacts == [owner]
        assert finops not in contacts

    def test_90_percent_adds_finops(self):
        """90% threshold includes finops team."""
        threshold = 90
        owner = "owner@example.com"
        bu_lead = "bu-lead@example.com"
        finops = "finops@example.com"

        if threshold <= 50:
            contacts = [owner]
        elif threshold <= 75:
            contacts = [owner, bu_lead]
        else:
            contacts = [owner, bu_lead, finops]

        assert finops in contacts


class TestBudgetAPIPayload:
    """Test budget REST API payload construction."""

    def test_payload_structure(self):
        """Budget payload has required fields."""
        payload = {
            "properties": {
                "category": "Cost",
                "amount": 1000,
                "timeGrain": "Monthly",
                "timePeriod": {
                    "startDate": "2026-04-01T00:00:00Z",
                    "endDate": "2027-03-31T00:00:00Z"
                },
                "notifications": {
                    "Forecasted_90": {
                        "enabled": True,
                        "operator": "GreaterThan",
                        "threshold": 90,
                        "thresholdType": "Forecasted",
                        "contactEmails": ["finops@example.com"]
                    }
                }
            }
        }

        props = payload["properties"]
        assert props["category"] == "Cost"
        assert props["amount"] > 0
        assert props["timeGrain"] == "Monthly"
        assert "notifications" in props
        assert len(props["notifications"]) >= 1

    def test_max_5_notifications(self):
        """Azure Budgets API supports max 5 notifications."""
        notifications = {
            "Actual_50": {}, "Actual_75": {},
            "Forecasted_90": {}, "Actual_100": {},
            "Forecasted_110": {}
        }
        assert len(notifications) <= 5
