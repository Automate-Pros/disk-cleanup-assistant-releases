---
name: disk-cleanup
description: Use when the user asks why a Windows drive is full, what is using disk space, how much space is free, or wants to free up space.
---

# Disk cleanup

Use the `dca` MCP tools. Their sizes come from a scan of the drive; never guess a size, a path or what a folder holds. Sizes are space on disk, given in bytes. Report them as Windows Explorer does, so they match what the user sees: 1 GB is 1,073,741,824 bytes and 1 TB is 1,024 GB. A scan sees sizes, not settings or history: when asked why something is that size (how the page file was configured, when an app last cleaned up), say the scan cannot tell rather than giving a likely cause as fact.

Steps 1 to 7 only read. Files change only through a plan (steps 8 to 10): `create_plan` checks each proposed change and returns a dry run, and `execute_plan` runs it only after the user approves it in their own client. Run a plan only after the user says yes in the chat to that dry run; never call `execute_plan` on your own judgment. The tools refuse protected and unsafe items (Windows, Program Files, a profile as a whole, OneDrive and other sync folders, links, files that changed): never work around a refusal by asking for the same thing another way, such as a parent folder or the files one by one; tell the user why it was refused.

## Steps

1. **Find the drive.** Call `list_volumes`. Lead with the fullest drive, in plain words: "C: has 21 GB free of 931 GB (2%)". If the user named a drive, use it.

2. **Scan it.** Call `scan_volume` with the drive, then `get_scan_status` every few seconds until `state` is `done` or `failed`.
   - Before scanning, tell the user Windows may show one administrator prompt. Approving it reads the drive's file table: about 15 seconds for a full 1 TB drive. Declining walks the folders instead, which takes several minutes and can't see into protected folders. The summary's `fallback_reason` says when that happened; pass it on.
   - A scan from earlier is kept. If `get_overview` already works and its `summary.scanned_at` is under a day old, use it and offer to rescan rather than scanning again.

3. **Get the overview.** Call `get_overview`. From it, tell the user:
   - the 3 to 5 largest entries at the top of the drive, with sizes and shares;
   - notable kinds of file in `by_extension`, such as video, disk images (`vhdx`, `iso`), archives or installers;
   - how much space has not been written to in over a year (`by_age`).

4. **Check for known junk.** Call `find_known_junk`. Its rules come from a tested catalog, so trust its findings over guesses. Its `allocated_bytes` is the space that could be got back; never add `never_delete_bytes` to it. A rule with an age or type filter counts only what passes it: its `left_out_bytes` is the rest of the space in those places, such as Temp files from the last week or photos in Downloads. That is the rule working, not a fault; when a folder is much larger than its rule's count, say so. Group the rules by `risk`:
   - `safe`: caches and temporary files that rebuild themselves, such as browser and package caches and Temp. Give each rule's action and its `regenerates` note.
   - `review`: the user's own things, such as old installers in Downloads and old app builds. They decide.
   - `caution`: removing these has a cost, such as rebuilding an idle project's `node_modules` or losing the way back to the previous Windows. Say what the cost is.
   - `never_delete`: WinSxS, the page file, the hibernation file, virtual disks. Explain them, and where the rule has a `task`, say the plan can run it to shrink them (component cleanup, compacting a WSL disk, turning hibernation off). Never count them as savings.

   A rule with a `task` is cleaned by Windows' own tools (Windows Temp, Windows Update downloads, Delivery Optimization, error reports, the previous Windows, the Recycle Bin): the plan runs that task as a `system_task` step. Most tasks run as administrator, so Windows asks the user to approve each one.

5. **Look for duplicates** when large media, disk images or archives fill the drive, or the user asks. Follow the `find-duplicates` skill, which calls `find_duplicates`.

   **Look for folders to move** when another fixed drive has room, or the user would rather move than delete. Follow the `relocate-folder` skill, which starts with `find_relocation_candidates` and ends with `finish_plan` once the programs work from the new place.

6. **Look closer where the space is.** Call `browse` on the largest folders, going down a level or two, until each large share is accounted for by something you can name. For a folder you can't name from its path, follow the `explain-folder` skill, which starts with `inspect_path`. Use `query_files` for questions such as "the largest files in Downloads", "videos over 1 GB" or "files untouched for 3 years".

7. **Answer.** Give a short ranked list, each line with size, share and what it is, for example "Users\mark\Videos: 210 GB (23%), your video library". Then:
   - separate what the user owns (documents, media, downloads, projects) from what Windows and apps keep;
   - say how much the known junk adds up to, by risk, and which rules hold the most;
   - say which large items are normal and managed by Windows, and which would be worth the user's review later;
   - say when the scan ran and how, from the summary.

8. **Propose a plan, if the user wants space back.** Ask how much they need and what they value (projects, photos, games), then pick from the findings, safest first. Recycle by default: it can be undone. Use `delete` only for caches and temporary files the junk catalog marks `safe` (the tool refuses anything else), `tool_clean` for a cache whose rule has a `clean_command`, and `system_task` for a place whose rule has a `task` (give the place's path exactly as `find_known_junk` lists it). A `never_delete` item goes in a plan only as its rule's `system_task`, and only when the user asks for it by name. Emptying the Recycle Bin always runs last, and after it nothing recycled can be put back: say so, and include it only if the user agrees. Never put anything the user has not agreed to in a plan. Call `create_plan` with the drive and the items (full paths and actions).

   Every change goes through a plan, so the dry run lists everything that will happen. Never give the user commands or scripts to run by hand. If something they want has no step type, say the tool can't do it yet.

9. **Show the dry run and ask.** From the report, list each step with its size and action, the totals (`recycle_bytes` is freed only once the Recycle Bin is emptied; `delete_bytes` is freed at once and cannot be undone; `task_bytes` is what Windows' own tasks clean, each marked when it runs as administrator), and every refused item with its reason. Ask the user whether to run it. Only after the user says yes, call `execute_plan` with the `plan_id`; their client then asks them to approve it once more. If they decline, nothing changes: say so and stop.

   If `execute_plan` cannot run at all, for example because the client's permission mode blocks it, the plan is still the whole job. Give the user one command to run in their own terminal, `dca run <plan id>`, using the full path of the plugin's `dca.exe`. It shows the same plan and asks them to type yes. Never replace the plan with commands or scripts of your own.

10. **Report what happened.** From `execute_plan`, say what was done, skipped and why (in use, changed since the scan, too large for the Recycle Bin), and the space recycled and deleted, and for each Windows task what it freed (its note) or why it was skipped (the administrator prompt was declined). Tell them recycled items stay in the Recycle Bin until it is emptied (a later plan's `system_task` for `$Recycle.Bin` can do that), and that until then `undo_plan` puts them back. `list_journal` shows past plans; a plan with started steps was interrupted, and running it again finishes it.

## Things that are normal and large

- `pagefile.sys` and `swapfile.sys`: virtual memory. Windows sizes it automatically unless it was set by hand, and the scan cannot tell which; changing it is a setting, not a cleanup.
- `hiberfil.sys`: the saved memory for hibernation and fast startup.
- `Windows\WinSxS`: the component store. It looks larger than it is, because many of its files are hard links shared with `Windows\System32`.
- `System Volume Information`: restore points and shadow copies.
- `$MFT`, `$Extend` and other `$` names at the top of the drive: the file system's own records.
- A file shown as a hard link holds no space of its own; it is counted under its first name.
- A cloud placeholder (OneDrive Files On-Demand) takes almost no local space even when its size is large.
