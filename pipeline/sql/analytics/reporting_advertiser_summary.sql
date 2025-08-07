-- This script creates a lifetime summary table for each advertiser.
-- It reads from the main daily performance table and uses ReplacingMergeTree to handle updates.

CREATE TABLE IF NOT EXISTS reporting.advertiser_summary
(
    advertiser_id     UInt64,
    advertiser_name   String,
    total_cost        Decimal(18, 4),
    total_impressions UInt64,
    total_clicks      UInt64,
    avg_ctr           Float64,
    avg_cpc           Float64,
    updated_at        DateTime DEFAULT now()
)
ENGINE = ReplacingMergeTree(updated_at)
PRIMARY KEY (advertiser_id);

-- Ensure the table is empty before inserting the new summary. This makes the script idempotent.
TRUNCATE TABLE IF EXISTS reporting.advertiser_summary;

-- To avoid a nested aggregation error, we first aggregate the sums in a CTE,
-- and then perform the final KPI calculations in the final SELECT.
INSERT INTO reporting.advertiser_summary (advertiser_id, advertiser_name, total_cost, total_impressions, total_clicks, avg_ctr, avg_cpc, updated_at)
WITH advertiser_sums AS (
    SELECT
        advertiser_id,
        advertiser_name,
        sum(total_cost) as lifetime_cost,
        sum(total_impressions) as lifetime_impressions,
        sum(total_clicks) as lifetime_clicks
    FROM reporting.daily_campaign_performance
    GROUP BY advertiser_id, advertiser_name
)
SELECT
    advertiser_id,
    advertiser_name,
    -- Explicitly cast calculated fields to match the target table's schema.
    CAST(lifetime_cost AS Decimal(18, 4)) as total_cost,
    lifetime_impressions,
    lifetime_clicks,
    CAST(if(lifetime_impressions > 0, lifetime_clicks / lifetime_impressions, 0) AS Float64) as avg_ctr,
    CAST(if(lifetime_clicks > 0, lifetime_cost / lifetime_clicks, 0) AS Float64) as avg_cpc,
    now() as updated_at
FROM advertiser_sums;