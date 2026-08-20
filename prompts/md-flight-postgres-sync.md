PROMPT: CREATE MOTHERDUCK FLIGHT FOR POSTGRES-TO-DUCKLAKE INCREMENTAL SYNC

GOAL
Build a MotherDuck Flight that syncs new rows from Supabase Postgres to 
DuckLake (S3) daily at 06:00 UTC using timestamp watermarking.

REQUIREMENTS
- Source: Supabase Postgres (read-only)
- Target: DuckLake (data in S3, metadata in Postgres)
- Pattern: Incremental (only rows where ts > high water mark)
- Extensions: postgres, ducklake, httpfs
- Schedule: Daily 06:00 UTC (cron: 0 6 * * *)

SECRETS (Create in MotherDuck first)

Secret 1: pg_supabase (Type: Flights)
  HOST: project-pooler.supabase.co (use pooler, not direct connection)
  PORT: 5432
  DATABASE: postgres
  USER: [your user]
  PASSWORD: [your password]
  SSLMODE: require

Secret 2: s3_ducklake (Type: Flights)
  ACCESS_KEY_ID: [aws key]
  SECRET_ACCESS_KEY: [aws secret]
  REGION: us-east-1

FLIGHT CODE (Python)

1. Connect: con = duckdb.connect(”md:”)
2. Load extensions: postgres, ducklake, httpfs
3. Create secrets from env (pg_supabase_*, s3_ducklake_*)
4. ATTACH ‘’ AS pg_src (TYPE POSTGRES, SECRET pg_secret, READ_ONLY)
5. ATTACH ‘ducklake:postgres:’ AS lake (DATA_PATH ‘s3://bucket/’, 
   METADATA_SCHEMA ‘ducklake_meta’, METADATA_PARAMETERS MAP {’secret’: ‘pg_secret’})
6. CREATE SCHEMA IF NOT EXISTS “lake”.”schema_name”
7. Bootstrap target table (CREATE IF NOT EXISTS ... WHERE 1 = 0)
8. Get HWM: SELECT MAX(ts) FROM target (or TIMESTAMP ‘1970-01-01’)
9. Pull new rows: SELECT * FROM source WHERE ts > hwm
10. INSERT into target
11. Log batch size, close connection

DEPLOY

MD_CREATE_FLIGHT:
  name: postgres_ducklake_sync
  source_code: [Python above]
  requirements_txt: duckdb==1.5.5
  flight_secret_names: [”pg_supabase”, “s3_ducklake”]
  config: {SOURCE_SCHEMA: “ducklake_prod_ingestion”, SOURCE_TABLE: “events_rich_source”, 
           S3_BUCKET: “ducklake-prod-tutorial”, METADATA_SCHEMA: “ducklake_meta”, 
           WATERMARK_COLUMN: “ts”}
  schedule_cron: 0 6 * * *
  max_runtime_sec: 1800

TEST

Run on-demand, check logs for:
  ✓ “Connecting to MotherDuck...”
  ✓ “Attaching Postgres...”
  ✓ “Attaching DuckLake...”
  ✓ “Batch size: N rows”
  ✓ “Sync complete”

KEY GOTCHAS

- Use Supabase POOLER host (project-pooler.supabase.co), not direct connection
- DuckLake path is 2-level: lake.schema.table (not 3-level)
- Both secrets must be in flight_secret_names list
- Watermark column must be timestamp type
- First run bootstraps the table (expected)

TROUBLESHOOT

“Name or service not known” → Use pooler host, not direct Supabase connection
“Parser Error: too many dots” → Change to lake.schema.table (2 levels, not 3)
“Connection refused” → Check Supabase IP allowlist for MotherDuck IPs

ADJUST FOR DIFFERENT TABLE

Update config: SOURCE_SCHEMA, SOURCE_TABLE, WATERMARK_COLUMN
Re-run Flight (bootstraps new table automatically)