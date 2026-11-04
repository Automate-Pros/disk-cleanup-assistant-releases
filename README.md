# Disk Cleanup Assistant

A Claude Code plugin that finds what is using disk space on Windows and cleans it up safely: it reads the drive's master file table, explains what is large and why, finds known junk and duplicates, and carries out only the cleanup you approve, with undo.

This repository holds the release builds of `dca.exe` and the desktop app `dca-app.exe`, and the plugin marketplace. The workflow that publishes each release writes everything here; don't edit it by hand.

## Install

In Claude Code on Windows:

```
/plugin marketplace add Automate-Pros/disk-cleanup-assistant-releases
/plugin install disk-cleanup-assistant@disk-cleanup-assistant
```

On first use, the plugin downloads the `dca.exe` of the release that `plugin/release.json` pins, checks its SHA-256 and refuses any file that differs.

Scans read the master file table, which needs administrator rights, so each scan asks once through a UAC prompt. To scan without prompts, and to make rescans take seconds, install the scan service once, from a terminal opened as administrator:

```
$dca = Get-ChildItem "$env:USERPROFILE\.claude\plugins\cache\disk-cleanup-assistant\disk-cleanup-assistant\*\bin\dca.exe" | Sort-Object LastWriteTime | Select-Object -Last 1
& $dca service install
```

The service only reads: it scans drives for the user signed in at the screen and never changes a file. `dca service uninstall` removes it.

## Update

In a terminal (not inside a Claude Code session), then restart Claude Code:

```
claude plugin marketplace update disk-cleanup-assistant
claude plugin update disk-cleanup-assistant@disk-cleanup-assistant
```

Or in Claude Code, open `/plugin`, choose **Installed**, then **disk-cleanup-assistant**, then **Update now**. There is no update command to type in a session: `/plugin` followed by anything but install, uninstall, enable, disable or marketplace just opens that menu. If you installed the scan service, run its install command again afterwards so the service runs the new build.
