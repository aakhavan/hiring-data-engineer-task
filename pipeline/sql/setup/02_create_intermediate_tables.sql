-- Create the destination tables in the 'intermediate' schema with the efficient MergeTree engine.
-- These tables will hold the replicated data from the 'raw' (PostgreSQL) schema.


CREATE TABLE IF NOT EXISTS intermediate.advertiser
(
    id         UInt64,
    name       String,
    updated_at Nullable(DateTime64(3, 'UTC')),
    created_at Nullable(DateTime64(3, 'UTC'))
)
ENGINE = ReplacingMergeTree()
ORDER BY id;

CREATE TABLE IF NOT EXISTS intermediate.campaign
(
    id            UInt64,
    name          String,
    bid           Decimal(10, 2),
    budget        Decimal(10, 2),
    start_date    Nullable(Date),
    end_date      Nullable(Date),
    advertiser_id Nullable(UInt64),
    updated_at    Nullable(DateTime64(3, 'UTC')),
    created_at    Nullable(DateTime64(3, 'UTC'))
)
ENGINE = ReplacingMergeTree()
ORDER BY id;

CREATE TABLE IF NOT EXISTS intermediate.impressions
(
    id          UInt64,
    campaign_id Nullable(UInt64),
    created_at  Nullable(DateTime64(3, 'UTC'))
)
ENGINE = ReplacingMergeTree()
ORDER BY id;

CREATE TABLE IF NOT EXISTS intermediate.clicks
(
    id          UInt64,
    campaign_id Nullable(UInt64),
    created_at  Nullable(DateTime64(3, 'UTC'))
)
ENGINE = ReplacingMergeTree()
ORDER BY id;