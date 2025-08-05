class Replication:
    """
    Orchestrates data replication from PostgreSQL to ClickHouse
    using a PostgreSQL DATABASE ENGINE for connections.
    """

    # The tables we want to replicate, in order of dependency.
    # Names must match the tables in PostgreSQL exactly.
    TABLES_TO_REPLICATE = ["advertiser", "campaign", "impressions", "clicks"]

    def __init__(self, ch_client):
        self.ch_client = ch_client

    def _get_last_replicated_id(self, table_name: str) -> int:
        """Gets the maximum ID from the destination table in ClickHouse."""
        # The destination table name in ClickHouse is the same as the source.
        query = f"SELECT max(id) FROM default.{table_name}"
        result = self.ch_client.query(query)
        last_id = result.result_rows[0][0] if result.result_rows else 0
        return last_id if last_id is not None else 0

    def _run_replication_query(self, table_name: str):
        """
        Executes the INSERT INTO ... SELECT query to replicate data
        by selecting from the PostgreSQL-backed database engine.
        """
        last_id = self._get_last_replicated_id(table_name)
        print(f"Last replicated ID for '{table_name}': {last_id}")

        # This query is much simpler. It tells ClickHouse to select from the
        # 'pg_source' database (which is our live link to PostgreSQL) and
        # insert into the corresponding native MergeTree table.
        query = f"""
        INSERT INTO default.{table_name}
        SELECT * FROM pg_source.{table_name} WHERE id > {last_id}
        """

        print(f"Replicating new data for '{table_name}'...")
        self.ch_client.command(query)
        print(f"✅ Replication for '{table_name}' complete.")

    def run(self):
        """
        Executes the full replication pipeline for all tables.
        """
        print("🚀 Starting data replication run...")
        failed_table = None
        try:
            for table in self.TABLES_TO_REPLICATE:
                failed_table = table  # Keep track of the current table
                self._run_replication_query(table)
            print("🎉 Replication run finished successfully.")
        except Exception as e:
            # Provide a more specific error message for easier debugging.
            print(f"❌ An error occurred during replication of table '{failed_table}': {e}")
            # In a production system, you would add more robust error handling/logging here.
            raise