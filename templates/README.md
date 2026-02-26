# templates/

Turnkey APEX automation scripts for common business verticals. Each template provides a complete cron-scheduled workflow: morning briefs, end-of-day summaries, inventory/compliance checks, and narrated audio reports.

> **Status:** Functional templates — review configuration variables before deployment. Test each command individually before enabling cron.

## Templates

| File | Vertical |
|---|---|
| `apex-template-retail.sh` | Retail / point-of-sale |
| `apex-template-ecom.sh` | E-commerce |
| `apex-template-medical.sh` | Medical practice |
| `apex-template-lawfirm.sh` | Law firm |
| `apex-template-agency.sh` | Marketing / creative agency |
| `apex-template-restaurant.sh` | Restaurant |
| `apex-template-fitness.sh` | Gym / fitness studio |
| `apex-template-realestate.sh` | Real estate |
| `apex-template-msp.sh` | Managed service provider |
| `apex-template-morning_automation.sh` | Generic morning brief |
| `apex-revenue-content.sh` | Content-driven revenue workflows |
| `apex-revenue-monitor.sh` | Revenue monitoring and alerting |
| `apex-revenue-proposals.sh` | Automated proposal generation |

## Setup (per template)

1. Open the script and set the configuration variables at the top (`BUSINESS`, `CITY`, `THRESHOLD`, etc.)
2. Create the expected directory structure (each script runs `mkdir -p` on first execution)
3. Test each subcommand manually before enabling cron
4. Add cron entries from the schedule block at the top of the script

## Common Subcommands

Most templates follow this pattern:

```bash
./apex-template-retail.sh brief       # morning brief
./apex-template-retail.sh eod         # end-of-day summary
./apex-template-retail.sh inventory   # stock/resource check
./apex-template-retail.sh weekly      # weekly review
./apex-template-retail.sh monthly     # monthly report
```

## Requirements

- APEX installed and on `$PATH`
- `GEMINI_API_KEY` set in environment
- `espeak` for audio narration (optional — remove audio steps if not needed)
- Vertical-specific: POS CSV export, EHR export, etc. (documented per template)
