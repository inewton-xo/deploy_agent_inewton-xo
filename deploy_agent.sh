#!/usr/bin/env bash
# deploy_agent.sh - bootstrap, run and archive the Student Attendance Tracker.
# Usage: ./deploy_agent.sh            (interactive menu)
#        ./deploy_agent.sh -d | --deploy
#        ./deploy_agent.sh -r | --run     [name]
#        ./deploy_agent.sh -a | --archive [name]
#        ./deploy_agent.sh -h | --help

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES="$SCRIPT_DIR/templates"
cd "$SCRIPT_DIR" || exit 1

DEPLOY_DIR=""     # set once Feature 1 starts creating files (used by the signal trap)

# ---------- helpers ----------
die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "[*] $*"; }

# Ask for the project name and echo it back via the global PROJECT_NAME.
ask_name() {
    local given="$1"
    if [[ -n "$given" ]]; then PROJECT_NAME="$given"
    else read -r -p "Project name (creates attendance_tracker_<name>): " PROJECT_NAME
    fi
    [[ -n "$PROJECT_NAME" ]] || die "Project name cannot be empty."
    [[ "$PROJECT_NAME" =~ ^[A-Za-z0-9_-]+$ ]] || die "Use only letters, digits, '_' or '-' in the name."
}

# ---------- signal handling (Feature 1 only) ----------
on_interrupt() {
    trap '' INT TSTP            # ignore repeats while we clean up
    echo
    echo "!! Deployment interrupted by the user (Ctrl+C / Ctrl+Z)."
    if [[ -n "$DEPLOY_DIR" && -d "$SCRIPT_DIR/$DEPLOY_DIR" ]]; then
        local zipfile="${DEPLOY_DIR}_archive.zip"
        echo "!! Archiving the incomplete project into $zipfile ..."
        if zip -rq "$zipfile" "$DEPLOY_DIR"; then
            rm -rf "$SCRIPT_DIR/$DEPLOY_DIR"
            echo "!! Archive created: $SCRIPT_DIR/$zipfile"
            echo "!! Incomplete directory removed."
        else
            echo "!! Could not create the zip; leaving $DEPLOY_DIR in place." >&2
        fi
    else
        echo "!! Nothing had been created yet - nothing to archive."
    fi
    echo "!! Session closed cleanly."
    exit 130
}

# ---------- Feature 2: run ----------
run_app() {
    local dir="$1"
    [[ -d "$dir" ]] || die "Project directory '$dir' not found. Deploy it first."
    [[ -f "$dir/attendance_checker.py" ]] || die "$dir/attendance_checker.py is missing."
    info "Starting the attendance checker in $dir ..."
    ( cd "$dir" && python3 attendance_checker.py )
}

# ---------- Feature 1: deploy ----------
deploy() {
    # Pre-flight checks
    local missing=0
    for cmd in python3 zip; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "ERROR: required command '$cmd' is not installed." >&2
            missing=1
        fi
    done
    (( missing )) && exit 1
    for f in attendance_checker.py assets.csv config.json; do
        [[ -f "$TEMPLATES/$f" ]] || die "templates/$f not found."
    done
    info "Pre-flight checks passed (python3, zip, templates)."

    # Name the project (before traps: nothing exists yet)
    ask_name ""
    local dir="attendance_tracker_${PROJECT_NAME}"

    if [[ -d "$dir" ]]; then
        read -r -p "Directory '$dir' already exists. Overwrite? [y/N]: " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            rm -rf "$dir" || die "Could not remove existing directory."
        else
            die "Aborted: '$dir' already exists and was not overwritten."
        fi
    fi

    # From here on, Ctrl+C / Ctrl+Z archive the partial project.
    DEPLOY_DIR="$dir"
    trap on_interrupt INT TSTP

    mkdir -p "$dir/Helpers" "$dir/reports" || die "Could not create directories."
    cp "$TEMPLATES/attendance_checker.py" "$dir/attendance_checker.py"
    cp "$TEMPLATES/config.json" "$dir/Helpers/config.json"
    info "Created structure and copied attendance_checker.py and config.json."

    # Roster
    echo "How should the roster (Helpers/assets.csv) be built?"
    echo "  A) Copy rows from templates/assets.csv (4 prior sessions each)"
    echo "  B) Generate a fresh roster (counts start at 0)"
    local choice n
    while true; do
        read -r -p "Choose A or B: " choice
        [[ "$choice" =~ ^[AaBb]$ ]] && break
        echo "Please type A or B."
    done

    while true; do
        read -r -p "How many students? " n
        [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 )) && break
        echo "Enter a whole number of at least 1."
    done

    if [[ "$choice" =~ ^[Aa]$ ]]; then
        local available=$(( $(wc -l < "$TEMPLATES/assets.csv") - 1 ))
        if (( n > available )); then
            echo "Template only has $available students; copying $available."
            n=$available
        fi
        head -n $(( n + 1 )) "$TEMPLATES/assets.csv" > "$dir/Helpers/assets.csv"
        sed -i.bak -E 's/("total_sessions"[[:space:]]*:[[:space:]]*)[0-9]+/\15/' "$dir/Helpers/config.json"
    else
        local first=(Alice Bob Carol David Emma Frank Grace Henry Irene James Karen Liam Mia Noah Olivia Peter Quinn Rachel Samuel Tina)
        local last=(Johnson Smith Williams Brown Jones Garcia Miller Davis Wilson Moore Taylor Anderson Thomas Jackson White Harris Martin Lee Clark Lewis)
        {
            echo "Email,Names,Attendance Count,Absence Count"
            local i fn ln email name
            for (( i=0; i<n; i++ )); do
                if (( i < ${#first[@]} )); then
                    fn="${first[i]}"; ln="${last[i]}"
                else
                    fn="Student"; ln="$(( i + 1 ))"
                fi
                email="$(echo "${fn}.${ln}" | tr '[:upper:]' '[:lower:]')@example.com"
                name="$fn $ln"
                echo "$email,$name,0,0"
            done
        } > "$dir/Helpers/assets.csv"
        sed -i.bak -E 's/("total_sessions"[[:space:]]*:[[:space:]]*)[0-9]+/\11/' "$dir/Helpers/config.json"
    fi
    rm -f "$dir/Helpers/config.json.bak"
    info "Roster written with $n student(s)."

    # Permissions
    chmod +x "$dir/attendance_checker.py"
    chmod 600 "$dir/Helpers/config.json"
    echo "Permissions set:"
    ls -l "$dir/attendance_checker.py" "$dir/Helpers/config.json"

    # Optional threshold update
    read -r -p "Update the attendance alert thresholds? [y/N]: " upd
    if [[ "$upd" =~ ^[Yy]$ ]]; then
        local w f
        while true; do
            read -r -p "Warning threshold % [75]: " w; w="${w:-75}"
            read -r -p "Failure threshold % [50]: " f; f="${f:-50}"
            if [[ "$w" =~ ^[0-9]+$ && "$f" =~ ^[0-9]+$ ]] && (( w <= 100 && f <= 100 && f < w )); then
                break
            fi
            echo "Both must be whole numbers 0-100, and failure must be lower than warning."
        done
        sed -i.bak -E \
            -e "s/(\"warning\"[[:space:]]*:[[:space:]]*)[0-9]+/\1${w}/" \
            -e "s/(\"failure\"[[:space:]]*:[[:space:]]*)[0-9]+/\1${f}/" \
            "$dir/Helpers/config.json"
        rm -f "$dir/Helpers/config.json.bak"
        chmod 600 "$dir/Helpers/config.json"
        info "Thresholds updated: warning=$w failure=$f"
    fi

    # Setup finished: release the trap (it must not apply to the marking session)
    trap - INT TSTP
    DEPLOY_DIR=""
    info "Deployment complete. Verifying by running the application..."
    run_app "$dir"
}

# ---------- Feature 3: archive ----------
archive_logs() {
    ask_name "$1"
    local dir="attendance_tracker_${PROJECT_NAME}"
    [[ -d "$dir" ]] || die "Project directory '$dir' not found."

    local ts; ts="$(date +%Y%m%d_%H%M%S)"
    local archived=0 name
    for name in attendance absent; do
        local src="$dir/reports/${name}.log"
        local dest_dir="$dir/archives/${name}"
        local dest="$dest_dir/${name}_${ts}.log"
        if [[ -f "$src" ]]; then
            mkdir -p "$dest_dir" && cp "$src" "$dest" \
                && { echo "Archived: $src -> $dest"; archived=$((archived+1)); } \
                || echo "Failed to archive $src" >&2
        else
            echo "Skipped: $src does not exist (nothing to archive)."
        fi
    done
    echo "$archived log file(s) archived."
}

usage() {
    cat << USAGE
Usage: $0 [option]
  (no option)        interactive menu
  -d, --deploy       deploy a new project
  -r, --run [name]   run the app in attendance_tracker_<name>
  -a, --archive [name]  archive that project's logs
  -h, --help         show this help
USAGE
}

menu() {
    echo "==== Attendance Tracker Deploy Agent ===="
    echo "1) Deploy the application"
    echo "2) Run the application"
    echo "3) Archive the log files"
    echo "4) Quit"
    read -r -p "Select [1-4]: " sel
    case "$sel" in
        1) deploy ;;
        2) ask_name ""; run_app "attendance_tracker_${PROJECT_NAME}" ;;
        3) archive_logs "" ;;
        4) exit 0 ;;
        *) die "Invalid selection." ;;
    esac
}

case "$1" in
    "")            menu ;;
    -d|--deploy)   deploy ;;
    -r|--run)      ask_name "$2"; run_app "attendance_tracker_${PROJECT_NAME}" ;;
    -a|--archive)  archive_logs "$2" ;;
    -h|--help)     usage ;;
    *)             usage; exit 1 ;;
esac
