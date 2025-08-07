-- -- This single, idempotent script handles the entire daily analytics update.
-- This script creates the primary daily reporting table by aggregating raw events.
-- It is fully idempotent and uses a watermark to process data incrementally.
-- Create the final table if it doesn't exist.
CREATE TABLE IF NOT EXISTS reporting.daily_campaign_performance
(
    report_date       Date,
    campaign_id       UInt64,
    campaign_name     String,
    advertiser_id     UInt64,
    advertiser_name   String,
    total_impressions UInt64,
    total_clicks      UInt64,
    total_cost        Decimal(18, 4),
    ctr               Float64,
    cpc               Float64,
    updated_at        DateTime DEFAULT now()
)
ENGINE = MergeTree()
PRIMARY KEY (report_date, campaign_id);

-- An intermediate table is used to stage the results before the final atomic upsert.
DROP TABLE IF EXISTS reporting.intermediate_daily_performance;

CREATE TABLE reporting.intermediate_daily_performance
ENGINE = MergeTree ORDER BY (report_date, campaign_id) AS
WITH
    -- Define a watermark to only process recent data. Use a 2-day lookback for resilience.

    -- I discovered somehow CH returns max(date==NULL) as 1970-01-01, following is a workaround for that.
    watermark AS (
        SELECT CASE WHEN max(report_date) = '1970-01-01' THEN max(report_date)
            ELSE date_sub(day , 2, max(report_date)) END as start_date
        FROM reporting.daily_campaign_performance
    ),
    -- Combine impressions and clicks into a single event stream.
    all_events AS (
        SELECT assumeNotNull(toDate(created_at)) as report_date, assumeNotNull(campaign_id) as campaign_id, 1 as impression, 0 as click
        FROM intermediate.impressions
        WHERE created_at IS NOT NULL AND campaign_id IS NOT NULL AND report_date >= (SELECT start_date FROM watermark)
        UNION ALL
        SELECT assumeNotNull(toDate(created_at)) as report_date, assumeNotNull(campaign_id) as campaign_id, 0 as impression, 1 as click
        FROM intermediate.clicks
        WHERE created_at IS NOT NULL AND campaign_id IS NOT NULL AND report_date >= (SELECT start_date FROM watermark)
    ),
    -- Aggregate events by day and campaign.
    daily_aggregates AS (
        SELECT report_date, campaign_id, sum(impression) as total_impressions, sum(click) as total_clicks
        FROM all_events
        GROUP BY report_date, campaign_id
    )
-- Final join to get campaign/advertiser details and calculate KPIs.
SELECT
    agg.report_date,
    c.id as campaign_id, c.name as campaign_name,
    a.id as advertiser_id, a.name as advertiser_name,
    agg.total_impressions,
    agg.total_clicks,
    -- Corrected Cost Model: Cost is now correctly driven by clicks (CPC model), not impressions.
    CAST(agg.total_clicks * c.bid AS Decimal(18, 4)) as total_cost,
    -- CTR calculation remains correct.
    CAST(if(agg.total_impressions > 0, agg.total_clicks / agg.total_impressions, 0) AS Float64) as ctr,
    -- CPC is now correctly derived from the new cost model.
    CAST(if(agg.total_clicks > 0, c.bid, 0) AS Float64) as cpc
FROM daily_aggregates agg
-- Use ANY LEFT JOIN for robustness. It's efficient and prevents row duplication
-- if the dimension tables have duplicates before a ReplacingMergeTree merge.
ANY LEFT JOIN intermediate.campaign AS c ON agg.campaign_id = c.id
ANY LEFT JOIN intermediate.advertiser AS a ON c.advertiser_id = a.id;


-- Atomically swap the data using a delete-and-insert (upsert) pattern.
ALTER TABLE reporting.daily_campaign_performance
    DELETE WHERE (report_date, campaign_id) IN (SELECT report_date, campaign_id FROM reporting.intermediate_daily_performance)
SETTINGS mutations_sync = 2; -- Makes the delete operation synchronous.

INSERT INTO reporting.daily_campaign_performance (report_date, campaign_id, campaign_name, advertiser_id, advertiser_name, total_impressions, total_clicks, total_cost, ctr, cpc)
SELECT report_date, campaign_id, campaign_name, advertiser_id, advertiser_name, total_impressions, total_clicks, total_cost, ctr, cpc
FROM reporting.intermediate_daily_performance;

-- Clean up the intermediate table.
DROP TABLE IF EXISTS reporting.intermediate_daily_performance;