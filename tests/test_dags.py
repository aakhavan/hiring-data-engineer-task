import pytest
from airflow.models.dagbag import DagBag
import yaml

DAGS_PATH = "dags/"
CONFIG_PATH = "pipeline/config.yml"

@pytest.fixture(scope="session")
def dagbag():
    """Load all DAGs from the specified path once per test session."""
    return DagBag(dag_folder=DAGS_PATH, include_examples=False, read_dags_from_db=False)

@pytest.fixture(scope="session")
def pipeline_config():
    """Loads the pipeline config for use in tests."""
    with open(CONFIG_PATH, "r") as f:
        return yaml.safe_load(f)

def test_dag_bag_has_no_import_errors(dagbag):
    """Test that the DagBag has no import errors."""
    assert not dagbag.import_errors, f"DAG import errors found: {dagbag.import_errors}"

def test_retail_data_pipeline_dag_is_loaded(dagbag):
    """Test that the 'retail_data_pipeline' DAG is successfully loaded."""
    dag_id = "retail_data_pipeline"
    dag = dagbag.get_dag(dag_id)
    assert dag is not None, f"DAG '{dag_id}' not found in DagBag."
    assert dag.dag_id == dag_id

def test_dag_structure_and_task_groups(dagbag):
    """Verify the main task groups and their dependencies."""
    dag = dagbag.get_dag("retail_data_pipeline")
    assert dag is not None

    expected_groups = {"setup", "replicate_sources", "analytics"}
    assert set(dag.task_group_dict.keys()) == expected_groups, "DAG is missing expected task groups."

    setup_group = dag.task_group_dict["setup"]
    replication_group = dag.task_group_dict["replicate_sources"]
    analytics_group = dag.task_group_dict["analytics"]

    # Check dependencies between groups using downstream_group_ids
    assert "replicate_sources" in setup_group.downstream_group_ids, "Replication group should depend on setup group."
    assert "analytics" in replication_group.downstream_group_ids, "Analytics group should depend on replication group."

def test_dynamic_replication_tasks_are_created(dagbag, pipeline_config):
    """Verify that replication tasks are created based on the config file."""
    dag = dagbag.get_dag("retail_data_pipeline")
    replication_group = dag.task_group_dict["replicate_sources"]
    assert replication_group is not None

    expected_task_ids = {f"replicate_sources.replicate_{source['name']}" for source in pipeline_config["sources"]}
    found_task_ids = set(replication_group.children.keys())

    assert found_task_ids == expected_task_ids, "Mismatch between config and created replication tasks."

def test_dynamic_analytics_tasks_are_created(dagbag, pipeline_config):
    """Verify that analytics tasks are created based on the config file."""
    dag = dagbag.get_dag("retail_data_pipeline")
    analytics_group = dag.task_group_dict["analytics"]
    assert analytics_group is not None

    expected_task_ids = {f"analytics.{analytic['name']}" for analytic in pipeline_config["analytics"]}
    found_task_ids = set(analytics_group.children.keys())

    assert found_task_ids == expected_task_ids, "Mismatch between config and created analytics tasks."