#!/usr/bin/env python3
"""
KNN Algorithm for User Feature Analysis
Finds k-nearest neighbors for users in the ml_datasets.features_for_knn_kmeans dataset
"""

import duckdb
import pandas as pd
import numpy as np
from sklearn.preprocessing import StandardScaler
from sklearn.neighbors import NearestNeighbors
import matplotlib.pyplot as plt
from sklearn.decomposition import PCA

def load_data_from_ducklake():
    """Load features from DuckLake"""
    conn = duckdb.connect()
    conn.execute("ATTACH 'ducklake:ducklake_prod' AS my_ducklake")
    conn.execute("USE my_ducklake")

    result = conn.execute(
        "SELECT * FROM ml_datasets.features_for_knn_kmeans"
    ).fetchall()

    columns = [desc[0] for desc in conn.description]
    df = pd.DataFrame(result, columns=columns)

    conn.close()
    return df

def prepare_features(df):
    """Separate user IDs from features and scale them"""
    user_ids = df['user_id'].values
    features_df = df.drop('user_id', axis=1)

    scaler = StandardScaler()
    features_scaled = scaler.fit_transform(features_df)

    return user_ids, features_df, features_scaled

def fit_knn(features_scaled, n_neighbors=5):
    """Fit KNN model"""
    knn = NearestNeighbors(n_neighbors=n_neighbors, metric='euclidean')
    knn.fit(features_scaled)
    return knn

def find_nearest_neighbors(knn, features_scaled, user_ids, query_idx=0, k=5):
    """Find k-nearest neighbors for a specific user"""
    distances, indices = knn.kneighbors(features_scaled[query_idx:query_idx+1], n_neighbors=k)

    results = []
    for dist, idx in zip(distances[0], indices[0]):
        results.append({
            'neighbor_user': user_ids[idx],
            'distance': round(dist, 4)
        })

    return results

def analyze_user_similarity(knn, features_scaled, user_ids):
    """Analyze average similarity patterns across all users"""
    distances, indices = knn.kneighbors(features_scaled, n_neighbors=6)  # 6 to exclude self

    avg_distances = distances[:, 1:].mean(axis=1)  # Skip self (index 0)

    most_isolated = np.argmax(avg_distances)
    most_central = np.argmin(avg_distances)

    return {
        'most_isolated_user': user_ids[most_isolated],
        'most_isolated_distance': round(avg_distances[most_isolated], 4),
        'most_central_user': user_ids[most_central],
        'most_central_distance': round(avg_distances[most_central], 4),
        'avg_neighbor_distance': round(avg_distances.mean(), 4)
    }

def visualize_knn(features_scaled, user_ids):
    """Visualize users in 2D space using PCA"""
    pca = PCA(n_components=2)
    features_2d = pca.fit_transform(features_scaled)

    plt.figure(figsize=(12, 8))
    plt.scatter(features_2d[:, 0], features_2d[:, 1], alpha=0.6, s=100)

    for i, user_id in enumerate(user_ids):
        plt.annotate(user_id, (features_2d[i, 0], features_2d[i, 1]),
                    fontsize=8, alpha=0.7, xytext=(5, 5), textcoords='offset points')

    plt.xlabel(f'PC1 ({pca.explained_variance_ratio_[0]:.1%} variance)')
    plt.ylabel(f'PC2 ({pca.explained_variance_ratio_[1]:.1%} variance)')
    plt.title('User Distribution in Feature Space (PCA)')
    plt.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig('knn_user_distribution.png', dpi=150)
    print("✓ Visualization saved to knn_user_distribution.png")

def main():
    print("Loading data from DuckLake...")
    df = load_data_from_ducklake()
    print(f"✓ Loaded {len(df)} user records with {len(df.columns) - 1} features\n")

    print("Preparing features...")
    user_ids, features_df, features_scaled = prepare_features(df)
    print(f"✓ Features scaled to standardized format\n")

    print("Fitting KNN model (k=5)...")
    knn = fit_knn(features_scaled, n_neighbors=5)
    print("✓ KNN model fitted\n")

    print("=" * 60)
    print("FINDING NEIGHBORS FOR SAMPLE USERS")
    print("=" * 60)

    for sample_idx in [0, 10, 25]:
        neighbors = find_nearest_neighbors(knn, features_scaled, user_ids, sample_idx, k=5)
        print(f"\nUser: {user_ids[sample_idx]}")
        print("  Nearest neighbors (including self):")
        for i, neighbor in enumerate(neighbors):
            print(f"    {i+1}. {neighbor['neighbor_user']} (distance: {neighbor['distance']})")

    print("\n" + "=" * 60)
    print("OVERALL SIMILARITY ANALYSIS")
    print("=" * 60)
    analysis = analyze_user_similarity(knn, features_scaled, user_ids)
    print(f"\nMost central user (most similar to others): {analysis['most_central_user']}")
    print(f"  → Avg distance to neighbors: {analysis['most_central_distance']}")
    print(f"\nMost isolated user (least similar to others): {analysis['most_isolated_user']}")
    print(f"  → Avg distance to neighbors: {analysis['most_isolated_distance']}")
    print(f"\nOverall average neighbor distance: {analysis['avg_neighbor_distance']}")

    print("\n" + "=" * 60)
    print("CREATING VISUALIZATION")
    print("=" * 60)
    visualize_knn(features_scaled, user_ids)

    print("\n✓ KNN analysis complete!")

if __name__ == '__main__':
    main()
