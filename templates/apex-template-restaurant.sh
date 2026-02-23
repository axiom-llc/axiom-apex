#!/bin/bash
# ============================================================
# APEX INTEGRATION TEMPLATE — RESTAURANT / FOOD SERVICE
# Version: 1.0
# Author: [Your Name] — Independent IT Consultant
# Client: [Restaurant Name]
# ============================================================
# DIRECTORY STRUCTURE:
#   ~/restaurant/
#     daily/            # Daily covers, sales, reservations
#     menu/             # Menu files, pricing, specials
#     staff/            # Staff schedules, labor logs
#     inventory/        # Ingredient stock levels
#     suppliers/        # Supplier contacts and orders
#     reports/          # Generated reports
#     audio/            # Narrated briefings for owner/manager
#     archives/         # Rotated historical data
#     logs/             # Script execution logs
# ============================================================
# CRON SCHEDULE:
#   0 9   * * *    ./apex-restaurant.sh morning
#   0 15  * * *    ./apex-restaurant.sh prep-brief
#   0 22  * * *    ./apex-restaurant.sh eod
#   0 8   * * 1    ./apex-restaurant.sh weekly
#   0 7   * * *    ./apex-restaurant.sh inventory-check
#   0 10  1 * *    ./apex-restaurant.sh monthly
# ============================================================

DATE=$(date +%Y-%m-%d)
DAY=$(date +%A)
WEEK=$(date +%V)
MONTH=$(date +%B)
RESTAURANT="[Restaurant Name]"
CITY="[City]"

mkdir -p ~/restaurant/{daily,menu,staff,inventory,suppliers,reports,audio,archives,logs}

CMD=${1:-morning}

# ── MORNING BRIEF ─────────────────────────────────────────
morning_brief() {
    apex "fetch https://wttr.in/${CITY} using curl extract temperature \
    and conditions and write to ~/restaurant/daily/weather-${DATE}.txt" &

    apex "read ~/restaurant/daily/reservations-${DATE}.txt \
    and summarize total covers by time slot \
    and write to ~/restaurant/daily/cover-summary-${DATE}.txt" &

    apex "read ~/restaurant/inventory/stock-levels.txt \
    and identify any ingredients critically low \
    and write alerts to ~/restaurant/inventory/low-stock-${DATE}.txt" &

    wait

    apex "read ~/restaurant/daily/weather-${DATE}.txt \
    ~/restaurant/daily/cover-summary-${DATE}.txt \
    ~/restaurant/inventory/low-stock-${DATE}.txt \
    ~/restaurant/staff/schedule-${DATE}.txt \
    and write a structured ${DAY} morning brief for ${RESTAURANT} \
    with sections for weather forecast covers expected \
    staff on shift stock alerts and specials \
    to ~/restaurant/reports/morning-brief-${DATE}.txt"

    apex "read ~/restaurant/reports/morning-brief-${DATE}.txt \
    and use espeak in Gordon Ramsay's voice at speed 145 \
    and save to ~/restaurant/audio/morning-brief-${DATE}.wav"

    aplay ~/restaurant/audio/morning-brief-${DATE}.wav 2>/dev/null
}

# ── PRE-SERVICE PREP BRIEF (3pm) ──────────────────────────
prep_brief() {
    apex "read ~/restaurant/daily/reservations-${DATE}.txt \
    ~/restaurant/menu/specials-${DATE}.txt \
    ~/restaurant/staff/schedule-${DATE}.txt \
    and write a pre-service brief covering tonight's covers \
    specials to push allergen notes and staffing \
    to ~/restaurant/reports/prep-brief-${DATE}.txt"

    apex "read ~/restaurant/reports/prep-brief-${DATE}.txt \
    and use espeak at speed 150 in a head chef voice \
    and save to ~/restaurant/audio/prep-brief-${DATE}.wav"

    aplay ~/restaurant/audio/prep-brief-${DATE}.wav 2>/dev/null
}

# ── DAILY SPECIAL GENERATOR ───────────────────────────────
generate_special() {
    apex "read ~/restaurant/inventory/stock-levels.txt \
    ~/restaurant/menu/cuisine-profile.txt \
    and generate 3 creative daily specials using ingredients \
    that are high in stock or near expiry \
    with dish name description and suggested price \
    to ~/restaurant/menu/specials-${DATE}.txt"

    apex "read ~/restaurant/menu/specials-${DATE}.txt \
    and use espeak in a French chef voice at speed 130 \
    and save to ~/restaurant/audio/specials-${DATE}.wav"

    aplay ~/restaurant/audio/specials-${DATE}.wav 2>/dev/null
}

# ── EOD SUMMARY ───────────────────────────────────────────
end_of_day() {
    apex "read ~/restaurant/daily/sales-${DATE}.txt \
    ~/restaurant/daily/cover-summary-${DATE}.txt \
    and calculate total revenue covers served \
    average spend per cover and top selling dishes \
    and write to ~/restaurant/reports/eod-sales-${DATE}.txt"

    apex "read ~/restaurant/reports/eod-sales-${DATE}.txt \
    ~/restaurant/daily/waste-log-${DATE}.txt \
    ~/restaurant/staff/schedule-${DATE}.txt \
    and write a full end of day report for ${DATE} at ${RESTAURANT} \
    to ~/restaurant/reports/eod-${DATE}.txt"

    apex "read ~/restaurant/reports/eod-${DATE}.txt \
    and use espeak in Morgan Freeman's voice at speed 135 \
    and save to ~/restaurant/audio/eod-${DATE}.wav"

    aplay ~/restaurant/audio/eod-${DATE}.wav 2>/dev/null
}

# ── INVENTORY CHECK ───────────────────────────────────────
inventory_check() {
    apex "read ~/restaurant/inventory/stock-levels.txt \
    ~/restaurant/suppliers/suppliers.txt \
    and generate a reorder list for any ingredients \
    below par level with supplier name contact and suggested order quantity \
    to ~/restaurant/suppliers/reorder-${DATE}.txt"

    apex "use espeak to say inventory check complete reorder list generated for ${DATE}"
}

# ── WEEKLY REVIEW ─────────────────────────────────────────
weekly_review() {
    apex "read all eod sales reports from this week in ~/restaurant/reports \
    and calculate weekly revenue covers average spend \
    best and worst performing days and top 10 dishes \
    to ~/restaurant/reports/weekly-${DATE}.txt" &

    apex "read all waste logs from this week in ~/restaurant/daily \
    and calculate total waste cost and identify patterns \
    to ~/restaurant/reports/weekly-waste-${DATE}.txt" &

    apex "read ~/restaurant/staff/schedule-${DATE}.txt \
    and calculate total labor hours and labor cost percentage \
    to ~/restaurant/reports/weekly-labor-${DATE}.txt" &

    wait

    apex "read ~/restaurant/reports/weekly-${DATE}.txt \
    ~/restaurant/reports/weekly-waste-${DATE}.txt \
    ~/restaurant/reports/weekly-labor-${DATE}.txt \
    and write a comprehensive weekly business review for ${RESTAURANT} \
    week ${WEEK} with revenue analysis waste report labor costs \
    and actionable recommendations \
    to ~/restaurant/reports/weekly-review-${DATE}.txt"

    apex "read ~/restaurant/reports/weekly-review-${DATE}.txt \
    and use espeak in a Michelin inspector voice at speed 135 \
    and save to ~/restaurant/audio/weekly-review-${DATE}.wav"

    aplay ~/restaurant/audio/weekly-review-${DATE}.wav 2>/dev/null

    apex "archive all daily files older than 7 days in ~/restaurant \
    into ~/restaurant/archives/week-${WEEK}.tar.gz \
    then use espeak to say weekly review complete"
}

# ── MONTHLY P&L ───────────────────────────────────────────
monthly_report() {
    apex "read all weekly reports in ~/restaurant/reports \
    and generate a full monthly P&L for ${MONTH} \
    covering total revenue cost of goods labor waste \
    gross margin and month on month trend \
    to ~/restaurant/reports/monthly-${MONTH}.txt"

    apex "read ~/restaurant/reports/monthly-${MONTH}.txt \
    and use espeak in a confident accountant voice at speed 140 \
    and save to ~/restaurant/audio/monthly-${MONTH}.wav"

    aplay ~/restaurant/audio/monthly-${MONTH}.wav 2>/dev/null
}

# ── ROUTER ────────────────────────────────────────────────
case $CMD in
    morning)        morning_brief ;;
    prep-brief)     prep_brief ;;
    special)        generate_special ;;
    eod)            end_of_day ;;
    inventory)      inventory_check ;;
    weekly)         weekly_review ;;
    monthly)        monthly_report ;;
    *)              echo "Unknown: $CMD" ;;
esac
