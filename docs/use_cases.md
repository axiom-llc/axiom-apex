# APEX Core Use Cases

## Communication

**Auto-respond to meeting requests with availability**
- Parse incoming email for meeting request keywords and proposed times
- Query calendar for conflicts at proposed times
- Reply with "confirmed" if available or list 3 alternative slots if not
- Create calendar event upon confirmation

**Generate email digests by category**
- Query inbox for unread emails from last 24 hours
- Group by sender domain (team@company.com → Internal, alerts@service.com → Notifications)
- Write summary document to Drive with subject lines and sender counts per category
- Mark emails as read after digest creation

**Archive and organize email attachments**
- Scan inbox for emails with attachments received today
- Download each attachment to /tmp
- Upload to Drive folder structure: /Attachments/{sender_domain}/{YYYY-MM-DD}/filename
- Store mapping of email_id → drive_file_id in memory for retrieval

**Send meeting summaries to attendees**
- Wait for calendar event end time + 5 minutes
- Search Drive for document matching event title
- Extract action items (lines starting with "TODO:" or "ACTION:")
- Email attendees with bulleted action items and Drive link

**Auto-unsubscribe from promotional emails**
- Search inbox for emails containing "unsubscribe" link in footer
- Filter to senders with 5+ messages in last 30 days
- Extract unsubscribe URL via regex
- Execute HTTP GET on unsubscribe link
- Create filter to auto-archive future emails from that sender

## Scheduling

**Block focus time in calendar gaps**
- Query calendar for next 5 business days
- Identify gaps ≥2 hours between meetings
- Create "Focus Block" events in those gaps with busy status
- Decline meeting invitations that overlap focus blocks

**Add travel buffers between meetings**
- Detect new calendar event with location field populated
- Calculate distance to previous/next meeting location via Maps API
- Insert 15min buffer before event if distance >2 miles
- Insert 10min buffer after event if next meeting exists
- Mark buffer blocks as "Traveling to {event_name}"

**Generate pre-meeting briefings**
- T-30 minutes before calendar event, extract attendee email addresses
- Search email for threads containing any attendee in last 14 days
- Search Drive for files modified by attendees in last 7 days
- Write briefing doc: attendee names, relevant email subjects, recent file links
- Save to Drive and open in browser

**Flag low-value recurring meetings**
- Query calendar for recurring events
- For each recurring event, count instances in last 60 days
- Check if accepted/declined ratio <50%
- Calculate total hours spent (instances × duration)
- Email list of meetings with <50% acceptance and total hours wasted

**Sync tasks to calendar**
- Query memory for stored tasks with due_date field
- For each task due within 7 days, check if calendar event exists
- Create calendar event on due_date at 9am if missing
- Include task description in event body
- Update memory with task_id → calendar_event_id mapping

## Document Management

**Consolidate duplicate file versions**
- Search Drive for files matching pattern: "{name} (1)", "{name} - Copy", "{name}_final_v2"
- Group files by base name (strip version suffixes)
- For each group, compare file modified dates
- Move older versions to /Archive/{YYYY-MM} folder
- Rename newest version to clean base name

**Search across Drive/Email/Memory**
- Accept search query string
- Execute Drive search for filename and content matches
- Execute Gmail search for subject and body matches
- Query memory database WHERE value LIKE '%query%'
- Combine results with source labels (Drive/Email/Memory)
- Write results to markdown file with clickable links

**Auto-file documents by type**
- Monitor Drive root folder for new files
- Classify by extension: .pdf→Documents, .jpg→Images, .xlsx→Spreadsheets
- If email attachment, classify by sender domain: invoices@vendor.com→Finance
- Move file to /Auto-Filed/{category}/{YYYY-MM}/
- Log file_id, original_path, new_path, classification_reason to memory

**Detect outdated documentation vs code**
- Parse git log for files changed in last 7 days
- Extract module/function names from changed files
- Search Drive for markdown/wiki files containing those names
- Compare file modified_date with git commit date
- Flag docs where modified_date < commit_date
- Write list of stale docs with git commit messages that caused staleness

**Extract contract renewal dates**
- Search Drive for files containing "contract" or "agreement" in name
- Download PDFs and extract text
- Regex search for date patterns near keywords: "expires", "renews", "term end"
- Store in memory: {contract_name: renewal_date}
- Create calendar reminders 60 and 30 days before renewal_date
- Email stakeholders with contract details at reminder time

## Project Coordination

**Generate daily standup reports**
- Query git for commits by user since yesterday 9am
- Extract commit messages and changed file counts
- Query calendar for today's events
- Query inbox for unread emails flagged as action items
- Write report: "Yesterday: {commits}, Today: {meetings}, Blockers: {flagged_emails}"
- Save to Drive and send to team channel

**Monitor milestone progress and alert on risks**
- Store project milestones in memory: {name, due_date, completion_criteria}
- Query completion criteria daily (e.g., "PR #123 merged", "deployment to prod successful")
- Calculate days_until_due for incomplete milestones
- If days_until_due <7 and incomplete, send email alert with specific criteria still pending
- Update memory with completion_status and last_check_date

**Send code review reminders for stale PRs**
- Query GitHub API for open PRs in specified repos
- Filter PRs where created_at > 48 hours ago AND review_count = 0
- Extract requested_reviewers list
- Query calendar for each reviewer's availability today
- Email reviewers: "PR #{number} waiting {hours} hours, you have {calendar_gaps} available"
- Log reminder_sent_date to memory to avoid duplicate reminders

**Collect sprint metrics for retrospectives**
- Query git for commits during sprint dates
- Count: total_commits, commits_per_day, lines_added, lines_deleted
- Query calendar for meetings during sprint, sum total_meeting_hours
- Query email for threads tagged with sprint_id, count threads and replies
- Calculate: commit_velocity, meeting_overhead_percentage, communication_density
- Write retrospective data to spreadsheet with trend graphs vs previous sprints

**Schedule tasks when dependencies complete**
- Store task dependency graph in memory: {task_id: [dependent_task_ids]}
- Monitor for task completion events (manual command or automated trigger)
- When task completes, query memory for tasks dependent on it
- Check if all dependencies for dependent tasks are now complete
- For unblocked tasks, create calendar event at next available focus block
- Email assignee with task details and scheduled time

## Compliance & Security

**Audit Drive sharing permissions**
- Query Drive API for all files with sharing settings != "private"
- Group by permission type: anyone_with_link, specific_people, public
- Compare against policy rules in memory (e.g., "no public sharing of {folder_pattern}")
- Generate violation report: file_name, current_permission, owner, policy_violated
- Email report to compliance officer and file owners

**Scan for exposed credentials in files**
- Download text files and code files added to Drive in last 24 hours
- Regex scan for patterns: API_KEY=, password=, sk-{40 chars}, ghp_{40 chars}
- For matches, record: file_path, matched_string (redacted), line_number
- Move violating files to quarantine folder with restricted permissions
- Email security team with violation details and file links

**Enforce data retention policies**
- Query memory for retention policies: {file_pattern: retention_days}
- Search Drive for files matching pattern where created_date > retention_days
- For expired files, move to /Archive/{YYYY} with timestamp
- After 90 days in archive, permanently delete
- Log all retention actions to audit trail: file_id, action, date, policy_applied

**Collect audit evidence by requirement**
- Accept audit requirement ID (e.g., "SOC2-CC6.1")
- Query memory for evidence mappings: requirement → [file_patterns, email_searches, calendar_queries]
- Execute each query and collect matching items
- Create evidence folder in Drive: /Audit/{year}/{requirement_id}/
- Copy all evidence files to folder, generate index document with descriptions
- Email auditor with folder link and completion timestamp

**Monitor regulatory changes and create review tasks**
- Poll regulatory API endpoints daily for new publications matching keywords in memory
- Compare publication dates against last_check_date to identify new items
- Download regulatory text and extract effective_date
- Create calendar review task: {regulatory_id} scheduled 30 days before effective_date
- Email compliance team with summary and link to full text
- Store regulation metadata in memory for future reference

## Financial

**Extract and categorize expense receipts**
- Monitor inbox for emails from domains in memory: {expensify.com, receipts@vendor.com}
- Download PDF/image attachments
- OCR extract: date, vendor, amount, category keywords
- Upload to Drive: /Expenses/{YYYY}/{MM}/{vendor}_${amount}.pdf
- Append row to expense spreadsheet: date, vendor, amount, category, receipt_link
- Sum amounts by category and email monthly totals

**Send invoice payment reminders**
- Parse invoices in /Finance/Invoices for due_date field (OCR or filename pattern)
- Store in memory: {invoice_id, vendor, amount, due_date, payment_status}
- Query daily for invoices where due_date - today = 7 or 3 or 0 days
- Email AP team: "Invoice #{id} from {vendor} for ${amount} due {date}"
- Mark reminder_sent in memory to prevent duplicate emails

**Alert on budget variance**
- Query memory for budget allocations: {category: monthly_limit}
- Sum expenses by category from spreadsheet
- Calculate variance: actual - budget
- If variance >10% over budget, email department head with specifics: "{category} is ${amount} over budget ({percentage}%)"
- Include top 5 expenses contributing to overage with vendor and amount

**Aggregate contract payment schedules**
- Search Drive for contracts with payment terms
- Extract payment schedule tables: {date, amount, milestone}
- Sum all payments by month for next 12 months
- Write cash flow projection spreadsheet with running totals
- Create calendar events for payment due dates
- Email CFO monthly cash requirement summary

## Development

**Execute deployment checklists programmatically**
- Query memory for deployment checklist: [{step_id, command, expected_output}]
- Execute each command via shell in order
- Compare actual output against expected_output (regex match or exit code)
- If mismatch, halt deployment and email team with failed step details
- If all pass, write deployment log with timestamps and proceed to next phase
- Store deployment results in memory for rollback reference

**Create incident response documents and notify on-call**
- Receive alert webhook with severity and service details
- Create Drive doc from template: /Incidents/{YYYY-MM-DD-HH-MM}_{service}.md
- Write incident header: time, severity, affected_service, alert_details
- Query memory for on-call rotation, identify current engineer
- Email on-call with incident doc link and "Acknowledged? Y/N" subject
- Block on-call engineer's calendar for next 4 hours
- Store incident_id → doc_id in memory for status updates

**Schedule security patching based on CVE severity**
- Poll CVE database daily for new entries matching software in memory inventory
- Extract: CVE_id, affected_versions, severity_score, exploit_availability
- Compare against installed versions from package manifests
- If severity ≥7.0, create patch task: "Apply {CVE_id} to {system} by {72_hours_from_now}"
- Schedule calendar block in next maintenance window
- Email security team with CVE details and scheduled patch time

**Store and compare performance baselines**
- Execute performance test suite post-deployment
- Extract metrics: response_time_p50, response_time_p95, throughput_rps, error_rate
- Query memory for previous baseline metrics from last successful deployment
- Calculate deltas: current - baseline for each metric
- If any metric degrades >10%, email team with regression details and comparison graphs
- Store new metrics as baseline if all metrics improved or <5% degradation

## Personal Productivity

**Generate morning briefing document**
- Trigger at 7:00 AM daily
- Query inbox: unread_count, emails from VIPs in last 24h (names from memory)
- Query calendar: today's events with time, location, attendees
- Fetch weather: temperature, conditions, precipitation probability
- Fetch news: top 3 headlines from configured sources
- Query memory for pending tasks with priority=high
- Write briefing to Drive: /Briefings/{YYYY-MM-DD}.md with all sections
- Open briefing in browser automatically

**Retrieve task context when switching focus**
- Detect calendar event start via polling (current_time = event.start_time)
- Extract event title and search memory for context_id matching title keywords
- If context exists, fetch: relevant_files from Drive, related_emails, task_status
- Write context summary: "Working on: {task}, Files: {links}, Last status: {status_text}"
- Display in terminal or save to /tmp/current_context.md for quick reference

**Curate learning resources and schedule study time**
- Accept topic keyword (e.g., "rust async programming")
- Search arXiv, YouTube, GitHub repos via APIs for resources matching keyword
- Score by relevance: citations, stars, views, recency
- Select top 5 resources, store in memory: {topic: [resource_links]}
- Find 2-hour calendar gaps in next 7 days
- Create calendar events: "Study: {topic}" with resource links in description
- Email self with study plan and resource list

**Protect calendar from fragmentation**
- Analyze next 5 business days for meeting density
- Count meetings per day and gaps between meetings
- If day has >4 meetings OR gaps <60 minutes, mark as "fragmented"
- For fragmented days, decline optional meetings (no "required" attendee status)
- Email meeting organizers: "Declined {meeting} to preserve focus time on {date}"
- Block 2+ hour focus blocks on fragmented days with busy status
