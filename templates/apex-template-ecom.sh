#!/bin/bash
# ============================================================
# APEX INTEGRATION TEMPLATE — E-COMMERCE / DROPSHIPPING
# Version: 1.0
# Author: [Your Name] — Independent IT Consultant
# Client: [Store Name]
# ============================================================
# DIRECTORY STRUCTURE:
#   ~/ecom/
#     orders/           # Daily order export CSVs from platform
#     products/         # Product catalog and listing files
#     suppliers/        # Supplier contacts and pricing
#     customers/        # Customer CRM and segment files
#     returns/          # Return and refund tracking
#     ads/              # Ad campaign performance exports
#     reports/          # Generated reports
#     copy/             # Auto-generated product copy and ads
#     audio/            # Narrated owner briefings
#     archives/         # Rotated historical data
#     logs/             # Script execution logs
# ============================================================
# INTEGRATES WITH:
#   Shopify — configure auto-export orders CSV to ~/ecom/orders/
#   WooCommerce — use WP-CLI export on cron
#   Any platform with CSV export capability
# ============================================================
# CRON SCHEDULE:
#   0 7  * * *    ./apex-ecom.sh morning
#   0 21 * * *    ./apex-ecom.sh eod
#   0 8  * * 1    ./apex-ecom.sh weekly
#   0 6  * * *    ./apex-ecom.sh ad-check
#   0 9  1 * *    ./apex-ecom.sh monthly
# ============================================================

DATE=$(date +%Y-%m-%d)
DAY=$(date +%A)
WEEK=$(date +%V)
MONTH=$(date +%B)
STORE="[Store Name]"

mkdir -p ~/ecom/{orders,products,suppliers,customers,returns,ads,reports,copy,audio,archives,logs}

CMD=${1:-morning}

# ── MORNING BRIEF ─────────────────────────────────────────
morning_brief() {
    # Process yesterday's orders
    YESTERDAY=$(date -d "yesterday" +%Y-%m-%d)

    apex "parse the orders CSV for ${YESTERDAY} in ~/ecom/orders \
    and calculate total revenue orders count \
    average order value and top 5 products \
    and write to ~/ecom/reports/sales-${YESTERDAY}.txt" &

    apex "read ~/ecom/ads/performance-${YESTERDAY}.txt \
    and calculate total ad spend ROAS CPC and CTR by campaign \
    and write to ~/ecom/reports/ads-${YESTERDAY}.txt" &

    apex "read ~/ecom/returns/returns-log.txt \
    and count returns opened yesterday and calculate return rate \
    and write to ~/ecom/reports/returns-${YESTERDAY}.txt" &

    wait

    apex "read ~/ecom/reports/sales-${YESTERDAY}.txt \
    ~/ecom/reports/ads-${YESTERDAY}.txt \
    ~/ecom/reports/returns-${YESTERDAY}.txt \
    and write a structured ${DAY} morning brief for ${STORE} \
    with sections for yesterday's revenue ad performance \
    return rate and today's priorities \
    to ~/ecom/reports/morning-brief-${DATE}.txt"

    apex "read ~/ecom/reports/morning-brief-${DATE}.txt \
    and use espeak in a sharp e-commerce analyst voice at speed 150 \
    and save to ~/ecom/audio/morning-brief-${DATE}.wav"

    aplay ~/ecom/audio/morning-brief-${DATE}.wav 2>/dev/null
}

# ── GENERATE PRODUCT COPY ─────────────────────────────────
generate_product_copy() {
    PRODUCT_NAME=$2
    CATEGORY=$3
    FEATURES=$4
    PRICE=$5

    apex "write compelling e-commerce product copy for ${PRODUCT_NAME} \
    category ${CATEGORY} key features: ${FEATURES} price ${PRICE} \
    including a punchy headline product description 150 words \
    5 bullet point features and SEO meta description \
    to ~/ecom/copy/${PRODUCT_NAME// /-}-copy.txt"

    # Generate ad variants
    apex "read ~/ecom/copy/${PRODUCT_NAME// /-}-copy.txt \
    and write 5 Facebook and Instagram ad copy variants \
    ranging from curiosity hook to direct response to social proof \
    to ~/ecom/copy/${PRODUCT_NAME// /-}-ads.txt"

    apex "use espeak to say product copy and ad variants generated for ${PRODUCT_NAME}"
}

# ── AD PERFORMANCE CHECK ──────────────────────────────────
ad_check() {
    apex "read ~/ecom/ads/performance-${DATE}.txt \
    and identify any campaigns with ROAS below 2.0 \
    CPC above threshold or CTR below 1 percent \
    and write kill or scale recommendations \
    to ~/ecom/ads/recommendations-${DATE}.txt"

    apex "read ~/ecom/ads/recommendations-${DATE}.txt \
    and use espeak to announce any campaigns recommended for pause or scaling"
}

# ── CUSTOMER SEGMENT ANALYSIS ─────────────────────────────
customer_analysis() {
    apex "parse all order CSVs in ~/ecom/orders \
    and segment customers into first-time repeat and VIP \
    calculate lifetime value by segment and average order frequency \
    to ~/ecom/customers/segments-${DATE}.txt"

    apex "read ~/ecom/customers/segments-${DATE}.txt \
    and write targeted win-back email copy for lapsed customers \
    loyalty reward offer for VIP customers \
    and upsell email for first-time buyers \
    to ~/ecom/copy/email-segments-${DATE}.txt"

    apex "use espeak to say customer segmentation and email copy complete"
}

# ── SUPPLIER REORDER CHECK ────────────────────────────────
supplier_reorder() {
    apex "read ~/ecom/products/inventory-levels.txt \
    ~/ecom/suppliers/suppliers.txt \
    and identify SKUs with stock below 14 day supply \
    based on recent sales velocity \
    and write reorder recommendations with supplier contacts \
    to ~/ecom/suppliers/reorder-${DATE}.txt"

    REORDER_COUNT=$(wc -l < ~/ecom/suppliers/reorder-${DATE}.txt 2>/dev/null || echo 0)
    apex "use espeak to say ${REORDER_COUNT} products flagged for reorder"
}

# ── EOD SUMMARY ───────────────────────────────────────────
end_of_day() {
    apex "parse today's orders CSV in ~/ecom/orders \
    and calculate real-time revenue orders and top products \
    to ~/ecom/reports/eod-sales-${DATE}.txt"

    apex "read ~/ecom/reports/eod-sales-${DATE}.txt \
    ~/ecom/reports/ads-${DATE}.txt \
    ~/ecom/reports/returns-${DATE}.txt \
    and write a full end of day report for ${DATE} at ${STORE} \
    with revenue ad spend net profit estimate and return rate \
    to ~/ecom/reports/eod-${DATE}.txt"

    apex "read ~/ecom/reports/eod-${DATE}.txt \
    and use espeak in a confident business voice at speed 140 \
    and save to ~/ecom/audio/eod-${DATE}.wav"

    aplay ~/ecom/audio/eod-${DATE}.wav 2>/dev/null
}

# ── WEEKLY REVIEW ─────────────────────────────────────────
weekly_review() {
    apex "read all daily sales reports from this week in ~/ecom/reports \
    and calculate weekly revenue order volume AOV \
    best day top products and revenue trend \
    to ~/ecom/reports/weekly-sales-${DATE}.txt" &

    apex "read all ad performance files from this week in ~/ecom/ads \
    and calculate weekly total spend ROAS by campaign \
    and best performing creative \
    to ~/ecom/reports/weekly-ads-${DATE}.txt" &

    apex "read ~/ecom/returns/returns-log.txt \
    and calculate weekly return rate by product \
    and identify any problem products \
    to ~/ecom/reports/weekly-returns-${DATE}.txt" &

    wait

    apex "read ~/ecom/reports/weekly-sales-${DATE}.txt \
    ~/ecom/reports/weekly-ads-${DATE}.txt \
    ~/ecom/reports/weekly-returns-${DATE}.txt \
    and write a comprehensive weekly e-commerce review for week ${WEEK} at ${STORE} \
    with revenue analysis ad efficiency product performance and strategic recommendations \
    to ~/ecom/reports/weekly-review-${DATE}.txt"

    apex "read ~/ecom/reports/weekly-review-${DATE}.txt \
    and use espeak in a Gary Vaynerchuk voice at speed 155 \
    and save to ~/ecom/audio/weekly-review-${DATE}.wav"

    aplay ~/ecom/audio/weekly-review-${DATE}.wav 2>/dev/null

    apex "archive all daily files older than 7 days in ~/ecom \
    into ~/ecom/archives/week-${WEEK}.tar.gz \
    then use espeak to say weekly review complete"
}

# ── MONTHLY REPORT ────────────────────────────────────────
monthly_report() {
    apex "read all weekly reports in ~/ecom/reports \
    and generate a full monthly e-commerce performance report for ${MONTH} \
    covering total revenue total ad spend net revenue \
    top 20 products customer acquisition cost \
    return rate and month on month growth \
    to ~/ecom/reports/monthly-${MONTH}.txt"

    apex "read ~/ecom/reports/monthly-${MONTH}.txt \
    and use espeak in a Wall Street analyst voice at speed 140 \
    and save to ~/ecom/audio/monthly-${MONTH}.wav"

    aplay ~/ecom/audio/monthly-${MONTH}.wav 2>/dev/null
}

# ── ROUTER ────────────────────────────────────────────────
case $CMD in
    morning)        morning_brief ;;
    product-copy)   generate_product_copy "$@" ;;
    ad-check)       ad_check ;;
    customers)      customer_analysis ;;
    reorder)        supplier_reorder ;;
    eod)            end_of_day ;;
    weekly)         weekly_review ;;
    monthly)        monthly_report ;;
    *)              echo "Unknown: $CMD" ;;
esac
