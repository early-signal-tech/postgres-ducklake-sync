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
    METADATA_SCHEMA 'ducklake_meta',
    METADATA_PARAMETERS MAP {'secret': 'pg_secret'}
);

-- ============================================================================
-- Pattern A: FULL REFRESH (illustrative -- not executed by default)
-- Use this if you ever need to rebuild the table from scratch.
-- ============================================================================
-- CREATE OR REPLACE TABLE lake.ducklake_prod_ingestion.events_rich_source AS
--     SELECT src.*
--     FROM pg_src.ducklake_prod_ingestion.events_rich_source AS src;

-- ============================================================================
-- Pattern B: INCREMENTAL sync based on ts (active pattern for immutable event tables)
-- Events are immutable, so we use the `ts` (event creation time) as a watermark:
-- only fetch rows with ts > the maximum ts we've seen before.
-- ============================================================================

-- Create the target schema if it doesn't exist (required before creating tables in it).
CREATE SCHEMA IF NOT EXISTS lake.ducklake_prod_ingestion;

-- Bootstrap the target table on first run only; no-op once it exists.
CREATE TABLE IF NOT EXISTS lake.ducklake_prod_ingestion.events_rich_source AS
    SELECT src.*
    FROM pg_src.ducklake_prod_ingestion.events_rich_source AS src
    WHERE 1 = 0;

-- Pull only rows (events) created since the target's current high-water mark (max ts, or epoch if empty).
CREATE OR REPLACE TEMP TABLE events_rich_source_batch AS
    SELECT src.*
    FROM pg_src.ducklake_prod_ingestion.events_rich_source AS src
    WHERE src.ts > (
        SELECT COALESCE(MAX(ts), TIMESTAMP '1970-01-01')
        FROM lake.ducklake_prod_ingestion.events_rich_source
    );

-- Upsert new rows (append-only for immutable events, but handles schema evolution gracefully).
-- For immutable tables, we can just INSERT; if you ever need to handle corrections/updates,
-- use delete-then-insert instead (see the commented pattern above).
INSERT INTO lake.ducklake_prod_ingestion.events_rich_source
    SELECT * FROM events_rich_source_batch;