-- ============================================================
-- Spend vs Budget — Snowflake Queries
-- Feature: LT-05 | Framework: §13
-- For Power BI Cost Insight dashboard integration
-- ============================================================

-- QUERY 1: Spend vs Budget by Cost Center (Executive View)
-- Aggregates RG budgets to BU level via CostCenter tag
SELECT
    cc.tag_value AS cost_center,
    COUNT(DISTINCT b.resource_group) AS rg_count,
    ROUND(SUM(b.budget_amount), 2) AS total_budget,
    ROUND(SUM(s.mtd_spend), 2) AS total_spend,
    ROUND(SUM(s.mtd_spend) - SUM(b.budget_amount), 2) AS variance,
    ROUND((SUM(s.mtd_spend) / NULLIF(SUM(b.budget_amount), 0)) * 100, 1) AS spend_percent,
    CASE
        WHEN (SUM(s.mtd_spend) / NULLIF(SUM(b.budget_amount), 0)) * 100 >= 110 THEN 'OVERRUN'
        WHEN (SUM(s.mtd_spend) / NULLIF(SUM(b.budget_amount), 0)) * 100 >= 100 THEN 'BREACH'
        WHEN (SUM(s.mtd_spend) / NULLIF(SUM(b.budget_amount), 0)) * 100 >= 90 THEN 'CRITICAL'
        WHEN (SUM(s.mtd_spend) / NULLIF(SUM(b.budget_amount), 0)) * 100 >= 75 THEN 'WARNING'
        ELSE 'ON TRACK'
    END AS status
FROM finops.budgets b
JOIN finops.rg_tags cc
    ON b.resource_group = cc.resource_group
    AND cc.tag_name = 'CostCenter'
LEFT JOIN (
    SELECT
        resource_group,
        SUM(cost_in_billing_currency) AS mtd_spend
    FROM finops.amortized_costs
    WHERE date >= DATE_TRUNC('MONTH', CURRENT_DATE())
    GROUP BY resource_group
) s ON b.resource_group = s.resource_group
GROUP BY cc.tag_value
ORDER BY variance DESC;


-- QUERY 2: RG-Level Spend vs Budget Detail
SELECT
    b.subscription_name,
    b.resource_group,
    b.budget_amount,
    COALESCE(s.mtd_spend, 0) AS mtd_spend,
    ROUND(COALESCE(s.mtd_spend, 0) - b.budget_amount, 2) AS variance,
    ROUND((COALESCE(s.mtd_spend, 0) / NULLIF(b.budget_amount, 0)) * 100, 1) AS spend_percent,
    b.owner_email,
    b.last_updated
FROM finops.budgets b
LEFT JOIN (
    SELECT
        resource_group,
        SUM(cost_in_billing_currency) AS mtd_spend
    FROM finops.amortized_costs
    WHERE date >= DATE_TRUNC('MONTH', CURRENT_DATE())
    GROUP BY resource_group
) s ON b.resource_group = s.resource_group
ORDER BY spend_percent DESC;


-- QUERY 3: Month-over-Month Budget Trend
SELECT
    DATE_TRUNC('MONTH', date) AS month,
    SUM(cost_in_billing_currency) AS total_spend,
    (SELECT SUM(budget_amount) FROM finops.budgets) AS total_budget
FROM finops.amortized_costs
WHERE date >= DATEADD('MONTH', -6, CURRENT_DATE())
GROUP BY DATE_TRUNC('MONTH', date)
ORDER BY month;


-- QUERY 4: Budget Change Audit Log
SELECT
    change_date,
    resource_group,
    old_budget,
    new_budget,
    ROUND(((new_budget - old_budget) / NULLIF(old_budget, 0)) * 100, 1) AS change_percent,
    changed_by,
    reason
FROM finops.budget_change_log
ORDER BY change_date DESC
LIMIT 50;
