# Feature Engineering for KNN/K-Means Clustering

Feature engineering guide for `events_rich_ml_gold` table, anchored to `user_id`.

## SQL: Create Feature Table

ATTACH 'ducklake:ducklake_prod' AS my_ducklake;
USE my_ducklake;

CREATE SCHEMA IF NOT EXISTS ml_datasets;

-- Feature engineering for KNN/K-Means clustering.
-- Categorical columns vary per event, so we take MODE() per user then one-hot encode.
CREATE OR REPLACE TABLE ml_datasets.features_for_knn_kmeans AS
WITH user_features AS (
  SELECT
    user_id,
    -- Engagement Features
    COUNT(*) as total_events,
    COUNT(DISTINCT event_type) as unique_event_types,
    COUNT(DISTINCT DATE(ts)) as days_active,
    DATEDIFF('day', MIN(ts), MAX(ts)) + 1 as user_lifespan_days,
    
    -- Event Type Distribution
    COUNT(CASE WHEN event_type = 'purchase' THEN 1 END) as purchase_events,
    COUNT(CASE WHEN event_type IN ('wishlist_add', 'wishlist_remove') THEN 1 END) as wishlist_events,
    COUNT(CASE WHEN event_type = 'rating' THEN 1 END) as rating_events,
    
    -- Behavioral Features
    COUNT(DISTINCT metadata_session_id) as total_sessions,
    AVG(payload_duration_ms) as avg_session_duration_ms,
    MAX(payload_duration_ms) as max_session_duration_ms,
    
    -- Monetary Features
    SUM(payload_value) as total_value,
    AVG(payload_value) as avg_event_value,
    SUM(payload_value) / NULLIF(COUNT(*), 0) as revenue_per_event,
    
    -- Device Diversity
    COUNT(DISTINCT payload_device_type) as device_types_used,
    
    -- Temporal Features
    DATEDIFF('day', MAX(ts), CURRENT_DATE) as days_since_last_event,
    MAX(user_attributes_signup_days_ago) as account_age_days,
    
    -- Purchase History
    MAX(payload_previous_purchase_count) as prev_purchase_count,
    
    -- Numeric user attributes
    AVG(user_attributes_mrr_value) as mrr_value,
    
    -- Frequency Metrics
    COUNT(*) / NULLIF(DATEDIFF('day', MIN(ts), MAX(ts)) + 1, 0) as events_per_day,
    COUNT(DISTINCT metadata_session_id) / NULLIF(DATEDIFF('day', MIN(ts), MAX(ts)) + 1, 0) as sessions_per_day,

    -- Modal categoricals (one-hotted in the outer SELECT)
    MODE(user_attributes_tier) as user_tier,
    MODE(user_attributes_country) as user_country,
    MODE(metadata_ab_variant) as ab_variant,
    MODE(payload_device_type) as primary_device,
    MODE(metadata_source) as primary_source
  
  FROM gold.events_rich_ml_gold
  GROUP BY user_id
)
SELECT
  user_id,
  COALESCE(total_events, 0) as total_events,
  COALESCE(unique_event_types, 0) as unique_event_types,
  COALESCE(days_active, 0) as days_active,
  COALESCE(user_lifespan_days, 0) as user_lifespan_days,
  COALESCE(purchase_events, 0) as purchase_events,
  COALESCE(wishlist_events, 0) as wishlist_events,
  COALESCE(rating_events, 0) as rating_events,
  COALESCE(total_sessions, 0) as total_sessions,
  COALESCE(avg_session_duration_ms, 0) as avg_session_duration_ms,
  COALESCE(max_session_duration_ms, 0) as max_session_duration_ms,
  COALESCE(total_value, 0) as total_value,
  COALESCE(avg_event_value, 0) as avg_event_value,
  COALESCE(revenue_per_event, 0) as revenue_per_event,
  COALESCE(device_types_used, 0) as device_types_used,
  COALESCE(days_since_last_event, 0) as days_since_last_event,
  COALESCE(account_age_days, 0) as account_age_days,
  COALESCE(prev_purchase_count, 0) as prev_purchase_count,
  COALESCE(mrr_value, 0) as mrr_value,
  COALESCE(events_per_day, 0) as events_per_day,
  COALESCE(sessions_per_day, 0) as sessions_per_day,

  -- One-hot: user_attributes_tier
  CASE WHEN user_tier = 'free' THEN 1 ELSE 0 END as tier_free,
  CASE WHEN user_tier = 'starter' THEN 1 ELSE 0 END as tier_starter,
  CASE WHEN user_tier = 'pro' THEN 1 ELSE 0 END as tier_pro,
  CASE WHEN user_tier = 'enterprise' THEN 1 ELSE 0 END as tier_enterprise,

  -- One-hot: user_attributes_country
  CASE WHEN user_country = 'AU' THEN 1 ELSE 0 END as country_au,
  CASE WHEN user_country = 'BR' THEN 1 ELSE 0 END as country_br,
  CASE WHEN user_country = 'CA' THEN 1 ELSE 0 END as country_ca,
  CASE WHEN user_country = 'DE' THEN 1 ELSE 0 END as country_de,
  CASE WHEN user_country = 'FR' THEN 1 ELSE 0 END as country_fr,
  CASE WHEN user_country = 'GB' THEN 1 ELSE 0 END as country_gb,
  CASE WHEN user_country = 'JP' THEN 1 ELSE 0 END as country_jp,
  CASE WHEN user_country = 'US' THEN 1 ELSE 0 END as country_us,

  -- One-hot: metadata_ab_variant
  CASE WHEN ab_variant = 'A' THEN 1 ELSE 0 END as variant_a,
  CASE WHEN ab_variant = 'B' THEN 1 ELSE 0 END as variant_b,

  -- One-hot: payload_device_type (modal device)
  CASE WHEN primary_device = 'mobile_android' THEN 1 ELSE 0 END as device_mobile_android,
  CASE WHEN primary_device = 'mobile_ios' THEN 1 ELSE 0 END as device_mobile_ios,
  CASE WHEN primary_device = 'tablet' THEN 1 ELSE 0 END as device_tablet,
  CASE WHEN primary_device = 'web' THEN 1 ELSE 0 END as device_web,

  -- One-hot: metadata_source (modal source)
  CASE WHEN primary_source = 'api' THEN 1 ELSE 0 END as source_api,
  CASE WHEN primary_source = 'email' THEN 1 ELSE 0 END as source_email,
  CASE WHEN primary_source = 'mobile' THEN 1 ELSE 0 END as source_mobile,
  CASE WHEN primary_source = 'push' THEN 1 ELSE 0 END as source_push,
  CASE WHEN primary_source = 'web' THEN 1 ELSE 0 END as source_web
FROM user_features
ORDER BY user_id;

-- Check the results
SELECT * FROM ml_datasets.features_for_knn_kmeans LIMIT 10;


## Python: Scale, Cluster & Find Neighbors

```python
import duckdb
import pandas as pd
import numpy as np
from sklearn.preprocessing import StandardScaler
from sklearn.cluster import KMeans
from sklearn.neighbors import NearestNeighbors

# Connect to DuckLake
con = duckdb.connect()
con.execute("ATTACH 'ducklake:ducklake_prod' AS my_ducklake;")
con.execute("USE my_ducklake;")

# Load the pre-engineered features
features_df = con.execute("""
    SELECT * FROM ml_datasets.features_for_knn_kmeans
""").df()

print(f"Loaded {len(features_df)} users with {len(features_df.columns)-1} features")

# Separate user_id and numeric features (categoricals are already one-hot encoded)
user_ids = features_df['user_id'].values
feature_cols = [col for col in features_df.columns if col != 'user_id']

X = features_df[feature_cols].values

# Standardize features (CRITICAL for KNN/K-Means)
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)

# K-Means Clustering
print("\nRunning K-Means (k=5)...")
kmeans = KMeans(n_clusters=5, random_state=42, n_init=10)
clusters = kmeans.fit_predict(X_scaled)

# KNN Analysis (find 5 nearest neighbors for each user)
print("Computing KNN (k=5)...")
knn = NearestNeighbors(n_neighbors=5)
knn.fit(X_scaled)
distances, indices = knn.kneighbors(X_scaled)

# Build result dataframe
result_df = features_df[['user_id']].copy()
result_df['cluster'] = clusters
result_df['nearest_neighbor_1'] = [user_ids[indices[i, 1]] for i in range(len(user_ids))]
result_df['nn_distance_1'] = [distances[i, 1] for i in range(len(user_ids))]

# Cluster statistics
print("\nCluster Distribution:")
print(result_df['cluster'].value_counts().sort_index())

# Save results
result_df.to_parquet('user_clusters_knn_kmeans.parquet', index=False)
print("\n✓ Results saved to user_clusters_knn_kmeans.parquet")

con.close()
```

## Features Explained

| Feature | Description |
|---------|-------------|
| `total_events` | Total number of events per user |
| `unique_event_types` | Count of distinct event types (diversity) |
| `days_active` | Number of unique days with activity |
| `user_lifespan_days` | Days between first and last event |
| `purchase_events` | Count of purchase events |
| `wishlist_events` | Count of wishlist adds/removes |
| `rating_events` | Count of rating events |
| `total_sessions` | Number of distinct sessions |
| `avg_session_duration_ms` | Average session length |
| `total_value` | Sum of all event values (revenue) |
| `revenue_per_event` | Average value per event |
| `device_types_used` | Device diversity (mobile, web, etc.) |
| `days_since_last_event` | Recency metric |
| `account_age_days` | User tenure |
| `events_per_day` | Engagement frequency |
| `tier_*` | One-hot of modal `user_attributes_tier` (free, starter, pro, enterprise) |
| `country_*` | One-hot of modal `user_attributes_country` (AU, BR, CA, DE, FR, GB, JP, US) |
| `variant_a` / `variant_b` | One-hot of modal `metadata_ab_variant` |
| `device_*` | One-hot of modal `payload_device_type` (mobile_android, mobile_ios, tablet, web) |
| `source_*` | One-hot of modal `metadata_source` (api, email, mobile, push, web) |

## Workflow

1. Run the SQL to create the `ml_datasets` schema and `ml_datasets.features_for_knn_kmeans` table
2. Run Python script to standardize and cluster
3. Results saved to `user_clusters_knn_kmeans.parquet`
