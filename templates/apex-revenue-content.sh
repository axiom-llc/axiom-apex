#!/bin/bash
# ============================================================
# APEX REVENUE TEMPLATE 2 — NICHE CONTENT & AFFILIATE ENGINE
# Model: Content farm → SEO traffic → affiliate commissions
# ROI profile: Slow burn, compounds over 3-6 months, then passive
# Est. return: $200-2000/month per niche site at maturity
# ============================================================
# HOW IT WORKS:
#   1. Generates SEO-optimized articles on a target niche
#   2. Writes articles to flat HTML/MD files ready to deploy
#   3. Tracks published URLs and internal link structure
#   4. Generates social media snippets per article
#   5. Produces weekly content calendar automatically
#
# DEPLOY OPTIONS:
#   A. Static site (Jekyll/Hugo) — commit generated MD files to git, auto-deploy via GitHub Pages
#   B. WordPress — pipe generated content to WP REST API via curl
#   C. Ghost CMS — pipe to Ghost Admin API via curl
#
# NICHES THAT WORK WELL WITH THIS MODEL:
#   Linux tooling reviews, open source software comparisons,
#   IT automation how-tos, homelab guides, VPS comparisons,
#   developer productivity tools — all areas you know deeply
#
# HUMAN TOUCHPOINTS (semi-autonomous):
#   - Weekly niche/keyword review (15 min)
#   - Spot-check 1 in 10 articles before publish
#   - Affiliate link insertion (semi-automated below)
#
# DEPLOYMENT:
#   VPS cron — generate 3 articles per day
#   0 6 * * *   ./apex-revenue-content.sh generate
#   0 7 * * 1   ./apex-revenue-content.sh weekly-calendar
# ============================================================

DATE=$(date +%Y-%m-%d)
WEEK=$(date +%V)
MONTH=$(date +%B)
mkdir -p ~/content/{articles,drafts,published,social,calendar,reports,logs,affiliate}

# ── CONFIGURE NICHE ───────────────────────────────────────
NICHE_FILE=~/content/niche.txt
if [ ! -f "$NICHE_FILE" ]; then
cat > "$NICHE_FILE" << 'EOF'
NICHE: Linux automation and open source IT tools
TARGET_AUDIENCE: sysadmins, DevOps engineers, independent IT consultants, homelabbers
TONE: expert, practical, direct, no fluff
ARTICLE_LENGTH: 1200-1800 words
AFFILIATE_PROGRAMS: Vultr, DigitalOcean, Linode, NordVPN, Hostinger
KEYWORDS_FOCUS: linux automation, bash scripting, open source tools, VPS setup, self-hosted, homelab
INTERNAL_LINK_TARGET: /tools /guides /reviews
EOF
fi

# ── AFFILIATE LINK MAP ────────────────────────────────────
AFFILIATE_FILE=~/content/affiliate/links.txt
if [ ! -f "$AFFILIATE_FILE" ]; then
cat > "$AFFILIATE_FILE" << 'EOF'
Vultr: https://www.vultr.com/?ref=YOURREF
DigitalOcean: https://m.do.co/c/YOURREF
Linode: https://www.linode.com/?r=YOURREF
NordVPN: https://nordvpn.com/ref/YOURREF
Hostinger: https://www.hostinger.com/YOURREF
EOF
fi

CMD=${1:-generate}

# ── GENERATE DAILY ARTICLES ───────────────────────────────
generate_articles() {
    echo "[${DATE}] Generating articles..." >> ~/content/logs/content.log

    # Read niche config and generate 3 articles
    apex "read ~/content/niche.txt and generate 3 distinct SEO-optimized article topics \
    with titles meta descriptions and keyword focus for today ${DATE} \
    and write to ~/content/calendar/topics-${DATE}.txt"

    # Generate each article in parallel
    for i in 1 2 3; do
        (
            SLUG="article-${DATE}-$(printf '%03d' $i)"

            apex "read ~/content/niche.txt \
            ~/content/calendar/topics-${DATE}.txt \
            and write article number ${i} from today's topic list \
            as a complete SEO-optimized markdown article with \
            H1 title H2 subheadings introduction body sections and conclusion \
            include practical code examples where relevant \
            length 1200 to 1800 words \
            to ~/content/drafts/${SLUG}.md"

            # Generate social snippets for each article
            apex "read ~/content/drafts/${SLUG}.md \
            and write 3 social media post variants \
            one for Twitter under 280 characters \
            one for LinkedIn professional tone 150 words \
            one for Reddit technical community tone \
            to ~/content/social/${SLUG}-social.txt"

            # Insert affiliate links
            apex "read ~/content/drafts/${SLUG}.md \
            and ~/content/affiliate/links.txt \
            and naturally insert 1 to 2 relevant affiliate links \
            where they fit contextually in the article \
            and write the updated article to ~/content/articles/${SLUG}.md"

            echo "[${DATE}] Article ${i} complete: ${SLUG}" >> ~/content/logs/content.log
        ) &
    done

    wait

    # Update master article index
    apex "append date ${DATE} articles article-${DATE}-001 article-${DATE}-002 article-${DATE}-003 \
    to ~/content/published/master-index.txt"

    apex "use espeak to say 3 articles generated for ${DATE} and ready for review"
}

# ── WEEKLY CONTENT CALENDAR ───────────────────────────────
weekly_calendar() {
    apex "read ~/content/niche.txt \
    ~/content/published/master-index.txt \
    and generate a full 7 day content calendar for next week \
    with article titles keywords estimated traffic potential \
    and content type mix how-to review comparison guide \
    to ~/content/calendar/week-${WEEK}.txt"

    apex "read ~/content/calendar/week-${WEEK}.txt \
    and use espeak in a confident voice at speed 140 \
    and save to ~/content/calendar/week-${WEEK}.wav"

    aplay ~/content/calendar/week-${WEEK}.wav 2>/dev/null
}

# ── PUBLISH TO STATIC SITE (Hugo/Jekyll) ─────────────────
publish_static() {
    SITE_DIR=${2:-~/sites/main}

    # Copy approved articles to site content directory
    apex "use shell to copy all markdown files from ~/content/articles \
    created today to ${SITE_DIR}/content/posts/"

    # Trigger site build and deploy
    apex "use shell to run cd ${SITE_DIR} && git add -A && \
    git commit -m 'content: auto-publish ${DATE}' && git push"

    apex "use espeak to say articles published to site for ${DATE}"
}

# ── PUBLISH TO WORDPRESS VIA REST API ─────────────────────
publish_wordpress() {
    WP_URL=$2
    WP_USER=$3
    WP_PASS=$4

    for article in ~/content/articles/article-${DATE}-*.md; do
        TITLE=$(head -1 "$article" | sed 's/# //')
        apex "read ${article} \
        and use shell to curl -X POST ${WP_URL}/wp-json/wp/v2/posts \
        with basic auth ${WP_USER}:${WP_PASS} \
        and post the article content as draft status \
        and log the response to ~/content/logs/wp-publish-${DATE}.txt"
    done

    apex "use espeak to say articles submitted to WordPress for ${DATE}"
}

# ── MONTHLY REVENUE REPORT ────────────────────────────────
monthly_report() {
    apex "read ~/content/published/master-index.txt \
    ~/content/logs/content.log \
    and write a monthly content production report for ${MONTH} \
    with total articles published social posts generated \
    affiliate links inserted and estimated content value \
    to ~/content/reports/monthly-${MONTH}.txt"

    apex "read ~/content/reports/monthly-${MONTH}.txt \
    and use espeak at speed 135 and save to ~/content/reports/monthly-${MONTH}.wav"

    aplay ~/content/reports/monthly-${MONTH}.wav 2>/dev/null
}

# ── ROUTER ────────────────────────────────────────────────
case $CMD in
    generate)           generate_articles ;;
    weekly-calendar)    weekly_calendar ;;
    publish-static)     publish_static "$@" ;;
    publish-wp)         publish_wordpress "$@" ;;
    monthly)            monthly_report ;;
    *)                  echo "Unknown command: $CMD" ;;
esac
