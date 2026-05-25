#!/bin/zsh
# DBLook — Right-Click SQLite Inspector
# Right-click any .db/.sqlite/.sqlite3 file → inspect schema, data, indexes
# Usage: dblook.sh <mode> <file>
# Modes: inspect, clipboard, dump

set -uo pipefail
setopt TYPESET_SILENT 2>/dev/null

# ─── Config ───────────────────────────────────────────────────────────────────

APP_NAME="DBLook"
SUPPORT_DIR="$HOME/Library/Application Support/DBLook"
USAGE_FILE="$SUPPORT_DIR/usage"
DAILY_LIMIT=1
LICENSE_FILE="$SUPPORT_DIR/license"
LICENSE_KEY_FILE="$SUPPORT_DIR/license_key"
API_URL="https://dblook-worker.opera10r.workers.dev"
LOG_FILE="$SUPPORT_DIR/debug.log"
SAMPLE_ROWS=10
MAX_TABLES=200

# ─── Setup ────────────────────────────────────────────────────────────────────

mkdir -p "$SUPPORT_DIR"

# ─── Logging ──────────────────────────────────────────────────────────────────

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null
}

# ─── Notification ─────────────────────────────────────────────────────────────

notify() {
    local title="$1"
    local body="$2"
    body="${body//\\/\\\\}"
    body="${body//\"/\\\"}"
    osascript -e "display notification \"$body\" with title \"$title\"" 2>/dev/null &
}

# ─── Usage Tracking ──────────────────────────────────────────────────────────

check_usage() {
    if [[ -f "$LICENSE_FILE" ]] && [[ "$(cat "$LICENSE_FILE" 2>/dev/null)" == "active" ]]; then
        return 0
    fi

    local today
    today=$(date +%Y-%m-%d)

    if [[ -f "$USAGE_FILE" ]]; then
        local stored_date stored_count
        stored_date=$(cut -d: -f1 "$USAGE_FILE")
        stored_count=$(cut -d: -f2 "$USAGE_FILE")

        if [[ "$stored_date" == "$today" ]] && (( stored_count >= DAILY_LIMIT )); then
            notify "$APP_NAME" "Daily free inspection used. Unlimited for \$1/month."
            exit 0
        fi
    fi
}

increment_usage() {
    if [[ -f "$LICENSE_FILE" ]] && [[ "$(cat "$LICENSE_FILE" 2>/dev/null)" == "active" ]]; then
        return 0
    fi

    local today
    today=$(date +%Y-%m-%d)

    if [[ -f "$USAGE_FILE" ]]; then
        local stored_date stored_count
        stored_date=$(cut -d: -f1 "$USAGE_FILE")
        stored_count=$(cut -d: -f2 "$USAGE_FILE")

        if [[ "$stored_date" == "$today" ]]; then
            echo "$today:$((stored_count + 1))" > "$USAGE_FILE"
        else
            echo "$today:1" > "$USAGE_FILE"
        fi
    else
        echo "$today:1" > "$USAGE_FILE"
    fi
}

# ─── Validation ───────────────────────────────────────────────────────────────

validate_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        notify "$APP_NAME" "File not found: $(basename "$file")"
        log "ERROR: File not found: $file"
        exit 1
    fi

    # Check magic bytes - SQLite files start with "SQLite format 3"
    local header
    header=$(head -c 16 "$file" 2>/dev/null)
    if [[ "$header" != "SQLite format 3"* ]]; then
        notify "$APP_NAME" "Not a valid SQLite database."
        log "ERROR: Invalid SQLite header: $file"
        exit 1
    fi
}

# ─── Core Inspection Engine ───────────────────────────────────────────────────
# Uses printf to write directly to stdout — capture with $() from callers

inspect_database() {
    local db_path="$1"
    local include_data="${2:-true}"
    local total_rows=0
    local table_count=0

    local file_name file_size file_size_mb sqlite_ver encoding page_size
    file_name=$(basename "$db_path")
    file_size=$(stat -f%z "$db_path" 2>/dev/null || echo "0")
    file_size_mb=$(echo "scale=2; $file_size / 1048576" | bc 2>/dev/null || echo "0")
    sqlite_ver=$(sqlite3 "$db_path" "SELECT sqlite_version();" 2>/dev/null || echo "unknown")
    encoding=$(sqlite3 "$db_path" "PRAGMA encoding;" 2>/dev/null || echo "unknown")
    page_size=$(sqlite3 "$db_path" "PRAGMA page_size;" 2>/dev/null || echo "unknown")

    # Header
    printf '%s\n' "═══ DBLook: Database Inspection ═══"
    printf '%s\n' "File: $file_name"
    printf '%s\n' "Size: ${file_size_mb} MB"
    printf '%s\n' "SQLite Version: $sqlite_ver"
    printf '%s\n' "Encoding: $encoding"
    printf '%s\n' "Page Size: $page_size bytes"

    # Get tables
    local tables
    tables=$(sqlite3 "$db_path" "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name;" 2>/dev/null)

    if [[ -z "$tables" ]]; then
        printf '%s\n' "Tables: 0"
        printf '%s\n' "══════════════════════════════════════════════════"
        printf '%s\n' ""
        printf '%s\n' "No user tables found in this database."
        return
    fi

    table_count=$(echo "$tables" | wc -l | tr -d ' ')
    if (( table_count > MAX_TABLES )); then
        tables=$(echo "$tables" | head -n $MAX_TABLES)
    fi

    # Get total row count
    local tbl cnt
    while IFS= read -r tbl; do
        cnt=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM \"$tbl\";" 2>/dev/null || echo "0")
        total_rows=$((total_rows + cnt))
    done <<< "$tables"

    printf '%s\n' "Tables: $table_count | Total Rows: $(printf "%'d" $total_rows)"
    printf '%s\n' "══════════════════════════════════════════════════"

    # Inspect each table
    local row_count create_sql col_info col_count idx_list idx_count
    local unique_str idx_cols fk_list fk_count sample
    local cid cname ctype notnull dflt pk flags flag_str type_str
    local seq idx_name is_unique origin partial
    local id fk_seq fk_table from_col to_col on_update on_delete match_val line

    while IFS= read -r tbl; do
        row_count=$(sqlite3 "$db_path" "SELECT COUNT(*) FROM \"$tbl\";" 2>/dev/null || echo "0")
        create_sql=$(sqlite3 "$db_path" "SELECT sql FROM sqlite_master WHERE type='table' AND name='$tbl';" 2>/dev/null || echo "")

        printf '\n%s\n' "── Table: $tbl ($(printf "%'d" $row_count) rows) ──"

        # CREATE SQL
        if [[ -n "$create_sql" ]]; then
            printf '\n%s\n' '```sql'
            printf '%s\n' "$create_sql"
            printf '%s\n' '```'
        fi

        # Columns
        col_info=$(sqlite3 "$db_path" "PRAGMA table_info(\"$tbl\");" 2>/dev/null)
        if [[ -n "$col_info" ]]; then
            col_count=$(echo "$col_info" | wc -l | tr -d ' ')
            printf '\n%s\n' "Columns ($col_count):"
            while IFS='|' read -r cid cname ctype notnull dflt pk; do
                flags=""
                [[ "$pk" != "0" ]] && flags+="PK"
                [[ "$notnull" != "0" ]] && { [[ -n "$flags" ]] && flags+=", "; flags+="NOT NULL"; }
                [[ -n "$dflt" ]] && { [[ -n "$flags" ]] && flags+=", "; flags+="DEFAULT $dflt"; }
                flag_str=""
                [[ -n "$flags" ]] && flag_str=" [$flags]"
                type_str="${ctype:-ANY}"
                printf '%s\n' "  $cname $type_str$flag_str"
            done <<< "$col_info"
        fi

        # Indexes
        idx_list=$(sqlite3 "$db_path" "PRAGMA index_list(\"$tbl\");" 2>/dev/null)
        if [[ -n "$idx_list" ]]; then
            idx_count=$(echo "$idx_list" | wc -l | tr -d ' ')
            printf '\n%s\n' "Indexes ($idx_count):"
            while IFS='|' read -r seq idx_name is_unique origin partial; do
                unique_str=""
                [[ "$is_unique" == "1" ]] && unique_str="UNIQUE "
                idx_cols=$(sqlite3 "$db_path" "PRAGMA index_info(\"$idx_name\");" 2>/dev/null | cut -d'|' -f3 | paste -sd',' - | sed 's/,/, /g')
                printf '%s\n' "  ${unique_str}${idx_name} ($idx_cols)"
            done <<< "$idx_list"
        fi

        # Foreign keys
        fk_list=$(sqlite3 "$db_path" "PRAGMA foreign_key_list(\"$tbl\");" 2>/dev/null)
        if [[ -n "$fk_list" ]]; then
            fk_count=$(echo "$fk_list" | wc -l | tr -d ' ')
            printf '\n%s\n' "Foreign Keys ($fk_count):"
            while IFS='|' read -r id fk_seq fk_table from_col to_col on_update on_delete match_val; do
                printf '%s\n' "  $from_col → ${fk_table}.${to_col} (ON DELETE $on_delete, ON UPDATE $on_update)"
            done <<< "$fk_list"
        fi

        # Sample data
        if [[ "$include_data" == "true" ]] && (( row_count > 0 )); then
            printf '\n%s\n' "Sample Data (first $SAMPLE_ROWS rows):"
            sample=$(sqlite3 -header -column "$db_path" "SELECT * FROM \"$tbl\" LIMIT $SAMPLE_ROWS;" 2>/dev/null)
            if [[ -n "$sample" ]]; then
                while IFS= read -r line; do
                    printf '%s\n' "  $line"
                done <<< "$sample"
            fi
        fi

    done <<< "$tables"

    # Views
    local views
    views=$(sqlite3 "$db_path" "SELECT name, sql FROM sqlite_master WHERE type='view' ORDER BY name;" 2>/dev/null)
    if [[ -n "$views" ]]; then
        local view_count vname vsql
        view_count=$(echo "$views" | wc -l | tr -d ' ')
        printf '\n%s\n' "═══ Views ($view_count) ═══"
        while IFS='|' read -r vname vsql; do
            printf '\n%s\n' "-- View: $vname"
            printf '%s\n' '```sql'
            printf '%s\n' "$vsql"
            printf '%s\n' '```'
        done <<< "$views"
    fi

    # Triggers
    local triggers
    triggers=$(sqlite3 "$db_path" "SELECT name, tbl_name, sql FROM sqlite_master WHERE type='trigger' ORDER BY name;" 2>/dev/null)
    if [[ -n "$triggers" ]]; then
        local trig_count tname ttbl tsql
        trig_count=$(echo "$triggers" | wc -l | tr -d ' ')
        printf '\n%s\n' "═══ Triggers ($trig_count) ═══"
        while IFS='|' read -r tname ttbl tsql; do
            printf '\n%s\n' "-- Trigger: $tname (on $ttbl)"
            printf '%s\n' '```sql'
            printf '%s\n' "$tsql"
            printf '%s\n' '```'
        done <<< "$triggers"
    fi

    printf '\n%s\n' "═══ End of Inspection ═══"
}

# ─── Mode Handlers ────────────────────────────────────────────────────────────

mode_inspect() {
    local file="$1"
    validate_file "$file"
    check_usage

    log "Inspecting: $file (mode: inspect)"

    local result
    result=$(inspect_database "$file" "true")

    # Copy to clipboard
    printf '%s' "$result" | pbcopy

    # Count for notification
    local tbl_count total
    tbl_count=$(sqlite3 "$file" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';" 2>/dev/null || echo "0")
    total=0
    local tables t c
    tables=$(sqlite3 "$file" "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';" 2>/dev/null)
    if [[ -n "$tables" ]]; then
        while IFS= read -r t; do
            c=$(sqlite3 "$file" "SELECT COUNT(*) FROM \"$t\";" 2>/dev/null || echo "0")
            total=$((total + c))
        done <<< "$tables"
    fi

    increment_usage
    notify "$APP_NAME" "$tbl_count tables, $(printf "%'d" $total) rows — copied to clipboard"
    log "Done: $tbl_count tables, $total rows"
}

mode_clipboard() {
    local file="$1"
    validate_file "$file"
    check_usage

    log "Clipboard: $file"

    local result
    result=$(inspect_database "$file" "true")
    printf '%s' "$result" | pbcopy

    local tbl_count
    tbl_count=$(sqlite3 "$file" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';" 2>/dev/null || echo "0")

    increment_usage
    notify "$APP_NAME" "Schema + data copied to clipboard ($tbl_count tables)"
    log "Clipboard done: $tbl_count tables"
}

mode_dump() {
    local file="$1"
    validate_file "$file"
    check_usage

    log "Dump: $file"

    local result
    result=$(inspect_database "$file" "true")

    # Save alongside the database
    local base_path output_path
    base_path="${file%.*}"
    output_path="${base_path}_schema.md"
    printf '%s\n' "$result" > "$output_path"

    increment_usage
    notify "$APP_NAME" "Schema saved to $(basename "$output_path")"
    log "Dump saved: $output_path"
}

# ─── Main ─────────────────────────────────────────────────────────────────────

if (( $# < 2 )); then
    echo "Usage: dblook <mode> <file>"
    echo "Modes: inspect, clipboard, dump"
    exit 1
fi

MODE="$1"
shift

FILE="$1"

case "$MODE" in
    inspect)    mode_inspect "$FILE" ;;
    clipboard)  mode_clipboard "$FILE" ;;
    dump)       mode_dump "$FILE" ;;
    *)
        echo "Unknown mode: $MODE"
        echo "Modes: inspect, clipboard, dump"
        exit 1
        ;;
esac
