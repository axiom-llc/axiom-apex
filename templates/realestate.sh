#!/usr/bin/env bash
# ============================================================
# APEX INTEGRATION TEMPLATE — REAL ESTATE AGENCY
# Version: 1.0
# Axiom LLC
# ============================================================
# DIRECTORY STRUCTURE:
#   ~/realestate/
#     listings/         # Active listing files (one per property)
#     leads/            # Inbound lead files
#     clients/          # Buyer/seller CRM files
#     viewings/         # Scheduled and completed viewings
#     offers/           # Offer tracking files
#     reports/          # Generated reports
#     market/           # Market data snapshots
#     audio/            # Narrated briefings for agents/principal
#     drafts/           # Auto-generated listing copy and emails
#     archives/         # Rotated historical data
#     logs/             # Script execution logs
# ============================================================
# CRON SCHEDULE:
#   0 8  * * 1-5   ./apex-realestate.sh morning
#   0 17 * * 1-5   ./apex-realestate.sh eod
#   0 9  * * 1     ./apex-realestate.sh weekly
#   0 7  * * *     ./apex-realestate.sh follow-up-check
#   0 9  1 * *     ./apex-realestate.sh monthly
# ============================================================

DATE=$(date +%Y-%m-%d)
DAY=$(date +%A)
WEEK=$(date +%V)
MONTH=$(date +%B)
AGENCY="[Agency Name]"

mkdir -p ~/realestate/{listings,leads,clients,viewings,offers,reports,market,audio,drafts,archives,logs}

CMD=${1:-morning}

# ── MORNING BRIEF ─────────────────────────────────────────
morning_brief() {
    apex "read all files in ~/realestate/viewings \
    and extract all viewings scheduled for today ${DATE} \
    and write to ~/realestate/viewings/today-${DATE}.txt" &

    apex "read ~/realestate/leads/new-leads.txt \
    and identify any uncontacted leads older than 24 hours \
    and write alerts to ~/realestate/leads/follow-up-${DATE}.txt" &

    apex "read all files in ~/realestate/offers \
    and identify any offers pending response \
    and write to ~/realestate/reports/pending-offers-${DATE}.txt" &

    wait

    apex "read ~/realestate/viewings/today-${DATE}.txt \
    ~/realestate/leads/follow-up-${DATE}.txt \
    ~/realestate/reports/pending-offers-${DATE}.txt \
    and write a structured ${DAY} morning brief for ${AGENCY} \
    with sections for today's viewings lead follow-ups and pending offers \
    to ~/realestate/reports/morning-brief-${DATE}.txt"

    apex "read ~/realestate/reports/morning-brief-${DATE}.txt \
    and use espeak in a confident estate agent voice at speed 145 \
    and save to ~/realestate/audio/morning-brief-${DATE}.wav"

    aplay ~/realestate/audio/morning-brief-${DATE}.wav 2>/dev/null
}

# ── NEW LISTING INTAKE ────────────────────────────────────
new_listing() {
    ADDRESS=$2
    TYPE=$3        # house, flat, commercial
    PRICE=$4
    BEDS=$5
    AGENT=$6
    SLUG=$(echo "$ADDRESS" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | tr ',' '')

    apex "write a new listing file for property at ${ADDRESS} \
    type ${TYPE} asking price ${PRICE} bedrooms ${BEDS} \
    agent ${AGENT} listed ${DATE} status ACTIVE \
    to ~/realestate/listings/${SLUG}.txt"

    # Auto-generate listing copy
    apex "write a compelling professional property listing description \
    for a ${BEDS} bedroom ${TYPE} at ${ADDRESS} priced at ${PRICE} \
    for use on Rightmove Zoopla and agency website \
    approximately 200 words highlighting key features and lifestyle appeal \
    to ~/realestate/drafts/listing-copy-${SLUG}.txt"

    # Generate social post
    apex "read ~/realestate/drafts/listing-copy-${SLUG}.txt \
    and write a short punchy social media post for the new listing \
    suitable for Instagram and Facebook under 150 words \
    to ~/realestate/drafts/social-${SLUG}.txt"

    apex "use espeak to say new listing added: ${ADDRESS} at ${PRICE}"

    echo "[${DATE}] New listing: ${SLUG}" >> ~/realestate/logs/listings.log
}

# ── NEW LEAD INTAKE ───────────────────────────────────────
new_lead() {
    NAME=$2
    EMAIL=$3
    PHONE=$4
    INTEREST=$5    # buying, selling, renting
    BUDGET=$6
    SLUG=$(echo "$NAME" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')

    apex "write a new lead file for ${NAME} email ${EMAIL} phone ${PHONE} \
    interest ${INTEREST} budget ${BUDGET} received ${DATE} status NEW \
    to ~/realestate/leads/${SLUG}-${DATE}.txt"

    # Auto-generate intro email draft
    apex "write a warm professional introduction email to new lead ${NAME} \
    who is interested in ${INTEREST} with budget ${BUDGET} \
    from ${AGENCY} offering to discuss requirements and next steps \
    to ~/realestate/drafts/intro-email-${SLUG}.txt"

    apex "append ${NAME} ${EMAIL} ${INTEREST} ${BUDGET} ${DATE} NEW \
    to ~/realestate/leads/new-leads.txt"

    apex "use espeak to say new lead received: ${NAME} interested in ${INTEREST}"
}

# ── FOLLOW-UP CHECKER ─────────────────────────────────────
follow_up_check() {
    apex "read all files in ~/realestate/clients \
    and identify any clients with no contact logged in 7 or more days \
    and write follow-up reminders to ~/realestate/leads/overdue-followup-${DATE}.txt"

    apex "read all files in ~/realestate/viewings \
    and identify any viewings completed more than 48 hours ago \
    with no offer or feedback logged \
    and write to ~/realestate/viewings/needs-feedback-${DATE}.txt"

    OVERDUE=$(wc -l < ~/realestate/leads/overdue-followup-${DATE}.txt 2>/dev/null || echo 0)

    if [ "$OVERDUE" -gt 0 ]; then
        apex "use espeak to say ${OVERDUE} clients are overdue for follow-up"
    fi
}

# ── MARKET SNAPSHOT ───────────────────────────────────────
market_snapshot() {
    apex "fetch https://api.propertydata.co.uk/prices?postcode=${POSTCODE} \
    using curl and write to ~/realestate/market/snapshot-${DATE}.txt" &

    apex "write a market commentary for ${DATE} \
    based on current interest rates housing supply and demand \
    and seasonal trends for the ${MONTH} property market \
    to ~/realestate/market/commentary-${DATE}.txt" &

    wait

    apex "read ~/realestate/market/snapshot-${DATE}.txt \
    ~/realestate/market/commentary-${DATE}.txt \
    and use espeak in a property analyst voice at speed 135 \
    and save to ~/realestate/audio/market-${DATE}.wav"

    aplay ~/realestate/audio/market-${DATE}.wav 2>/dev/null
}

# ── EOD SUMMARY ───────────────────────────────────────────
end_of_day() {
    apex "read ~/realestate/viewings/today-${DATE}.txt \
    ~/realestate/leads/new-leads.txt \
    ~/realestate/reports/pending-offers-${DATE}.txt \
    and write an end of day summary for ${DATE} at ${AGENCY} \
    covering viewings completed new leads received \
    offers outstanding and pipeline value \
    to ~/realestate/reports/eod-${DATE}.txt"

    apex "read ~/realestate/reports/eod-${DATE}.txt \
    and use espeak at speed 135 and save to \
    ~/realestate/audio/eod-${DATE}.wav"

    aplay ~/realestate/audio/eod-${DATE}.wav 2>/dev/null
}

# ── WEEKLY REVIEW ─────────────────────────────────────────
weekly_review() {
    apex "read all listing files in ~/realestate/listings \
    and generate a pipeline report showing active listings \
    days on market average asking price and viewing counts \
    to ~/realestate/reports/weekly-listings-${DATE}.txt" &

    apex "read all lead files in ~/realestate/leads \
    and calculate new leads this week conversion rate \
    and pipeline value \
    to ~/realestate/reports/weekly-leads-${DATE}.txt" &

    apex "read all offer files in ~/realestate/offers \
    and summarize offers made accepted rejected and pending \
    and total deal value this week \
    to ~/realestate/reports/weekly-offers-${DATE}.txt" &

    wait

    apex "read ~/realestate/reports/weekly-listings-${DATE}.txt \
    ~/realestate/reports/weekly-leads-${DATE}.txt \
    ~/realestate/reports/weekly-offers-${DATE}.txt \
    and write a comprehensive weekly business review for ${AGENCY} week ${WEEK} \
    with executive summary pipeline health lead conversion and market commentary \
    to ~/realestate/reports/weekly-review-${DATE}.txt"

    apex "read ~/realestate/reports/weekly-review-${DATE}.txt \
    and use espeak in Morgan Freeman's voice at speed 135 \
    and save to ~/realestate/audio/weekly-review-${DATE}.wav"

    aplay ~/realestate/audio/weekly-review-${DATE}.wav 2>/dev/null
}

# ── MONTHLY REPORT ────────────────────────────────────────
monthly_report() {
    apex "read all weekly reports in ~/realestate/reports \
    and generate a full monthly performance report for ${MONTH} \
    covering total listings active sold under offer \
    total commission earned lead volume and conversion rate \
    to ~/realestate/reports/monthly-${MONTH}.txt"

    apex "read ~/realestate/reports/monthly-${MONTH}.txt \
    and use espeak in a confident business voice at speed 140 \
    and save to ~/realestate/audio/monthly-${MONTH}.wav"

    aplay ~/realestate/audio/monthly-${MONTH}.wav 2>/dev/null
}

# ── ROUTER ────────────────────────────────────────────────
case $CMD in
    morning)        morning_brief ;;
    listing)        new_listing "$@" ;;
    lead)           new_lead "$@" ;;
    follow-up)      follow_up_check ;;
    market)         market_snapshot ;;
    eod)            end_of_day ;;
    weekly)         weekly_review ;;
    monthly)        monthly_report ;;
    *)              echo "Unknown: $CMD" ;;
esac
