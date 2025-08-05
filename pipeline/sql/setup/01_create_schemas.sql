-- Create the necessary schemas for our pipeline.

-- 'raw' schema connects directly to the PostgreSQL source.
-- It uses Jinja templating to securely access connection details from Airflow.
CREATE DATABASE IF NOT EXISTS raw
ENGINE = PostgreSQL('{{ conn.postgres_source.host }}:{{ conn.postgres_source.port }}', '{{ conn.postgres_source.schema }}', '{{ conn.postgres_source.login }}', '{{ conn.postgres_source.password }}');

-- 'intermediate' schema for native ClickHouse tables replicated from the source.
CREATE DATABASE IF NOT EXISTS intermediate;

-- 'reporting' schema for the final, aggregated analytical tables.
CREATE DATABASE IF NOT EXISTS reporting;