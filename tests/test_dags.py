import pytest
from airflow.models.dagbag import DagBag
import yaml

# The path to the dags folder, relative to the project root
DAGS_PATH = "dags/"
CONFIG_PATH = "pipeline/config.yml"


@pytest.fixture(scope="session")
def dagbag():
    """
    A pytest fixture that loads all DAGs from the specified path once per test session.
    This is an efficient way to make the parsed DAGs available to all tests.
    """
    # We must set include_examples to False to avoid parsing Airflow's example DAGs
    return DagBag(dag_folder=DAGS_PATH, include_examples=False, read_dags_from_db=False)

@pytest.fixture(scope="session")
def pipeline_config():
    """Loads the pipeline config for use in tests."""
    with open(CONFIG_PATH, "r") as f:
        return yaml.safe_load(f)


def test_dag_bag_has_no_import_errors(dagbag):
    """
    Test that the DagBag has no import errors. This is the most critical test
    to ensure that all DAGs can be parsed by Airflow without syntax or import issues.
    """
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

    # Check for top-level task groups
    expected_groups = {"setup", "replicate_sources", "analytics"}
    assert set(dag.task_group_dict.keys()) == expected_groups, "DAG is missing expected task groups."

    # Check dependencies between groups
    setup_group = dag.get_task("setup")
    replication_group = dag.get_task("replicate_sources")
    analytics_group = dag.get_task("analytics")

    assert replication_group.task_id in setup_group.downstream_task_ids, "Replication group should depend on setup group."
    assert analytics_group.task_id in replication_group.downstream_task_ids, "Analytics group should depend on replication group."


def test_dynamic_replication_tasks_are_created(dagbag, pipeline_config):
    """Verify that replication tasks are created based on the config file."""
    dag = dagbag.get_dag("retail_data_pipeline")
    replication_group = dag.get_task_group("replicate_sources")
    assert replication_group is not None

    expected_task_ids = {f"replicate_sources.replicate_{source['name']}" for source in pipeline_config["sources"]}
    found_task_ids = {task.task_id for task in replication_group.children}

    assert found_task_ids == expected_task_ids, "Mismatch between config and created replication tasks."


def test_dynamic_analytics_tasks_are_created(dagbag, pipeline_config):
    """Verify that analytics tasks are created based on the config file."""
    dag = dagbag.get_dag("retail_data_pipeline")
    analytics_group = dag.get_task_group("analytics")
    assert analytics_group is not None

    expected_task_ids = {f"analytics.{analytic['name']}" for analytic in pipeline_config["analytics"]}
    found_task_ids = {task.task_id for task in analytics_group.children}

    assert found_task_ids == expected_task_ids, "Mismatch between config and created analytics tasks."