#!/usr/bin/env bash
# ============================================================
# APEX INTEGRATION TEMPLATE — RETAIL / E-COMMERCE
# Version: 1.0
# Axiom LLC
# ============================================================
# DIRECTORY STRUCTURE:
#   ~/retail/
#     sales/            # Daily sales CSVs dropped here by POS/platform export
#     inventory/        # Stock level files updated by import scripts
#     reports/          # Generated daily/weekly/monthly reports
#     audio/            # Narrated owner briefings
#     suppliers/        # Supplier contact and order files
#     customers/        # Customer CRM plain text files
#     archives/         # Rotated historical data
#     logs/             # Script execution logs
# ============================================================
# CRON SCHEDULE:
#   0 7  * * *     daily-brief.sh         # Every morning
#   0 21 * * *     end-of-day.sh          # Every evening
#   0 8  * * 1     weekly-review.sh       # Monday morning
#   0 6  * * *     inventory-check.sh     # Pre-open inventory alert
#   0 9  1 * *     monthly-report.sh      # Monthly P&L summary
# ============================================================
# SETUP NOTES:
#   1. Configure POS/Shopify/WooCommerce to auto-export CSV to ~/retail/sales/
#   2. Set CITY variable to your location for weather (affects foot traffic context)
#   3. Set LOW_STOCK_THRESHOLD to your reorder point
#   4. Populate ~/retail/suppliers/suppliers.txt with supplier contacts

DATE=$(date +%Y-%m-%d)
DAY=$(date +%A)
WEEK=$(date +%V)
MONTH=$(date +%B)
BUSINESS="[Business Name]"
CITY="[City]"
LOW_STOCK_THRESHOLD=10

mkdir -p ~/retail/{sales,inventory,reports,audio,suppliers,customers,archives,logs}

# ── USAGE ─────────────────────────────────────────────────
# Daily brief:          ./apex-template-retail.sh brief
# EOD summary:          ./apex-template-retail.sh eod
# Inventory check:      ./apex-template-retail.sh inventory
# Weekly review:        ./apex-template-retail.sh weekly
# Monthly report:       ./apex-template-retail.sh monthly
# Process sales CSV:    ./apex-template-retail.sh process-sales sales-export.csv
# Log customer note:    ./apex-template-retail.sh customer "Jane Smith" "Frequent buyer, prefers email"

CMD=${1:-brief}

# ── DAILY MORNING BRIEF ───────────────────────────────────
daily_brief() {
    echo "[$(date)] Running daily brief..." >> ~/retail/logs/script.log

    # Parallel data gathering
    apex "fetch https://wttr.in/${CITY} using curl extract temperature \
    and conditions and write to ~/retail/reports/weather-${DATE}.txt" &

    apex "read the most recent file in ~/retail/sales and calculate \
    total revenue units sold and top 5 products \
    and write to ~/retail/reports/sales-snapshot-${DATE}.txt" &

    apex "read ~/retail/inventory/stock-levels.txt and identify any items \
    below threshold ${LOW_STOCK_THRESHOLD} units and write alerts \
    to ~/retail/inventory/low-stock-${DATE}.txt" &

    wait

    # Consolidated brief
    apex "read ~/retail/reports/weather-${DATE}.txt \
    ~/retail/reports/sales-snapshot-${DATE}.txt \
    ~/retail/inventory/low-stock-${DATE}.txt \
    and write a structured ${DAY} morning brief for ${BUSINESS} \
    with sections for weather outlook yesterday sales summary and stock alerts \
    to ~/retail/reports/daily-brief-${DATE}.txt"

    # Narrate for owner
    apex "read ~/retail/reports/daily-brief-${DATE}.txt \
    and use espeak in a clear professional voice at speed 145 \
    and save to ~/retail/audio/daily-brief-${DATE}.wav"

    aplay ~/retail/audio/daily-brief-${DATE}.wav 2>/dev/null

    echo "[$(date)] Daily brief complete." >> ~/retail/logs/script.log
}

# ── INVENTORY CHECK ───────────────────────────────────────
inventory_check() {
    echo "[$(date)] Running inventory check..." >> ~/retail/logs/script.log

    apex "read ~/retail/inventory/stock-levels.txt and generate a full \
    inventory health report flagging items below ${LOW_STOCK_THRESHOLD} units \
    items at zero stock and items with no movement in 30 days \
    to ~/retail/inventory/inventory-report-${DATE}.txt"

    apex "read ~/retail/inventory/inventory-report-${DATE}.txt \
    and ~/retail/suppliers/suppliers.txt \
    and write draft reorder recommendations with suggested quantities \
    and supplier contacts to ~/retail/suppliers/reorder-${DATE}.txt"

    apex "read ~/retail/inventory/inventory-report-${DATE}.txt \
    and use espeak to announce critical stock alerts \
    and save to ~/retail/audio/inventory-alert-${DATE}.wav"

    aplay ~/retail/audio/inventory-alert-${DATE}.wav 2>/dev/null

    echo "[$(date)] Inventory check complete." >> ~/retail/logs/script.log
}

# ── END OF DAY SUMMARY ────────────────────────────────────
end_of_day() {
    echo "[$(date)] Running EOD summary..." >> ~/retail/logs/script.log

    # Parallel analysis
    apex "parse the sales CSV for today in ~/retail/sales and calculate \
    total revenue average transaction value and units per category \
    and write to ~/retail/reports/eod-sales-${DATE}.txt" &

    apex "read ~/retail/reports/sales-snapshot-${DATE}.txt and compare \
    today's performance to yesterday and write variance analysis \
    to ~/retail/reports/eod-variance-${DATE}.txt" &

    wait

    apex "read ~/retail/reports/eod-sales-${DATE}.txt \
    ~/retail/reports/eod-variance-${DATE}.txt \
    ~/retail/inventory/low-stock-${DATE}.txt \
    and write a comprehensive end of day report for ${DATE} at ${BUSINESS} \
    to ~/retail/reports/eod-report-${DATE}.txt"

    apex "read ~/retail/reports/eod-report-${DATE}.txt \
    and use espeak in Morgan Freeman's voice at speed 135 \
    and save to ~/retail/audio/eod-${DATE}.wav"

    aplay ~/retail/audio/eod-${DATE}.wav 2>/dev/null

    echo "[$(date)] EOD complete." >> ~/retail/logs/script.log
}

# ── WEEKLY REVIEW ─────────────────────────────────────────
weekly_review() {
    echo "[$(date)] Running weekly review..." >> ~/retail/logs/script.log

    # Parallel weekly aggregation
    apex "read all sales reports in ~/retail/reports from the past 7 days \
    and calculate total weekly revenue daily averages best day worst day \
    and top 10 products to ~/retail/reports/weekly-sales-${DATE}.txt" &

    apex "read ~/retail/inventory/stock-levels.txt and generate weekly \
    inventory turnover analysis and restock priority list \
    to ~/retail/reports/weekly-inventory-${DATE}.txt" &

    apex "read all files in ~/retail/customers and identify top 10 customers \
    by purchase frequency and write customer insights \
    to ~/retail/reports/weekly-customers-${DATE}.txt" &

    wait

    # Consolidated weekly report
    apex "read ~/retail/reports/weekly-sales-${DATE}.txt \
    ~/retail/reports/weekly-inventory-${DATE}.txt \
    ~/retail/reports/weekly-customers-${DATE}.txt \
    and write a full weekly business review for week ${WEEK} at ${BUSINESS} \
    with executive summary revenue analysis inventory health and customer insights \
    to ~/retail/reports/weekly-review-${DATE}.txt"

    apex "read ~/retail/reports/weekly-review-${DATE}.txt \
    and use espeak in a confident business analyst voice at speed 140 \
    and save to ~/retail/audio/weekly-review-${DATE}.wav"

    aplay ~/retail/audio/weekly-review-${DATE}.wav 2>/dev/null

    # Archive
    apex "archive all daily report files older than 7 days in ~/retail/reports \
    into ~/retail/archives/week-${WEEK}.tar.gz \
    then use espeak to say weekly review complete"

    echo "[$(date)] Weekly review complete." >> ~/retail/logs/script.log
}

# ── MONTHLY P&L REPORT ────────────────────────────────────
monthly_report() {
    echo "[$(date)] Running monthly report..." >> ~/retail/logs/script.log

    apex "read all weekly sales reports in ~/retail/reports \
    and generate a full monthly P&L summary for ${MONTH} \
    with total revenue cost of goods sold gross margin and trends \
    to ~/retail/reports/monthly-${MONTH}.txt"

    apex "read ~/retail/reports/monthly-${MONTH}.txt \
    and use espeak in a Wall Street analyst voice at speed 140 \
    and save to ~/retail/audio/monthly-${MONTH}.wav"

    aplay ~/retail/audio/monthly-${MONTH}.wav 2>/dev/null

    echo "[$(date)] Monthly report complete." >> ~/retail/logs/script.log
}

# ── PROCESS SALES CSV ─────────────────────────────────────
process_sales() {
    CSV_FILE=$2

    apex "parse the CSV file at ~/retail/sales/${CSV_FILE} and extract \
    total sales units sold revenue by category and top products \
    and write structured report to ~/retail/reports/processed-${CSV_FILE%.csv}-${DATE}.txt"

    apex "append a summary line to ~/retail/sales/sales-master-log.txt \
    for date ${DATE} from file ${CSV_FILE} with total and unit count"

    apex "use espeak to say sales file ${CSV_FILE} processed and logged"
}

# ── LOG CUSTOMER NOTE ─────────────────────────────────────
log_customer() {
    CUSTOMER=$2
    NOTE=$3
    SLUG=$(echo "$CUSTOMER" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')

    apex "append a dated note to ~/retail/customers/${SLUG}.txt \
    with date ${DATE} note: ${NOTE}"

    apex "use espeak to say customer note logged for ${CUSTOMER}"
}

# ── ROUTER ────────────────────────────────────────────────
case $CMD in
    brief)          daily_brief ;;
    eod)            end_of_day ;;
    inventory)      inventory_check ;;
    weekly)         weekly_review ;;
    monthly)        monthly_report ;;
    process-sales)  process_sales "$@" ;;
    customer)       log_customer "$@" ;;
    *)              echo "Unknown command: $CMD" ;;
esac
