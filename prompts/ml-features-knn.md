Look at my DuckLake using the DuckDB CLI. 

You can use this attach statement:  

ATTACH 'ducklake:ducklake_prod' AS my_ducklake; 
USE my_ducklake;

First create a new schema if it doesnt' exist called ml_datasets.

Look at this table: 

FROM my_ducklake.gold.events_rich_ml_gold;

Give me either a SQL query or python script to build this dataset out into a 
feaure engineered dataset for KNN or K Means. 

I want to anchor into user_id
Use one hot encoding for category columns