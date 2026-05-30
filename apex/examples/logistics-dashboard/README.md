# Logistics Intelligence Dashboard

This blueprint demonstrates a full-stack, compliance-driven logistics pipeline. It ingests CSV shipment records, validates transactions against ASON policy profiles, and presents verification results in an interactive web interface [2].

## System Components

*   `data_ingestion.py` — Ingests `shipments.csv` records, programmatically validates them using the APEX REST API, and stores structured traces in a SQLite ledger [2].
*   `operations_api.py` — A microservice providing transactional state checks and compliance evaluation loops.
*   `compliance_dashboard.py` — Dash (Flask-based) visualization engine serving real-time compliance ratios, error logs, and transactional graphs.
*   `live_dashboard.py` — Real-time event streaming interface monitoring plan execution and tool callbacks.

---

## Execution

1. Install standard dashboard dependencies:
   ```bash
   pip install dash pandas
   ```
2. Run the ingestion pipeline to parse shipment profiles (requires a running `apex serve` instance):
   ```bash
   python data_ingestion.py
   ```
3. Launch the dashboard interface:
   ```bash
   python compliance_dashboard.py
   ```
4. Audit results on `http://127.0.0.1:8050` in any diagnostic browser [2].
