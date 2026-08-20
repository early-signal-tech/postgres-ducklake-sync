-- Gold layer transformation: flatten events_rich_source JSON columns into a denormalized ML-ready schema.
-- Reads from my_ducklake.ducklake_prod_ingestion.events_rich_source and writes a full refresh to
-- my_ducklake.gold.events_rich_ml_gold (idempotent, always represents the current state).
--
-- Assumes postgres, ducklake, httpfs, and json are already INSTALLed/LOADed by the caller
-- (see .github/workflows/gold_layer.yml). Credentials go into CREATE SECRET (whose fields
-- accept getenv()); ATTACH references that secret by name. The workflow parses PG_CONN_STRING
-- into PGHOST/PGPORT/PGUSER/PGPASSWORD/PGDATABASE beforehand.

CREATE OR REPLACE SECRET pg_secret (
    TYPE POSTGRES,
    HOST getenv('PGHOST'),
    PORT getenv('PGPORT'),
    DATABASE getenv('PGDATABASE'),
    USER getenv('PGUSER'),
    PASSWORD getenv('PGPASSWORD'),
    SSLMODE 'require'
);

CREATE OR REPLACE SECRET s3_secret (
    TYPE S3,
    KEY_ID getenv('AWS_ACCESS_KEY_ID'),
    SECRET getenv('AWS_SECRET_ACCESS_KEY'),
    REGION 'us-east-1'
);

-- DuckLake catalog: metadata in Postgres, data files in S3.
ATTACH 'ducklake:postgres:' AS my_ducklake (
    DATA_PATH 's3://ducklake-prod-tutorial/',
    METADATA_SCHEMA 'ducklake_meta',
    METADATA_PARAMETERS MAP {'secret': 'pg_secret'}
);

-- Create gold schema if it doesn't exist.
CREATE SCHEMA IF NOT EXISTS my_ducklake.gold;

-- Full refresh: read bronze layer, flatten JSON, write to gold.
-- All columns are cast to their target types; NULL is used for missing/unparseable values.
CREATE OR REPLACE TABLE my_ducklake.gold.events_rich_ml_gold AS
SELECT
    src.id::INT AS id,
    src.user_id::VARCHAR AS user_id,
    src.event_type::VARCHAR AS event_type,
    src.ts::TIMESTAMP AS ts,

    -- Flatten payload (JSON)
    TRY_CAST(json_extract_string(src.payload, '$.page') AS VARCHAR) AS payload_page,
    TRY_CAST(json_extract_string(src.payload, '$.duration_ms') AS INT) AS payload_duration_ms,
    TRY_CAST(json_extract_string(src.payload, '$.value') AS DECIMAL(10,2)) AS payload_value,
    TRY_CAST(json_extract_string(src.payload, '$.device_type') AS VARCHAR) AS payload_device_type,
    TRY_CAST(json_extract_string(src.payload, '$.referrer') AS VARCHAR) AS payload_referrer,
    TRY_CAST(json_extract_string(src.payload, '$.session_number') AS INT) AS payload_session_number,
    TRY_CAST(json_extract_string(src.payload, '$.previous_purchase_count') AS INT) AS payload_previous_purchase_count,

    -- Flatten metadata (JSON)
    TRY_CAST(json_extract_string(src.metadata, '$.source') AS VARCHAR) AS metadata_source,
    TRY_CAST(json_extract_string(src.metadata, '$.country') AS VARCHAR) AS metadata_country,
    TRY_CAST(json_extract_string(src.metadata, '$.session_id') AS VARCHAR) AS metadata_session_id,
    TRY_CAST(json_extract_string(src.metadata, '$.ab_variant') AS VARCHAR) AS metadata_ab_variant,
    TRY_CAST(json_extract_string(src.metadata, '$.user_tier') AS VARCHAR) AS metadata_user_tier,
    TRY_CAST(json_extract_string(src.metadata, '$.days_since_signup') AS INT) AS metadata_days_since_signup,

    -- Flatten user_attributes (JSON)
    TRY_CAST(json_extract_string(src.user_attributes, '$.tier') AS VARCHAR) AS user_attributes_tier,
    TRY_CAST(json_extract_string(src.user_attributes, '$.signup_days_ago') AS INT) AS user_attributes_signup_days_ago,
    TRY_CAST(json_extract_string(src.user_attributes, '$.country') AS VARCHAR) AS user_attributes_country,
    TRY_CAST(json_extract_string(src.user_attributes, '$.mrr_value') AS DECIMAL(10,2)) AS user_attributes_mrr_value

FROM my_ducklake.ducklake_prod_ingestion.events_rich_source AS src;
