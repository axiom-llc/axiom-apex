# Industrial Logistics Verification Dashboard

This blueprint demonstrates a secure, high-throughput logistics data-processing and auditing interface [2]. It is engineered to ingest shipment manifests, process records programmatically against strict ASON safety policies via the APEX API, and log the results into an audit-ready SQLite database [2].

---

## 1. System Architecture & Flow

```
shipments.csv ──> data_ingestion.py ──(HTTP POST)──> apex serve (port 8080)
                                                          │
   live_dashboard.py <── [SQLite Runs DB] <──(Logs Run)───┘
          │
  compliance_dashboard.py <── [operations_api.py]
```

1.  **Ingestion & Run Execution (`data_ingestion.py`)**: Parses local files (`shipments.csv`) and submits each transaction to `apex serve` for programmatic evaluation [2].
2.  **State Management & Compliance API (`operations_api.py`)**: Runs queries against the trace databases to expose compliance ratios, metrics, and state maps.
3.  **Real-Time Dashboards**:
    *   `live_dashboard.py` — Monitors live execution pipelines, tool outcomes, and step counts.
    *   `compliance_dashboard.py` — Dash interface rendering compliance metrics, error trends, and audit statistics.

---

## 2. Setup & Execution Guide

### Prerequisites
Ensure you have the required dependencies installed:
```bash
pip install dash pandas sqlite3
```

### Step 1: Start the APEX Server
In a dedicated terminal, launch the APEX API service on port `8080`:
```bash
apex serve --host 127.0.0.1 --port 8080
```

### Step 2: Run the Ingestion Pipeline
Execute the ingestion script to parse your shipments and populate the database:
```bash
python data_ingestion.py
```

### Step 3: Launch the Compliance Monitor
Launch the Dash visualization dashboard:
```bash
python compliance_dashboard.py
```

### Step 4: Access the Dashboard
Open your web browser and navigate to `http://127.0.0.1:8050` to audit shipment verification states, compliance statistics, and database traces [2].
