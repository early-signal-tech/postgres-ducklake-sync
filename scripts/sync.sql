-- Assumes postgres, ducklake, and httpfs are already INSTALLed/LOADed by the caller
-- (see .github/workflows/sync.yml, which loads them before .read'ing this file).
--
-- DuckDB's ATTACH requires its connection argument to be a string literal -- getenv()
-- and string concatenation both fail to parse there. So credentials never appear as a
-- literal: they go into a CREATE SECRET (whose fields DO accept getenv()), and both
-- ATTACH statements below reference that secret by name instead of embedding a
-- connection string. The workflow parses PG_CONN_STRING into PGHOST/PGPORT/PGUSER/
-- PGPASSWORD/PGDATABASE beforehand, since Postgres secrets take discrete fields, not
-- a single DSN.

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

-- Source: Supabase Postgres, attached read-only via the session pooler. READ_ONLY is
-- an app-level guard against accidental writes from this pipeline -- it does not
-- change the underlying role's actual Postgres grants.
ATTACH '' AS pg_src (TYPE POSTGRES, SECRET pg_secret, READ_ONLY);

-- Target: DuckLake, catalog metadata stored in its own Postgres schema
-- (ducklake_catalog) inside the SAME Supabase database as the source tables
-- (reusing pg_secret), data files stored in S3. METADATA_SCHEMA keeps catalog
-- tables isolated from the ducklake_prod_ingestion application schema.
ATTACH 'ducklake:postgres:' AS lake (
    DATA_PATH 's3://ducklake-prod-tutorial/',
    METADATA_SCHEMA 'ducklake_catalog',
    METADATA_PARAMETERS MAP {'secret': 'pg_secret'}
);

CREATE SCHEMA IF NOT EXISTS lake.ducklake_prod_ingestion;

-- ============================================================================
-- Pattern A: FULL REFRESH (illustrative -- not executed by default)
-- Use this instead of Pattern B below when the table is small/cheap to rebuild
-- and you'd rather not track a watermark column.
-- ============================================================================
-- CREATE OR REPLACE TABLE lake.ducklake_prod_ingestion.events_rich_source AS
--     SELECT src.*
--     FROM pg_src.ducklake_prod_ingestion.events_rich_source AS src;

-- ============================================================================
-- Pattern B: INCREMENTAL sync based on updated_at (active pattern for this table)
-- Assumes events_rich_source has an `updated_at` timestamp column and an `id`
-- primary key -- verify both before first run (see setup notes).
-- ============================================================================

-- Bootstrap the target table on first run only; no-op once it exists.
CREATE TABLE IF NOT EXISTS lake.ducklake_prod_ingestion.events_rich_source AS
    SELECT src.*
    FROM pg_src.ducklake_prod_ingestion.events_rich_source AS src
    WHERE 1 = 0;

-- Pull only rows changed since the target's current high-water mark.
CREATE OR REPLACE TEMP TABLE events_rich_source_batch AS
    SELECT src.*
    FROM pg_src.ducklake_prod_ingestion.events_rich_source AS src
    WHERE src.updated_at > (
        SELECT COALESCE(MAX(tgt.updated_at), TIMESTAMP '1970-01-01')
        FROM lake.ducklake_prod_ingestion.events_rich_source AS tgt
    );

-- Drop any existing versions of those rows, then insert the fresh versions
-- (delete-then-insert, since it works regardless of unique-constraint support).
DELETE FROM lake.ducklake_prod_ingestion.events_rich_source AS tgt
WHERE tgt.id IN (SELECT batch.id FROM events_rich_source_batch AS batch);

INSERT INTO lake.ducklake_prod_ingestion.events_rich_source
    SELECT * FROM events_rich_source_batch;
