# Tests

No automated test suite. APEX is validated through integration runs.

## Validated Commands
```bash
# System / file operations
apex "write current logged in user and hostname to ~/sysinfo.txt"
apex "get current date time hostname kernel version and uptime and write all to ~/full-sysinfo.txt"
apex "write top 5 running processes by cpu to ~/procs.txt"
apex "get disk usage for all mounted filesystems and write to ~/disk-full.txt"
apex "write a glossary of 100 linux terminal commands with descriptions to ~/linux-glossary.txt"
apex "write detailed biographies of all 8 planets in our solar system each to their own file in ~/planets/"

# HTTP
apex "fetch https://api.github.com/repos/torvalds/linux using curl save to ~/linux-repo.json"
apex "fetch https://wttr.in/New_York using curl save to ~/ny-weather.txt"

# Memory
apex "save current git branch to memory as active_branch"
apex "read from memory the active_branch value"

# Audio pipeline (requires espeak + aplay)
apex "write a detailed report on the planet Mars to ~/mars-report.txt then use espeak with speed 130 to read it aloud"
apex "write bad-ass gangster hip hop lyrics about the terminal to ~/terminal-hip_hop.txt then use espeak with pitch 40 and speed 165 to read it aloud and save to ~/terminal-hip_hop.wav"
```

## Known Limitations

- `http_get` does not work on JS-rendered pages (React/Vue/SPAs)
- DuckDuckGo API returns empty body under load — avoid
- Wikipedia HTML pages return 403 without user-agent — use REST API endpoints instead
- Replace spaces with `+` in all URLs
