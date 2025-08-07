# Data Engineering Assignment: Thought Process

This document outlines my approach and the key decisions made while building the solution for this assignment.

## Initial Approach

I have not worked with `ClickHouse` prior to this assignment, so I was happy to get the chance to learn more about it. I was impressed by its capabilities and feel I will use this technology for my own future projects.

I recognized this task as a Proof of Concept (POC), where the initial goal is to deliver a working result as quickly as possible so that business decision-makers can proceed with their analysis. With that in mind, I immediately researched best practices for connecting `Postgres` to `ClickHouse` and based my solution on a video on ClickHouse youtube channel discussing PeerDB technology.

## Architecture and Tooling

*   **Orchestration (`Airflow`)**: I chose to use `Airflow` for orchestration, as I have extensive experience with it and understood that it is also used by your company. To accomplish this, I extended the provided `docker-compose.yml` file to include a local `Airflow` service.

*   **Best Practices (Credentials)**: As a best practice, I implemented the database credentials as `Airflow` Connections. In a real production environment, this same concept would be managed through Infrastructure as Code (`Terraform`, etc.) and a secrets manager.

*   **Data Modeling (Medallion Architecture)**: I followed a Medallion design pattern, creating a three-layer setup (`Raw`, `Intermediate`, and `Analytics`) inside `ClickHouse`. My pipeline initially replicates the raw data from `Postgres` into the `Raw` and `Intermediate` layer and then performs analytical transformations on incrementally imported data in the subsequent `Reporting` layer.

## Key Technical Implementation

*   **Dynamic Queries**: My main emphasis was on creating a dynamic SQL query that can handle both a full initial load and subsequent incremental loads. This solution is derived from my own professional experience and is a pattern I would recommend in future employment. It allows for the same query logic to be templated and reused for many different tables, whether through `Airflow` or a tool like `dbt`. 

*   **Configuration-Driven DAG**: The `Airflow` DAG itself is driven by a configuration file where I have defined the source and destination tables. This approach makes the solution easier to scale and extend in the future with more advanced features like new data sources, Data Governance, Data Contracts, and further automation.

*   **Data Quality & CI/CD**: I have added several SQL-based data quality checks within the pipeline. I also implemented a GitHub Actions workflow to test the DAG, which is a proven best practice that reduces the risk of human error in a production environment.


Finally, I should declare that I fully utilize AI assistance (like `GitHub Copilot` and `Gemini`) in my development workflow. I believe this is a critical skill for modern professionals, as it significantly improves the quality of outputs on topics like generating tests, writing clean code, and creating documentation. While I have tried to limit the time spent on this assignment to keep it fair, I strongly believe that by leveraging AI, I can produce a higher-quality solution in a much shorter amount of time.

## How to Run the Application

This section provides a step-by-step guide to set up and run the entire data pipeline locally.

### Prerequisites

*   **Docker** and **Docker Compose**: Ensure you have both installed and running on your machine.

### 1. Environment Setup

Create a `.env` file in the root directory of the project. This file will store the necessary credentials for the services. Follow the format represented in `.env.example`. I have intentionally rename this file to keep the repo clean.



### 2. Start the Services

Open a terminal in the project's root directory and run the following command to build and start all the services (Postgres, ClickHouse, and Airflow) in the background:

```bash
docker-compose up -d
```

It may take a few minutes for all services to initialize and become healthy.

### 3. Seed the Database

Once the services are running, generate the seed data as explained in README.md

### 4. Run the Airflow Pipeline

1.  **Access the Airflow UI**: Open your web browser and navigate to `http://localhost:8081`.
2.  **Login**: Use the credentials you defined in your `.env` file (e.g., `admin`/`admin`).
3.  **Enable the DAG**: Find the `retail_data_pipeline` DAG in the list, and toggle the switch on the left to unpause it.
4.  **Trigger the DAG**: Click the "Play" button on the right side of the DAG's row to manually trigger a new run.

You can click on the DAG name to view the pipeline's progress in the Grid View.

### 5. Verify the Output

After the pipeline has completed successfully, you can verify the results.

*   **Connect to ClickHouse**: Use a database client (like DBeaver or the command-line client) to connect to ClickHouse on `localhost:8123` with the user `pycharm_user` and the password from your `.env` file. You can then query the tables in the `reporting` schema.

*   **Run Validation Script**: For a comprehensive check, execute the contents of the `pipeline/sql/validation/run_all_checks.sql` script in your ClickHouse client. A successful run should show `'OK'` for all checks or return an empty result set for the deep validation queries.