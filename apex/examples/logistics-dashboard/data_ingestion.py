import pandas as pd
import requests
import sqlite3
from datetime import datetime

SHIPMENTS_LOG_CSV = 'shipments.csv'
PARTNER_TASKS_API_URL = "https://jsonplaceholder.typicode.com/todos"
DATABASE_NAME = 'maverick_operational_data.db'

PARTNER_ID_TO_NAME_MAP = {
    1: "Amazon-Prime",
    2: "Hertz-Local",
    3: "Uhaul-Interstate",
    4: "Budget-Airport",
    5: "Ryder-Logistics",
    6: "Enterprise-Corp"
}

def calculate_on_time_status(planned_arrival_str, actual_arrival_str, delivery_status):
    if pd.isna(actual_arrival_str) or actual_arrival_str == "" or delivery_status != "Delivered":
        return "Pending"
    try:
        planned = datetime.fromisoformat(planned_arrival_str)
        actual = datetime.fromisoformat(actual_arrival_str)
        if actual <= planned + pd.Timedelta(minutes=15):
            return "On-Time"
        else:
            return "Late"
    except ValueError:
        return "Error"

def create_db_tables(conn):
    cursor = conn.cursor()
    cursor.execute('''
    CREATE TABLE IF NOT EXISTS daily_shipments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shipment_id TEXT UNIQUE,
        log_date TEXT,
        vehicle_id TEXT,
        driver_id TEXT,
        partner_contract TEXT,
        origin_city TEXT,
        destination_city TEXT,
        load_type TEXT,
        package_count INTEGER,
        shipment_value_usd REAL,
        planned_departure_datetime TEXT,
        actual_departure_datetime TEXT,
        planned_arrival_datetime TEXT,
        actual_arrival_datetime TEXT,
        miles_driven REAL,
        fuel_consumed_gallons REAL,
        fuel_efficiency_mpg REAL,
        delivery_status TEXT,
        on_time_status_reported TEXT,
        on_time_status_calculated TEXT,
        notes TEXT
    )
    ''')

    cursor.execute('''
    CREATE TABLE IF NOT EXISTS partner_tasks_status (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        partner_contract TEXT,
        task_source_id INTEGER,
        task_title TEXT,
        task_completed_status BOOLEAN,
        simulated_service_health TEXT,
        log_timestamp TEXT DEFAULT CURRENT_TIMESTAMP
    )
    ''')
    conn.commit()
    print("[DB INFO] Database tables ensured.")

def ingest_shipments_data(conn):
    print(f"\n[INFO] Ingesting shipment data from '{SHIPMENTS_LOG_CSV}'...")
    try:
        df = pd.read_csv(SHIPMENTS_LOG_CSV)
        df['on_time_status_calculated'] = df.apply(lambda row: calculate_on_time_status(
            row['planned_arrival_datetime'], row['actual_arrival_datetime'], row['delivery_status']
        ), axis=1)
        df['fuel_efficiency_mpg'] = (df['miles_driven'] / df['fuel_consumed_gallons']).round(2)
        df['fuel_efficiency_mpg'] = df['fuel_efficiency_mpg'].fillna(0)
        df_to_insert = df[['shipment_id', 'log_date', 'vehicle_id', 'driver_id', 'partner_contract',
                           'origin_city', 'destination_city', 'load_type', 'package_count', 'shipment_value_usd',
                           'planned_departure_datetime', 'actual_departure_datetime', 'planned_arrival_datetime',
                           'actual_arrival_datetime', 'miles_driven', 'fuel_consumed_gallons',
                           'fuel_efficiency_mpg', 'delivery_status', 'on_time_status_reported',
                           'on_time_status_calculated', 'notes']]
        df_to_insert.to_sql('daily_shipments', conn, if_exists='replace', index=False)
        print(f"[SUCCESS] Ingested {len(df)} shipment records into 'daily_shipments' table.")
    except FileNotFoundError:
        print(f"[ERROR] Shipment log file not found: {SHIPMENTS_LOG_CSV}")
    except UnicodeDecodeError as e:
        print(f"[ERROR] Encoding error reading {SHIPMENTS_LOG_CSV}: {e}")
    except Exception as e:
        print(f"[ERROR] Failed to ingest shipment data: {e}")

def ingest_partner_tasks_data(conn):
    print(f"\n[INFO] Ingesting simulated partner tasks from '{PARTNER_TASKS_API_URL}'...")
    partner_tasks_to_insert = []
    try:
        for api_user_id, partner_name in PARTNER_ID_TO_NAME_MAP.items():
            response = requests.get(PARTNER_TASKS_API_URL, params={'userId': api_user_id}, timeout=10)
            response.raise_for_status()
            todos = response.json()

            for todo in todos[:5]:
                task_completed_status = todo['completed']
                sim_health = "OK" if task_completed_status else "Action Required"
                partner_tasks_to_insert.append((
                    partner_name,
                    todo['id'],
                    todo['title'],
                    task_completed_status,
                    sim_health
                ))

        if partner_tasks_to_insert:
            cursor = conn.cursor()
            cursor.executemany('''
            INSERT OR IGNORE INTO partner_tasks_status
            (partner_contract, task_source_id, task_title, task_completed_status, simulated_service_health)
            VALUES (?, ?, ?, ?, ?)
            ''', partner_tasks_to_insert)
            conn.commit()
            print(f"[SUCCESS] Ingested {len(partner_tasks_to_insert)} simulated partner tasks into 'partner_tasks_status' table.")
        else:
            print("[INFO] No partner tasks to ingest.")

    except requests.exceptions.RequestException as e:
        print(f"[ERROR] API request failed for partner tasks: {e}")
    except Exception as e:
        print(f"[ERROR] Failed to ingest partner tasks: {e}")

def run_ingestion_service():
    print("-" * 60)
    print("  Maverick Data Ingestion Service")
    print("-" * 60)

    conn = sqlite3.connect(DATABASE_NAME)
    create_db_tables(conn)
    ingest_shipments_data(conn)
    ingest_partner_tasks_data(conn)
    conn.close()

    print(f"\n[INFO] Database '{DATABASE_NAME}' is ready.")
    print("\n" + "-" * 60)
    print("  Data Ingestion Complete.")
    print("-" * 60 + "\n")

if __name__ == "__main__":
    run_ingestion_service()
