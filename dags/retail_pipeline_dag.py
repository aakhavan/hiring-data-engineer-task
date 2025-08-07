from __future__ import annotations

import yaml
import re
import pendulum

from airflow.models.dag import DAG
from airflow.utils.task_group import TaskGroup
from airflow_clickhouse_plugin.operators.clickhouse import ClickHouseOperator

# Define constants for file paths
PIPELINE_BASE_PATH = "/opt/airflow/pipeline"
CONFIG_FILE_PATH = f"{PIPELINE_BASE_PATH}/config.yml"
SQL_PATH = f"{PIPELINE_BASE_PATH}/sql"


def read_and_split_sql(sql_file: str) -> list[str]:
    """
    Reads a SQL file from the pipeline's SQL directory, removes comments,
    and splits it into a list of individual statements. This is a robust
    way to ensure the ClickHouseOperator executes each statement from a
    multi-statement file correctly.
    """
    full_path = f"{SQL_PATH}/{sql_file}"
    with open(full_path, "r") as f:
        sql_content = f.read()

    # Remove multi-line /* */ and single-line -- comments
    sql_content = re.sub(r"/\*.*?\*/", "", sql_content, flags=re.DOTALL)
    sql_content = re.sub(r"--.*", "", sql_content)

    # Split by semicolon and filter out any empty strings
    statements = [stmt.strip() for stmt in sql_content.split(";") if stmt.strip()]
    return statements

# Load the pipeline configuration from the YAML file
with open(CONFIG_FILE_PATH, "r") as f:
    config = yaml.safe_load(f)


with DAG(
    dag_id="retail_data_pipeline",
    start_date=pendulum.datetime(2024, 1, 1, tz="UTC"),
    schedule="@daily",
    catchup=False,
    # Enable Jinja templating for SQL files
    template_searchpath=f"{SQL_PATH}",
    render_template_as_native_obj=True,
    tags=["retail", "elt", "reporting"],
) as dag:
    # --- 1. Setup Group ---
    # Tasks for creating schemas and tables.
    with TaskGroup(group_id="setup") as setup_group:
        # This task uses Jinja templating to inject credentials into the SQL.
        create_schemas = ClickHouseOperator(
            task_id="create_schemas",
            clickhouse_conn_id="clickhouse_default",
            sql=read_and_split_sql("setup/01_create_schemas.sql"),
        )

        create_intermediate_tables = ClickHouseOperator(
            task_id="create_intermediate_tables",
            clickhouse_conn_id="clickhouse_default",
            sql=read_and_split_sql("setup/02_create_intermediate_tables.sql"),
        )

        create_schemas >> create_intermediate_tables

    # --- 2. Replication Group ---
    # Dynamically create a task for each source table defined in the config.
    with TaskGroup(group_id="replicate_sources") as replication_group:
        for source in config["sources"]:
            table_name = source["name"]

            # This SQL block performs a full, idempotent "truncate-and-load".
            # It ensures the intermediate table is a perfect, clean copy of the
            # source data. We provide a list of statements to the operator
            # to avoid multi-statement errors.
            replication_sql_statements = [
                f"TRUNCATE TABLE IF EXISTS intermediate.{table_name}",
                f"INSERT INTO intermediate.{table_name} SELECT * FROM raw.{table_name}",
            ]

            ClickHouseOperator(
                task_id=f"replicate_{table_name}",
                clickhouse_conn_id="clickhouse_default",
                sql=replication_sql_statements,
            )

    # --- 3. Analytics Group ---
    # Dynamically create a task for each analytics script defined in the config.
    with TaskGroup(group_id="analytics") as analytics_group:
        for analytic in config["analytics"]:
            ClickHouseOperator(
                task_id=analytic["name"],
                clickhouse_conn_id="clickhouse_default",
                sql=read_and_split_sql(analytic["script"]),
                # Add a docstring for clarity in the Airflow UI
                doc_md=analytic.get("description", ""),
            )

    # --- 4. Define Main Dependencies ---
    # This ensures the pipeline runs in the correct order: setup -> replicate -> analyze.
    setup_group >> replication_group >> analytics_group