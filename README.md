# REVS SS TOOL

A friendly Minecraft screenshare toolkit for Windows. One window, plain English, no jargon.

REVS SS TOOL is open source under the MIT license. The public build keeps the main PowerShell source readable so server staff and contributors can audit what runs on a checked PC.

## Features

- **Live search** - type `usb`, `macro`, `jar`, `alt`, `deleted` and the tool list filters as you go.
- **Built-in scanners** - registry search, process `.jar` scan, injected mod finder, and a full PC check summary.
- **One-click tool launcher** - forensic and screenshare tools are downloaded from their official pages and opened for you.
- **Cleanup on close** - launched processes are stopped where possible and downloaded files are wiped from the tool folder.
- **Optional reporting** - click and scan summaries can be sent to your own Discord webhook or relay when configured, and can be turned off from the app.

## Run it

Open **Windows PowerShell** and paste:

```powershell
powershell -ExecutionPolicy Bypass -Command "irm https://github.com/theprodogy/revs-ss-tool/raw/refs/heads/main/run.ps1 | iex"
```

That downloads the tool and relaunches it as **admin** when needed for deeper process and registry checks.

## Run from source

Clone or download the repo, then run:

```powershell
powershell -ExecutionPolicy Bypass -STA -File .\REVS-SS-TOOL.ps1
```

Windows PowerShell is required because the UI uses WPF.

## Privacy and reporting

Reporting is disabled by default. To enable it for your own server, set one of these environment variables before launching:

```powershell
$env:SS_WEBHOOK_URL = "https://discord.com/api/webhooks/xxxx/yyyy"
$env:SS_WEBHOOK_URLS = "https://discord.com/api/webhooks/one,https://discord.com/api/webhooks/two"
$env:SS_RELAY_URL = "https://your-worker.your-account.workers.dev"
$env:SS_RELAY_KEY = "optional-shared-key"
```

When reporting is enabled, REVS sends clicked tool names and scan summaries. It does not read passwords, browser tokens, or personal file contents for reporting.

You can turn reporting off at any time with the **Reporting** checkbox in the app footer. To force reporting off before launch, set either:

```powershell
$env:SS_REPORTING = "off"
$env:SS_REPORTING_DISABLED = "1"
```

## External tools

REVS links to third-party utilities maintained by their own authors. Each tool is governed by its own license and terms. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Publish a public copy

To generate a GitHub-ready copy:

```powershell
.\Build-GitHubRepo.ps1 -Owner YOUR_GITHUB_NAME -Repo revs-ss-tool
```

The output goes to `dist/github`.

If you have the GitHub CLI authenticated, `publish.ps1` can create or update a public GitHub repository for you. Review the generated `dist/github` folder before publishing.

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md) before opening issues or pull requests.

## License

MIT - see [LICENSE](LICENSE).
