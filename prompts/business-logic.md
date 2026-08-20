Look at my DuckLake using the DuckDB CLI. 

You can use this attach statement:  

ATTACH 'ducklake:ducklake_prod' AS my_ducklake; 
USE my_ducklake;

First create a new schema if it doesnt' exist called metrics.

Then look at this table: 

FROM my_ducklake.gold.events_rich_ml_gold;

Give me either a SQL query or python script to build this dataset out into a set of useful business metrics. No more than 5 metrics is necessary. 

Have new tables be places in the metrics schema.