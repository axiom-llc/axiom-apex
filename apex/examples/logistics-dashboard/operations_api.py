from flask import Flask, jsonify, request
import sqlite3
from datetime import datetime

app = Flask(__name__)
DATABASE_NAME = 'maverick_operational_data.db'

def get_db_connection():
    conn = sqlite3.connect(DATABASE_NAME)
    conn.row_factory = sqlite3.Row
    return conn

@app.route('/api/logistics/daily_summary', methods=['GET'])
def get_daily_logistics_summary():
    conn = get_db_connection()
    cursor = conn.cursor()
    cursor.execute("""
        SELECT
            COUNT(shipment_id) as total_shipments,
            SUM(CASE WHEN delivery_status = 'Delivered' THEN 1 ELSE 0 END) as delivered_shipments,
            SUM(CASE WHEN on_time_status_calculated = 'On-Time' THEN 1 ELSE 0 END) as on_time_deliveries,
            SUM(CASE WHEN delivery_status = 'In-Transit' THEN 1 ELSE 0 END) as shipments_in_transit,
            AVG(fuel_efficiency_mpg) as average_fleet_mpg,
            SUM(shipment_value_usd) as total_value_in_transit_or_delivered
        FROM daily_shipments
        WHERE delivery_status IN ('Delivered', 'In-Transit')
    """)
    summary = cursor.fetchone()
    on_time_percentage = 0
    if summary and summary["delivered_shipments"] and summary["delivered_shipments"] > 0:
        on_time_percentage = round((summary["on_time_deliveries"] / summary["delivered_shipments"]) * 100, 2)
    conn.close()
    if summary and summary["total_shipments"] is not None:
        return jsonify({
            "report_date": "Overall (Demo Data)",
            "total_shipments_logged": summary["total_shipments"],
            "shipments_in_transit": summary["shipments_in_transit"] if summary["shipments_in_transit"] is not None else 0,
            "delivered_shipments": summary["delivered_shipments"] if summary["delivered_shipments"] is not None else 0,
            "on_time_delivery_percent": on_time_percentage,
            "average_fleet_mpg": round(summary["average_fleet_mpg"], 2) if summary["average_fleet_mpg"] else None,
            "total_value_shipped_usd": summary["total_value_in_transit_or_delivered"] if summary["total_value_in_transit_or_delivered"] is not None else 0
        })
    else:
        return jsonify({"error": "No summary data available"}), 404

@app.route('/api/partner_performance/status', methods=['GET'])
def get_partner_status():
    partner_contract_param = request.args.get('partner_contract', default="Amazon-Prime", type=str)
    conn = get_db_connection()
    cursor = conn.cursor()

    cursor.execute("""
        SELECT
            partner_contract,
            COUNT(shipment_id) as total_shipments_with_partner,
            SUM(CASE WHEN delivery_status = 'Delivered' THEN 1 ELSE 0 END) as delivered_by_partner,
            SUM(CASE WHEN on_time_status_calculated = 'On-Time' THEN 1 ELSE 0 END) as on_time_by_partner,
            AVG(shipment_value_usd) as avg_shipment_value_partner
        FROM daily_shipments
        WHERE partner_contract = ?
        GROUP BY partner_contract
    """, (partner_contract_param,))
    shipment_stats = cursor.fetchone()

    cursor.execute("""
        SELECT
            simulated_service_health, 
            COUNT(id) as status_count
        FROM partner_tasks_status 
        WHERE partner_contract = ?
        GROUP BY simulated_service_health
    """, (partner_contract_param,))
    service_health_logs = cursor.fetchall()
    conn.close()

    if not shipment_stats and not service_health_logs:
        return jsonify({"error": f"No data found for partner: {partner_contract_param}"}), 404

    partner_on_time_delivery_percent = 0
    if shipment_stats and shipment_stats["delivered_by_partner"] and shipment_stats["delivered_by_partner"] > 0:
        partner_on_time_delivery_percent = round(
            (shipment_stats["on_time_by_partner"] / shipment_stats["delivered_by_partner"]) * 100, 2
        )
    
    service_health_summary = {log["simulated_service_health"]: log["status_count"] for log in service_health_logs}

    return jsonify({
        "partner_contract": partner_contract_param,
        "shipment_metrics": {
            "total_shipments_with_partner": shipment_stats["total_shipments_with_partner"] if shipment_stats else 0,
            "delivered_by_partner": shipment_stats["delivered_by_partner"] if shipment_stats else 0,
            "on_time_delivery_percent_partner": partner_on_time_delivery_percent,
            "average_shipment_value_usd_partner": round(shipment_stats["avg_shipment_value_partner"], 2) if shipment_stats and shipment_stats["avg_shipment_value_partner"] is not None else None
        },
        "partner_service_health_summary": service_health_summary 
    })

def run_api_service():
    print("-" * 60)
    print("  Maverick Operations API Service - Act II")
    print("-" * 60)
    print("[INFO] Starting Flask API server for Maverick Operations...")
    print("[INFO] Daily Summary: http://127.0.0.1:5000/api/logistics/daily_summary")
    print("[INFO] Partner Status: http://127.0.0.1:5000/api/partner_performance/status?partner_contract=Amazon-Prime")
    print("           (Try other partners like Uhaul-Interstate, Hertz-Local etc.)")
    print("[INFO] Press CTRL+C in this terminal to stop the server.")
    print("-" * 60 + "\n")
    # Set debug=False if using the .sh script that redirects output
    app.run(host='127.0.0.1', port=5000, debug=False) 

if __name__ == '__main__':
    run_api_service()
