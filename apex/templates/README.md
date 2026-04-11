# axiom-apex Templates

Operational bash scripts that automate business workflows using the `apex` CLI ([axiom-apex on PyPI](https://pypi.org/project/axiom-apex/)).

Each template follows a consistent pattern: **parallel data ingestion → structured synthesis → executive brief → archive.**

## Installation

```bash
pip install axiom-apex
apex templates list
apex templates install <name>   # scaffolds config stubs + cron to cwd
```

Or clone directly:

```bash
git clone https://github.com/axiom-llc/axiom-apex
cd axiom-apex/apex/templates
```

## Templates

| Name | Category | Description | Revenue Tier |
|------|----------|-------------|-------------|
| [compliance-audit](compliance-audit.sh) | operations | SOC2/HIPAA/PCI-DSS/GDPR automated auditing | high |
| [cybersecurity](cybersecurity.sh) | operations | Threat intel, vuln scan, incident response | high |
| [revenue-monitor](revenue-monitor.sh) | financial | Micro-SaaS monitoring service with invoicing | high |
| [solo-agency](solo-agency.sh) | growth | Full consulting lifecycle: intake → invoice | high |
| [due-diligence](due-diligence.sh) | financial | M&A / investment diligence via parallel agents | high |
| [content-engine](content-engine.sh) | growth | Content marketing pipeline → publishing queue | high |
| [client-reporting](client-reporting.sh) | growth | Automated client-facing report generation | high |
| [deal-flow](deal-flow.sh) | financial | VC/angel inbound deal triage and scoring | high |
| [healthcare-rcm](healthcare-rcm.sh) | operations | Revenue cycle management automation | medium |
| [insurance-claims](insurance-claims.sh) | operations | Claims processing and adjudication | medium |
| [law-firm](law-firm.sh) | legal | Solo/small firm practice automation | medium |
| [msp](msp.sh) | operations | Managed service provider operations | medium |
| [recruiter](recruiter.sh) | growth | Parallel resume scoring and outreach | medium |
| [supply-chain](supply-chain.sh) | operations | Vendor risk monitoring and scoring | medium |
| [hedge-fund](hedge-fund.sh) | financial | Pre-market intelligence brief (reference impl) | medium |
| [opportunity-scanner](opportunity-scanner.sh) | growth | Weekly market research → scored opportunities | low |
| [venture-bootstrap](venture-bootstrap.sh) | growth | Opportunity → MVP spec → outreach assets | low |

Full metadata (config keys, cron schedules, commands) is in [`index.json`](index.json).

## Quick Start

### hedge-fund.sh (reference — simplest)

```bash
echo "AAPL,MSFT,NVDA,BTC-USD" > ~/.config/apex/watchlist
echo "macro,tech,energy"       > ~/.config/apex/sectors
./hedge-fund.sh
# Add to cron: 0 6 * * 1-5 /path/to/hedge-fund.sh
```

### revenue-monitor.sh (highest ROI)

```bash
# Edit SERVICE_NAME, YOUR_EMAIL, YOUR_NAME at top of script
./revenue-monitor.sh onboard "Acme Corp" acme.com 1.2.3.4 cto@acme.com 2 100
./revenue-monitor.sh pulse-all   # test
# Add all cron jobs from script header
```

### compliance-audit.sh

```bash
export ORG_NAME="Acme Corp"
export FRAMEWORKS="SOC2 HIPAA"
./compliance-audit.sh nightly
./compliance-audit.sh audit SOC2
```

### solo-agency.sh

```bash
echo "Axiom LLC"                              > ~/.config/apex/agency_name
echo "200"                                   > ~/.config/apex/agency_rate
echo "AI automation, systems integration"    > ~/.config/apex/agency_skills
./solo-agency.sh morning
echo "New project brief..." > /tmp/brief.txt
./solo-agency.sh intake /tmp/brief.txt
```

## Shared Library

Templates source [`lib/common.sh`](lib/common.sh) for:

- `date_add` / `date_yesterday` — GNU + BSD/macOS portability
- `safe_speak` / `safe_speak_file` / `safe_play` — espeak guard (no-ops on headless servers)
- `load_config` — structured key:value config loader
- `wait_pids` — parallel job waiter with failure reporting
- `slugify`, `require_file`, `require_dir`, `require_cmd`, `log`

## Config Reference

All templates read config from `~/.config/apex/`. Shared keys:

| File | Used by | Description |
|------|---------|-------------|
| `~/.config/apex/watchlist` | hedge-fund | Comma-separated tickers |
| `~/.config/apex/sectors` | hedge-fund | Comma-separated sectors |
| `~/.config/apex/sec_assets` | cybersecurity | One IP/domain per line |
| `~/.config/apex/vendors` | supply-chain | One vendor per line |
| `~/.config/apex/agency_name` | solo-agency, client-reporting | Agency/firm trading name |
| `~/.config/apex/agency_rate` | solo-agency | Default hourly rate |
| `~/.config/apex/agency_skills` | solo-agency | Comma-separated service lines |
| `~/.config/apex/fund_name` | deal-flow | Fund name |
| `~/.config/apex/fund_thesis` | deal-flow | Investment thesis (plain text) |
| `~/.config/apex/content_brand` | content-engine | Brand name |
| `~/.config/apex/content_topics` | content-engine | Comma-separated topic clusters |

## Adding a Template

1. Follow the 6-phase pattern: ingest → analyze → synthesize → brief → log → archive
2. Source `lib/common.sh`
3. Add `set -euo pipefail`
4. Add an entry to `index.json`
5. Add a cron schedule comment block in the header

## License

MIT — see [LICENSE](../LICENSE).

---

*Templates require [axiom-apex](https://pypi.org/project/axiom-apex/) >= 0.1.0. Built by [Axiom LLC](https://github.com/axiom-llc).*
