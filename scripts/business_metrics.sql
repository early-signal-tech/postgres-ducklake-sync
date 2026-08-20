-- Business Metrics from gold.events_rich_ml_gold
-- Connect with: ATTACH 'ducklake:ducklake_prod' AS my_ducklake; USE my_ducklake;

CREATE SCHEMA IF NOT EXISTS metrics;

-- 1. Revenue by User Tier
CREATE OR REPLACE TABLE metrics.revenue_by_tier AS
SELECT
  user_attributes_tier as tier,
  COUNT(DISTINCT user_id) as unique_users,
  SUM(user_attributes_mrr_value) as total_mrr,
  AVG(user_attributes_mrr_value) as avg_mrr_per_user,
  COUNT(*) as total_events
FROM gold.events_rich_ml_gold
GROUP BY user_attributes_tier
ORDER BY total_mrr DESC;

-- 2. Average Session Duration & Event Value by Device Type
CREATE OR REPLACE TABLE metrics.engagement_by_device AS
SELECT
  payload_device_type as device,
  COUNT(DISTINCT metadata_session_id) as unique_sessions,
  COUNT(DISTINCT user_id) as unique_users,
  ROUND(AVG(payload_duration_ms), 2) as avg_session_duration_ms,
  ROUND(AVG(payload_value), 2) as avg_event_value,
  ROUND(SUM(payload_value), 2) as total_event_value,
  COUNT(*) as total_events
FROM gold.events_rich_ml_gold
GROUP BY payload_device_type
ORDER BY unique_sessions DESC;

-- 3. AB Test Performance (Variant A vs B)
CREATE OR REPLACE TABLE metrics.ab_variant_performance AS
SELECT
  metadata_ab_variant as variant,
  event_type,
  COUNT(*) as event_count,
  COUNT(DISTINCT user_id) as unique_users,
  COUNT(DISTINCT metadata_session_id) as unique_sessions,
  ROUND(AVG(payload_value), 2) as avg_event_value,
  ROUND(AVG(payload_duration_ms), 2) as avg_duration_ms
FROM gold.events_rich_ml_gold
GROUP BY metadata_ab_variant, event_type
ORDER BY variant, event_count DESC;

-- 4. Page Performance Metrics
CREATE OR REPLACE TABLE metrics.page_performance AS
SELECT
  payload_page as page,
  COUNT(*) as total_events,
  COUNT(DISTINCT user_id) as unique_users,
  COUNT(DISTINCT metadata_session_id) as unique_sessions,
  ROUND(AVG(payload_value), 2) as avg_event_value,
  ROUND(AVG(payload_duration_ms), 2) as avg_duration_ms,
  ROUND(SUM(payload_value), 2) as total_value_generated
FROM gold.events_rich_ml_gold
GROUP BY payload_page
ORDER BY unique_users DESC;

-- 5. User Lifecycle Value (Days Since Signup vs Engagement)
CREATE OR REPLACE TABLE metrics.user_lifecycle AS
SELECT
  CASE
    WHEN user_attributes_signup_days_ago <= 7 THEN '0-7 days'
    WHEN user_attributes_signup_days_ago <= 30 THEN '8-30 days'
    WHEN user_attributes_signup_days_ago <= 90 THEN '31-90 days'
    ELSE '90+ days'
  END as user_age_cohort,
  COUNT(DISTINCT user_id) as unique_users,
  ROUND(AVG(user_attributes_mrr_value), 2) as avg_mrr,
  COUNT(*) as total_events,
  COUNT(DISTINCT metadata_session_id) as total_sessions,
  ROUND(AVG(payload_value), 2) as avg_event_value
FROM gold.events_rich_ml_gold
WHERE user_attributes_signup_days_ago IS NOT NULL
GROUP BY user_age_cohort
ORDER BY
  CASE user_age_cohort
    WHEN '0-7 days' THEN 1
    WHEN '8-30 days' THEN 2
    WHEN '31-90 days' THEN 3
    ELSE 4
  END;

-- View all metrics
SELECT '=== Revenue by Tier ===' as metric;
SELECT * FROM metrics.revenue_by_tier;

SELECT '=== Device Performance ===' as metric;
SELECT * FROM metrics.engagement_by_device;

SELECT '=== AB Test Results ===' as metric;
SELECT * FROM metrics.ab_variant_performance LIMIT 10;

SELECT '=== Top Pages ===' as metric;
SELECT * FROM metrics.page_performance;

SELECT '=== User Lifecycle ===' as metric;
SELECT * FROM metrics.user_lifecycle;
