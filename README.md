# deploy_agent – Student Attendance Tracker bootstrapper

`deploy_agent.sh` deploys, runs and archives logs for the Python Student Attendance Tracker. `attendance_checker.py` is never modified.

## Setup
Put the three unmodified source files in `templates/`: `attendance_checker.py`, `assets.csv`, `config.json`. Requires `python3` and `zip`.

```bash
chmod +x deploy_agent.sh
```

## Choosing a feature
Interactive menu (no arguments) or flags:

| Command | Feature |
|---|---|
| `./deploy_agent.sh` | menu: 1 Deploy, 2 Run, 3 Archive, 4 Quit |
| `./deploy_agent.sh -d` / `--deploy` | Feature 1 |
| `./deploy_agent.sh -r [name]` / `--run` | Feature 2 |
| `./deploy_agent.sh -a [name]` / `--archive` | Feature 3 |

`name` is the part after `attendance_tracker_`; if omitted you are prompted.

## Feature 1 – Deploy
1. Pre-flight: checks `python3`, `zip` and the template files; exits with a clear message if missing.
2. Asks for a name and creates `attendance_tracker_<name>/` with `attendance_checker.py`, `Helpers/{assets.csv,config.json}` and an empty `reports/`. If the directory exists you choose overwrite or abort.
3. Roster: **A** copies N rows (+ header) from `templates/assets.csv`; **B** generates N fresh students from name arrays in the script with counts at 0 (beyond the arrays it uses `Student N`).
4. `total_sessions` consistency (fixed with `sed`, no prompt): Option A rows carry 4 prior sessions, so `total_sessions` = 5; Option B starts fresh, so `total_sessions` = 1. It must always be prior sessions + 1.
5. Permissions: `chmod +x attendance_checker.py`, `chmod 600 Helpers/config.json`; shown with `ls -l`.
6. Thresholds: if you answer `y`, you enter warning (default 75) and failure (default 50). Values must be 0–100 with failure < warning. Only the `"warning": N` and `"failure": N` lines are edited in place with `sed`; formatting and order are untouched.
7. Verification: deploy finishes by launching Feature 2, so a successful startup proves structure, roster and config work together.

## Feature 2 – Run
`cd attendance_tracker_<name> && python3 attendance_checker.py` (in a subshell). Interactive marking session.

## Feature 3 – Archive logs
After a run, copies each existing log into its own directory with a timestamp:
```
attendance_tracker_<name>/archives/attendance/attendance_YYYYMMDD_HHMMSS.log
attendance_tracker_<name>/archives/absent/absent_YYYYMMDD_HHMMSS.log
```
Missing logs (e.g. nobody absent) are reported as skipped; the script does not crash. Originals stay in `reports/`.

## Signal handling (Ctrl+C / Ctrl+Z)
`SIGINT` and `SIGTSTP` are trapped from the moment project creation starts until setup finishes (the trap is removed before the marking session). On either signal the script prints an interruption message, zips whatever exists into `attendance_tracker_<name>_archive.zip` (next to the script), removes the half-built directory and exits cleanly (status 130).

**Test it:** run `./deploy_agent.sh -d`, enter a name, then press Ctrl+C or Ctrl+Z at any prompt (e.g. the roster choice). Check with `ls` and `unzip -l attendance_tracker_<name>_archive.zip`; the zip holds the partial tree (e.g. `attendance_checker.py`, `Helpers/config.json`, `reports/`). Interrupting at the name prompt creates nothing, so nothing is zipped.

## How I tested
- Deployed with options A and B; checked `Helpers/assets.csv` rows and `total_sessions` (5 / 1).
- Verified `ls -l` shows `-rwxr-xr-x` for the script and `-rw-------` for `config.json`.
- Updated thresholds and diffed `config.json`: only those two numbers changed.
- Existing-directory path (abort and overwrite), empty name, invalid input.
- Archive with and without `absent.log`.
- Sent real SIGINT and SIGTSTP mid-deploy and inspected the zip.
