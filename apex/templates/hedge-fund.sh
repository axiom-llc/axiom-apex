#!/usr/bin/env bash
# ============================================================
# hedge-fund.sh — Pre-market intelligence brief
# Requires: apex, curl
# Config:   echo "AAPL,MSFT,NVDA,BTC-USD" > ~/.config/apex/watchlist
#           echo "macro,tech,energy" > ~/.config/apex/sectors
# Cron:     0 6 * * 1-5 ~/path/to/hedge-fund.sh >> ~/hedge/logs/hedge.log 2>&1
# ============================================================
set -euo pipefail

DATE=$(date +%Y-%m-%d)
DAY=$(date +%A)
WATCHLIST=$(cat ~/.config/apex/watchlist 2>/dev/null || echo "AAPL,MSFT,NVDA,BTC-USD")
SECTORS=$(cat ~/.config/apex/sectors 2>/dev/null || echo "macro,tech,energy")
mkdir -p ~/hedge/{signals,macro,thesis,logs,archives}

# ── PHASE 1: RAW DATA INGESTION (parallel) ────────────────
apex "fetch https://finance.yahoo.com/markets/stocks/most-active/ using http_get \
and extract top 20 most active tickers with price and volume changes \
and write to ~/hedge/signals/active.txt" &

apex "fetch https://finance.yahoo.com/markets/stocks/gainers/ using http_get \
and extract top gainers with percentage moves \
and write to ~/hedge/signals/gainers.txt" &

apex "fetch https://finance.yahoo.com/markets/stocks/losers/ using http_get \
and extract top losers with percentage moves \
and write to ~/hedge/signals/losers.txt" &

apex "fetch https://api.hnpwa.com/v0/news/1.json using http_get \
and extract all stories related to markets finance tech or economics \
and write to ~/hedge/signals/hn_signals.txt" &

apex "fetch https://feeds.a.dj.com/rss/RSSMarketsMain.xml using http_get \
and extract headlines and summaries from the last 12 hours \
and write to ~/hedge/macro/wsj_feed.txt" &

wait

# ── PHASE 2: SECTOR + MACRO ANALYSIS (parallel) ───────────
apex "read ~/hedge/signals/active.txt ~/hedge/signals/gainers.txt ~/hedge/signals/losers.txt \
and identify dominant sector rotation signals for today: ${SECTORS} \
and write a structured sector momentum brief to ~/hedge/macro/sectors.txt" &

apex "read ~/hedge/macro/wsj_feed.txt ~/hedge/signals/hn_signals.txt \
and extract macro signals: fed language, inflation data, geopolitical risk, credit stress \
and write to ~/hedge/macro/macro_signals.txt" &

apex "read ~/hedge/signals/active.txt ~/hedge/signals/gainers.txt \
and identify unusual volume or momentum anomalies that suggest institutional positioning \
and write to ~/hedge/signals/institutional.txt" &

wait

# ── PHASE 3: WATCHLIST POSITIONING ───────────────────────
apex "for each ticker in ${WATCHLIST}: \
assess current momentum signals from ~/hedge/signals/ and ~/hedge/macro/ files, \
infer likely pre-market direction, key levels, and catalyst risk, \
write a structured per-ticker brief to ~/hedge/signals/watchlist.txt"

# ── PHASE 4: THESIS GENERATION ────────────────────────────
apex "read all files in ~/hedge/signals and ~/hedge/macro \
and write a structured pre-market investment thesis for ${DATE} ${DAY} with sections: \
MACRO ENVIRONMENT | SECTOR ROTATION | INSTITUTIONAL SIGNALS | WATCHLIST OUTLOOK | \
TOP CONVICTION IDEAS | RISK FLAGS | POSITIONING BIAS \
to ~/hedge/thesis/thesis-${DATE}.txt"

# ── PHASE 5: EXECUTIVE BRIEF ──────────────────────────────
apex "read ~/hedge/thesis/thesis-${DATE}.txt \
and distill into a 5-bullet pre-market brief a portfolio manager reads in 60 seconds \
each bullet under 20 words, action-oriented, no hedging \
write to ~/hedge/thesis/brief-${DATE}.txt"

cat ~/hedge/thesis/brief-${DATE}.txt

# ── PHASE 6: ARCHIVE ──────────────────────────────────────
YESTERDAY=$(date -d "yesterday" +%Y-%m-%d)
ARCHIVE=~/hedge/archives/${YESTERDAY}.tar.gz
if [[ ! -f "$ARCHIVE" ]]; then
    find ~/hedge/{signals,macro,thesis} \
        -maxdepth 1 -name "*${YESTERDAY}*" -print0 | \
        tar czf "$ARCHIVE" --null -T - 2>/dev/null || true
fi
