
-- Simple data quality check for number of rows
SELECT
    'advertiser' AS table_name,
    (SELECT count() FROM raw.advertiser) AS raw_count,
    (SELECT count() FROM intermediate.advertiser) AS intermediate_count,
    if(raw_count = intermediate_count, 'OK', 'MISMATCH') AS status
UNION ALL
SELECT
    'campaign' AS table_name,
    (SELECT count() FROM raw.campaign) AS raw_count,
    (SELECT count() FROM intermediate.campaign) AS intermediate_count,
    if(raw_count = intermediate_count, 'OK', 'MISMATCH') AS status
UNION ALL
SELECT
    'impressions' AS table_name,
    (SELECT count() FROM raw.impressions) AS raw_count,
    (SELECT count() FROM intermediate.impressions) AS intermediate_count,
    if(raw_count = intermediate_count, 'OK', 'MISMATCH') AS status
UNION ALL
SELECT
    'clicks' AS table_name,
    (SELECT count() FROM raw.clicks) AS raw_count,
    (SELECT count() FROM intermediate.clicks) AS intermediate_count,
    if(raw_count = intermediate_count, 'OK', 'MISMATCH') AS status;



-- Simple data quality check for impressions and clicks
WITH
    -- Aggregate events as in the analytics script
    all_events AS (
        SELECT assumeNotNull(toDate(created_at)) as report_date, assumeNotNull(campaign_id) as campaign_id, 1 as impression, 0 as click
        FROM intermediate.impressions
        WHERE created_at IS NOT NULL AND campaign_id IS NOT NULL
        UNION ALL
        SELECT assumeNotNull(toDate(created_at)) as report_date, assumeNotNull(campaign_id) as campaign_id, 0 as impression, 1 as click
        FROM intermediate.clicks
        WHERE created_at IS NOT NULL AND campaign_id IS NOT NULL
    ),
    daily_aggregates AS (
        SELECT report_date, campaign_id, sum(impression) as total_impressions, sum(click) as total_clicks
        FROM all_events
        GROUP BY report_date, campaign_id
    )
SELECT
    r.report_date,
    r.campaign_id,
    r.total_impressions AS reported_impressions,
    a.total_impressions AS recalculated_impressions,
    if(r.total_impressions = a.total_impressions, 'OK', 'MISMATCH') AS impressions_status,
    r.total_clicks AS reported_clicks,
    a.total_clicks AS recalculated_clicks,
    if(r.total_clicks = a.total_clicks, 'OK', 'MISMATCH') AS clicks_status
FROM reporting.daily_campaign_performance r
LEFT JOIN daily_aggregates a
    ON r.report_date = a.report_date AND r.campaign_id = a.campaign_id
ORDER BY r.report_date, r.campaign_id;


-- Data Quality Recalculation Test for reporting.advertiser_summary

WITH
    advertiser_sums AS (
        SELECT
            advertiser_id,
            advertiser_name,
            sum(total_cost) AS total_cost,
            sum(total_impressions) AS total_impressions,
            sum(total_clicks) AS total_clicks
        FROM reporting.daily_campaign_performance
        GROUP BY advertiser_id, advertiser_name
    )
SELECT
    s.advertiser_id,
    s.advertiser_name,
    if(abs(s.total_cost - a.total_cost) < 0.01, 'OK', 'MISMATCH') AS total_cost_status,
    if(s.total_impressions = a.total_impressions, 'OK', 'MISMATCH') AS total_impressions_status,
    if(s.total_clicks = a.total_clicks, 'OK', 'MISMATCH') AS total_clicks_status,
    if(abs(s.avg_ctr - if(a.total_impressions > 0, a.total_clicks / a.total_impressions, 0)) < 0.0001, 'OK', 'MISMATCH') AS avg_ctr_status,
    if(abs(s.avg_cpc - if(a.total_clicks > 0, a.total_cost / a.total_clicks, 0)) < 0.01, 'OK', 'MISMATCH') AS avg_cpc_status
FROM reporting.advertiser_summary s
ANY LEFT JOIN advertiser_sums a
    ON s.advertiser_id = a.advertiser_id AND s.advertiser_name = a.advertiser_name;