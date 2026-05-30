#!/usr/bin/env bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
RED_BOLD='\033[1;31m'
NC='\033[0m'

DB_FILE="maverick_operational_data.db"
API_LOG_FILE="api_server.log"
DASH_LOG_FILE="dashboard_server.log"

PID_API=0
PID_DASHBOARD=0

cleanup() {
    echo -e "\n${YELLOW}Initiating cleanup...${NC}"
    if [ "$PID_API" -ne 0 ] && ps -p $PID_API > /dev/null; then
        echo -e "${YELLOW}Stopping API server (PID: $PID_API)...${NC}"
        kill $PID_API
        wait $PID_API 2>/dev/null
        echo -e "${GREEN}API server stopped.${NC}"
    else
        echo -e "${CYAN}API server (PID: $PID_API) was not running or PID not captured.${NC}"
    fi

    if [ "$PID_DASHBOARD" -ne 0 ] && ps -p $PID_DASHBOARD > /dev/null; then
        echo -e "${YELLOW}Stopping Dashboard server (PID: $PID_DASHBOARD)...${NC}"
        kill $PID_DASHBOARD
        wait $PID_DASHBOARD 2>/dev/null
        echo -e "${GREEN}Dashboard server stopped.${NC}"
    else
        echo -e "${CYAN}Dashboard server (PID: $PID_DASHBOARD) was not running or PID not captured.${NC}"
    fi
    echo -e "${GREEN}Cleanup complete. Demo finished.${NC}"
    exit 0
}

trap cleanup SIGINT SIGTERM

if [ -f "$DB_FILE" ]; then
    echo -e "${YELLOW}Removing previous demo database ($DB_FILE)...${NC}"
    rm "$DB_FILE"
fi
rm -f "$API_LOG_FILE" "$DASH_LOG_FILE"

echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  MAVERICK LOGISTICS — INTEGRATED DASHBOARD PoC — Axiom LLC${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "${YELLOW}This demo will run the data pipeline, start the API & Dashboard servers.${NC}"
echo -e "${YELLOW}Server logs will be written to '$API_LOG_FILE' and '$DASH_LOG_FILE'.${NC}"
echo -e "${YELLOW}Ensure Python dependencies are installed:${NC}"
echo -e "${YELLOW}  pip install pandas requests Flask dash dash-bootstrap-components plotly${NC}"
echo ""
echo -e "${YELLOW}Press Enter to begin data ingestion...${NC}"
read

echo -e "${CYAN}STEP 1: Running data ingestion (data_ingestion.py)${NC}"
echo -e "${CYAN}-----------------------------------------------------------------------${NC}"
python3 data_ingestion.py
echo ""
echo -e "${YELLOW}Ingestion complete. Database '${DB_FILE}' is populated.${NC}"
echo -e "${YELLOW}Press Enter to start servers...${NC}"
read

echo -e "${CYAN}STEP 2: Starting Operations API server (operations_api.py)${NC}"
echo -e "${CYAN}-------------------------------------------------------------------------${NC}"
python3 operations_api.py > "$API_LOG_FILE" 2>&1 &
PID_API=$!
if ps -p $PID_API > /dev/null; then
    echo -e "${GREEN}API server starting in background (PID: $PID_API). Log: $API_LOG_FILE${NC}"
    echo -e "${YELLOW}Allowing a few seconds for initialization...${NC}"
    sleep 3
else
    echo -e "${RED}ERROR: Failed to start API server. Check $API_LOG_FILE for details.${NC}"
    PID_API=0
fi
echo ""

echo -e "${CYAN}STEP 3: Starting Live Dashboard server (live_dashboard.py)${NC}"
echo -e "${CYAN}-------------------------------------------------------------------------${NC}"
python3 live_dashboard.py > "$DASH_LOG_FILE" 2>&1 &
PID_DASHBOARD=$!
if ps -p $PID_DASHBOARD > /dev/null; then
    echo -e "${GREEN}Dashboard server starting in background (PID: $PID_DASHBOARD). Log: $DASH_LOG_FILE${NC}"
    echo -e "${YELLOW}Allowing a few seconds for initialization...${NC}"
    sleep 3
else
    echo -e "${RED}ERROR: Failed to start Dashboard server. Check $DASH_LOG_FILE for details.${NC}"
    PID_DASHBOARD=0
fi
echo ""

if [ "$PID_API" -ne 0 ] && [ "$PID_DASHBOARD" -ne 0 ]; then
    echo -e "${GREEN}Both servers running!${NC}"
    echo -e "${YELLOW}  - API:       http://127.0.0.1:5000${NC}"
    echo -e "${YELLOW}  - Dashboard: http://127.0.0.1:8050${NC}"
    echo ""
    echo -e "${YELLOW}Tail logs in separate terminals:${NC}"
    echo -e "${YELLOW}  tail -f ${API_LOG_FILE}${NC}"
    echo -e "${YELLOW}  tail -f ${DASH_LOG_FILE}${NC}"
    echo ""
    echo -e "${RED_BOLD}Press Ctrl+C IN THIS TERMINAL to stop both servers.${NC}"
    wait
else
    echo -e "${RED_BOLD}CRITICAL ERROR: One or both servers failed to start.${NC}"
    if [ "$PID_API" -eq 0 ]; then echo -e "${RED}  API Log: ${API_LOG_FILE}${NC}"; fi
    if [ "$PID_DASHBOARD" -eq 0 ]; then echo -e "${RED}  Dashboard Log: ${DASH_LOG_FILE}${NC}"; fi
    cleanup
fi
