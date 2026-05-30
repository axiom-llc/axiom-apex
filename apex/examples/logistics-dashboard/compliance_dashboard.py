import dash
from dash import dcc, html
from dash.dependencies import Input, Output, State
import dash_bootstrap_components as dbc
import os

from google import genai

GEMINI_READY = False
try:
    client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])
    print("[INFO] Gemini API configured successfully for dashboard.")
    GEMINI_READY = True
except KeyError:
    print("[ERROR] DASHBOARD: GEMINI_API_KEY environment variable not found!")
except Exception as e:
    print(f"[ERROR] DASHBOARD: Failed to configure Gemini API: {e}")

SIMULATED_CONTRACTS = {
    "Amazon-Prime": """
    Service Level Agreement for Amazon Prime Deliveries with Maverick Logistics:
    1. On-Time Delivery: 98% of all shipments must arrive within the planned 4-hour delivery window.
    2. Late Arrival Penalty: For shipments arriving more than 1 hour past the window, a $50 penalty applies. More than 4 hours late incurs a $200 penalty and requires immediate notification to amazon_logistics_ops@example.com.
    3. Real-time Tracking: Maverick must provide API updates every 15 minutes for shipments in transit. API downtime exceeding 1 hour per day is a breach.
    4. Damage Claims: Any reported damage must be documented with photos and submitted via the Partner Portal within 12 hours of delivery.
    5. Reporting: Weekly performance reports detailing on-time rates, exceptions, and API uptime are due by Monday 09:00 EST.
    """,
    "Uhaul-Interstate": """
    Maverick Logistics - Uhaul Interstate Transport Agreement:
    A. Vehicle Condition: All Uhaul-branded trucks operated by Maverick must pass a daily pre-trip inspection. Records to be auditable.
    B. Route Adherence: Approved interstate routes must be followed unless deviation is required for safety or unavoidable road closure, with immediate dispatch notification.
    C. Delay Notification: Any anticipated delay exceeding 2 hours against the original ETA must be communicated to Uhaul Dispatch (dispatch@uhaul-logistics.example.com) at least 1 hour prior to the original ETA if possible, or as soon as known.
    D. Load Security: Maverick is responsible for ensuring all cargo is secured according to Uhaul's "SafeLoad V2.1" manual. Breaches may result in liability.
    E. After-Hours Contact: For issues outside 08:00-18:00 Central Time, contact Uhaul Emergency Line: 1-800-UHAUL-HELP.
    """,
    "Hertz-Local": """
    Hertz Local Van Leasing & Operation Agreement - Maverick Addendum:
    - Mileage Cap: Leased vans under this agreement have a monthly mileage cap of 3000 miles per vehicle. Overages billed at $0.25/mile.
    - Maintenance Reporting: Any dashboard warning lights or suspected mechanical issues must be reported to hertz_fleet_maintenance@example.com within 4 operating hours.
    - Authorized Drivers Only: Only Maverick drivers pre-approved by Hertz (list updated monthly) may operate these vehicles.
    - Incident Reporting: All traffic incidents, regardless of severity, must be reported to Hertz Claims and Maverick Safety within 1 hour using the "MobileSafe" app.
    """
}
AVAILABLE_PARTNERS_LIST = list(SIMULATED_CONTRACTS.keys())


def get_partner_compliance_brief_for_dashboard(partner_name):
    if not GEMINI_READY:
        return dcc.Markdown("Gemini API not ready.")
    if partner_name not in SIMULATED_CONTRACTS:
        return dcc.Markdown(f"No contract for {partner_name}")
    contract_snippet = SIMULATED_CONTRACTS[partner_name]
    prompt = f"""You are an AI assistant for Maverick Logistics. Given the contract snippet for '{partner_name}': --- {contract_snippet} --- Generate a "Quick Compliance Brief" highlighting 3-4 most critical operational "Must Do's" or "Key Obligations". Present as actionable bullet points. Be concise."""
    try:
        response = client.models.generate_content(model="gemini-2.5-flash", contents=prompt)
        return dcc.Markdown(response.text)
    except Exception as e:
        return dcc.Markdown(f"Error with Gemini: {e}")


def analyze_scenario_compliance_for_dashboard(partner_name, operational_scenario):
    if not GEMINI_READY:
        return dcc.Markdown("Gemini API not ready.")
    if partner_name not in SIMULATED_CONTRACTS:
        return dcc.Markdown(f"No contract for {partner_name}")
    if not operational_scenario.strip():
        return dcc.Markdown("Please provide an operational scenario.")
    contract_snippet = SIMULATED_CONTRACTS[partner_name]
    prompt = f"""You are an AI compliance analyst for Maverick Logistics. Contract with '{partner_name}': --- {contract_snippet} --- Scenario: "{operational_scenario}" --- Based *only* on the contract and scenario: 1. Potential breaches/obligations (e.g., notifications, penalties)? 2. Immediate actions for Maverick staff per contract? 3. If no implications, state so. Be specific."""
    try:
        response = client.models.generate_content(model="gemini-2.5-flash", contents=prompt)
        return dcc.Markdown(response.text)
    except Exception as e:
        return dcc.Markdown(f"Error with Gemini: {e}")


app = dash.Dash(__name__, external_stylesheets=[dbc.themes.BOOTSTRAP])
app.title = "Maverick Compliance Assistant"

app.layout = dbc.Container([
    dbc.Row(dbc.Col(html.H1("Maverick Partner Compliance Assistant", className="text-center text-primary my-4"))),

    dbc.Row([
        dbc.Col([
            dbc.Card([
                dbc.CardHeader("Select Partner & Action"),
                dbc.CardBody([
                    dbc.Label("Partner Name:"),
                    dcc.Dropdown(
                        id='gemini-partner-dropdown',
                        options=[{'label': partner, 'value': partner} for partner in AVAILABLE_PARTNERS_LIST],
                        value=AVAILABLE_PARTNERS_LIST[0],
                        className="mb-3"
                    ),
                    dbc.Button("Get Quick Compliance Brief", id="btn-get-brief", color="info", className="me-2 mb-2", n_clicks=0),
                    html.Hr(),
                    dbc.Label("Operational Scenario (Optional):"),
                    dcc.Textarea(
                        id='gemini-scenario-input',
                        placeholder="Describe an operational scenario here...",
                        style={'width': '100%', 'height': 100},
                        className="mb-3"
                    ),
                    dbc.Button("Analyze Scenario Compliance", id="btn-analyze-scenario", color="success", className="mb-2", n_clicks=0),
                ])
            ], className="mb-4")
        ], width=12, md=5),

        dbc.Col([
            dbc.Card([
                dbc.CardHeader("Gemini AI Analysis"),
                dbc.CardBody(id='gemini-output-area', children=[
                    dbc.Alert("Select an action and partner to see results.", color="secondary")
                ])
            ])
        ], width=12, md=7)
    ]),
    dbc.Row(dbc.Col(html.P(
        "Note: This is a Proof of Concept using simulated contract data and Google's Gemini AI.",
        className="text-muted small text-center mt-4"
    )))

], fluid=True, className="p-3")


@app.callback(
    Output('gemini-output-area', 'children'),
    [Input('btn-get-brief', 'n_clicks'),
     Input('btn-analyze-scenario', 'n_clicks')],
    [State('gemini-partner-dropdown', 'value'),
     State('gemini-scenario-input', 'value')],
    prevent_initial_call=True
)
def update_gemini_output(n_brief, n_analyze, selected_partner, scenario_text):
    ctx = dash.callback_context
    if not ctx.triggered:
        return dbc.Alert("Please select an action.", color="info")

    button_id = ctx.triggered[0]['prop_id'].split('.')[0]

    if not GEMINI_READY:
        return dbc.Alert("Gemini API is not configured. Please set GEMINI_API_KEY environment variable.", color="danger")

    if not selected_partner:
        return dbc.Alert("Please select a partner.", color="warning")

    if button_id == 'btn-get-brief':
        print(f"[DASH INFO] Getting brief for {selected_partner}")
        return html.Div([html.H4(f"Compliance Brief: {selected_partner}"),
                         get_partner_compliance_brief_for_dashboard(selected_partner)])

    elif button_id == 'btn-analyze-scenario':
        if not scenario_text or not scenario_text.strip():
            return dbc.Alert("Please enter an operational scenario to analyze.", color="warning")
        print(f"[DASH INFO] Analyzing scenario for {selected_partner}: {scenario_text[:50]}...")
        return html.Div([html.H4(f"Scenario Analysis: {selected_partner}"),
                         html.P(f"Scenario: {scenario_text}", className="fst-italic mb-2"),
                         analyze_scenario_compliance_for_dashboard(selected_partner, scenario_text)])

    return dbc.Alert("No action selected or error.", color="light")


if __name__ == '__main__':
    if not GEMINI_READY:
        print("\n[CRITICAL] Gemini API key not configured. The dashboard will load but AI features will not work.")
        print("Please set the GEMINI_API_KEY environment variable and restart.")
    app.run_server(debug=False, host='127.0.0.1', port=8051)
