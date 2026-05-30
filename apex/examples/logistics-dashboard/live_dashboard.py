import dash
from dash import dcc, html
from dash.dependencies import Input, Output, State 
import requests
import pandas as pd
import plotly.express as px
import dash_bootstrap_components as dbc

# --- Configuration ---
API_BASE_URL = "http://127.0.0.1:5000/api"
AVAILABLE_PARTNERS = ["Amazon-Prime", "Hertz-Local", "Uhaul-Interstate", "Budget-Airport", "Ryder-Logistics", "Enterprise-Corp"]
ALL_PARTNERS_FOR_CHART = AVAILABLE_PARTNERS

# --- Initialize Dash App with Bootstrap Theme ---
app = dash.Dash(__name__, external_stylesheets=[dbc.themes.BOOTSTRAP])
app.title = "Maverick Operations Command Center"

# --- App Layout ---
app.layout = dbc.Container([
    dbc.Row(dbc.Col(html.H1("Maverick Operations Command Center", className="text-center text-primary my-4"))),

    # Section for Daily Logistics Summary
    dbc.Row([
        dbc.Col([
            html.H3("Daily Logistics Summary"),
            html.P("(Data primarily from internal shipment logs - CSV Source)", className="text-muted small mb-2"),
            dbc.Card(dbc.CardBody(id='daily-summary-kpis', children=[html.P("Loading...")]))
        ], width=12, md=6, className="mb-4"),

        dbc.Col([
            html.H3("Shipments by Partner (Overall)"),
            html.P("(Aggregated from internal shipment logs - CSV Source)", className="text-muted small mb-2"),
            dbc.Card(dbc.CardBody(dcc.Graph(id='partner-shipments-chart', figure={})))
        ], width=12, md=6, className="mb-4")
    ]),

    # Section for Detailed Partner Performance
    dbc.Row([
        dbc.Col([
            html.H3("Detailed Partner Performance"),
            dcc.Dropdown(
                id='partner-dropdown',
                options=[{'label': partner, 'value': partner} for partner in AVAILABLE_PARTNERS],
                value=AVAILABLE_PARTNERS[0],
                className="mb-3"
            ),
            dbc.Row([
                dbc.Col(
                    dbc.Card([
                        dbc.CardHeader("Shipment Metrics with Partner (from Internal CSV Data)"),
                        dbc.CardBody(id='partner-shipment-metrics-kpis')
                    ]), width=12, md=6, className="mb-3"
                ),
                dbc.Col(
                    dbc.Card([
                        dbc.CardHeader("Partner Service Health (from Simulated External API Data)"),
                        dbc.CardBody(id='partner-health-chart-kpis')
                    ]), width=12, md=6, className="mb-3"
                )
            ])
        ], width=12)
    ]),

    dcc.Interval(id='interval-component', interval=60*1000, n_intervals=0) # Refresh every 60s
], fluid=True, className="p-3")


# --- Callbacks to Update Dashboard Components ---

# Callback for Daily Logistics Summary
@app.callback(
    Output('daily-summary-kpis', 'children'),
    [Input('interval-component', 'n_intervals')]
)
def update_daily_summary(n):
    try:
        response = requests.get(f"{API_BASE_URL}/logistics/daily_summary")
        response.raise_for_status()
        data = response.json()
        
        kpi_items = [
            html.P(f"Total Shipments Logged: {data.get('total_shipments_logged', 'N/A')}", className="card-text"),
            html.P(f"Shipments In-Transit: {data.get('shipments_in_transit', 'N/A')}", className="card-text"),
            html.P(f"Delivered Shipments: {data.get('delivered_shipments', 'N/A')}", className="card-text"),
            html.H4(f"{data.get('on_time_delivery_percent', 'N/A')}%", className="card-title text-success"),
            html.P("On-Time Delivery Rate", className="card-text text-muted small"),
            html.P(f"Average Fleet MPG: {data.get('average_fleet_mpg', 'N/A')}", className="card-text mt-2"),
        ]
        return kpi_items
    except Exception as e:
        return dbc.Alert(f"Error fetching daily summary: {e}", color="danger")


# Callback for Shipments by Partner Chart
@app.callback(
    Output('partner-shipments-chart', 'figure'),
    [Input('interval-component', 'n_intervals')]
)
def update_partner_shipments_chart(n):
    partner_data_for_chart = []
    try:
        for partner in ALL_PARTNERS_FOR_CHART:
            response = requests.get(f"{API_BASE_URL}/partner_performance/status?partner_contract={partner}")
            if response.ok:
                data = response.json()
                shipments = data.get('shipment_metrics', {}).get('total_shipments_with_partner', 0)
                partner_data_for_chart.append({'Partner': partner, 'Total Shipments': shipments})
            else:
                partner_data_for_chart.append({'Partner': partner, 'Total Shipments': 0})
        
        if not partner_data_for_chart:
            fig = px.bar(title="No Partner Shipment Data Available")
        else:
            df_chart = pd.DataFrame(partner_data_for_chart)
            fig = px.bar(df_chart, x='Partner', y='Total Shipments', title="Shipments by Partner",
                         color='Partner', labels={'Total Shipments': 'Number of Shipments'})
            fig.update_layout(showlegend=False) 
        return fig
    except Exception as e:
        print(f"Error generating partner shipments chart: {e}")
        return px.bar(title=f"Error: {e}")


# Callback for Detailed Partner Performance (KPIs and Health Chart)
@app.callback(
    [Output('partner-shipment-metrics-kpis', 'children'),
     Output('partner-health-chart-kpis', 'children')],
    [Input('partner-dropdown', 'value'),
     Input('interval-component', 'n_intervals')]
)
def update_partner_performance_details(selected_partner, n):
    if not selected_partner:
        return dbc.Alert("Select partner.", color="info"), html.Div()

    try:
        response = requests.get(f"{API_BASE_URL}/partner_performance/status?partner_contract={selected_partner}")
        response.raise_for_status()
        data = response.json()

        shipment_metrics = data.get('shipment_metrics', {})
        service_health_summary = data.get('partner_service_health_summary', {})

        shipment_kpis_content = [
            html.P(f"Total Shipments: {shipment_metrics.get('total_shipments_with_partner', 'N/A')}", className="card-text"),
            html.P(f"Delivered: {shipment_metrics.get('delivered_by_partner', 'N/A')}", className="card-text"),
            html.H4(f"{shipment_metrics.get('on_time_delivery_percent_partner', 'N/A')}%", className="card-title text-info"), 
            html.P("Partner On-Time Delivery", className="card-text text-muted small"),
        ]

        health_data = []
        if service_health_summary:
            # Ensure keys used here EXACTLY match what the API sends in service_health_summary
            # These keys will be the 'Status' column in df_health
            health_data = [{'Status': k, 'Count': v} for k, v in service_health_summary.items() if v > 0]
        
        health_chart_figure = {}
        if health_data:
            df_health = pd.DataFrame(health_data)
            
            # Define the color map with EXACT key matching from your API data
            color_map = {
                'OK': 'green',             # Explicitly green for "OK"
                'Action Required': 'orange', # Orange for "Action Required"
                # If you have other statuses like 'Breached', add them here:
                # 'Breached': 'red' 
            }
            
            health_chart_figure = px.pie(df_health, 
                                         names='Status', 
                                         values='Count', 
                                         title=f"Simulated Service Health", # Simplified title
                                         color='Status', # Tell Plotly to color based on the 'Status' column
                                         color_discrete_map=color_map # Provide the explicit map
                                        )
            health_chart_figure.update_layout(
                legend_title_text='Service Status',
            )
        else:
            # Fallback if no health data
            health_chart_figure = px.pie(title=f"No Service Health Data") 
            health_chart_figure.update_layout(
                annotations=[dict(text='No Data', x=0.5, y=0.5, font_size=20, showarrow=False)]
            )
            
        health_chart_div_content = [dcc.Graph(figure=health_chart_figure)]

        return shipment_kpis_content, health_chart_div_content

    except Exception as e:
        error_msg = dbc.Alert(f"Error: {e}", color="danger")
        return error_msg, html.Div(error_msg) # Return error for both outputs

# --- Run the App ---
if __name__ == '__main__':
    # Set debug=False if using the .sh script that redirects output
    app.run_server(debug=False, host='127.0.0.1', port=8050)
