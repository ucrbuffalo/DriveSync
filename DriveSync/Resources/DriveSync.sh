#!/bin/zsh

# App-owned resources
SCRIPT_PATH="${0:A}"
RESOURCE_DIR="${SCRIPT_PATH:h}"

EXCLUDES="$RESOURCE_DIR/exclusions"
XATTR_EXCLUSIONS="$RESOURCE_DIR/xattr-exclusions"

# User-owned data
APP_SUPPORT="$HOME/Library/Application Support/DriveSync"
CONFIG_DIR="$APP_SUPPORT/config"

CONFIG="$CONFIG_DIR/config.plist"
USER_EXCLUDES="$CONFIG_DIR/exclusions-user"

LOG_DIR="$APP_SUPPORT/logs"
HEALTH_LOG_DIR="$LOG_DIR/health"

STATE_DIR="$APP_SUPPORT/state"
LOCK_DIR="$STATE_DIR/running.lock"

RSYNC_BIN="${DRIVESYNC_RSYNC:-}"

if ! mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$HEALTH_LOG_DIR" "$STATE_DIR" 2>/dev/null; then
    /usr/bin/notifyutil -p com.drivesync.app.notification.workingDirectoriesUnavailable
    exit 1
fi

TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)

if [ "$1" = "--check" ]; then
    LOG_FILE="$HEALTH_LOG_DIR/HealthCheck-$TIMESTAMP.log"
else
    LOG_FILE="$LOG_DIR/DriveSync-$TIMESTAMP.log"
fi

LAST_SUCCESS="$STATE_DIR/last-success"
CANCEL_FLAG="$STATE_DIR/cancelled"
STALE_NOTIFIED="$STATE_DIR/stale-notified"
CURRENT_LOG="$STATE_DIR/current-log"
ISSUES_FILE="$STATE_DIR/issues.jsonl"

if [ ! -w "$LOG_DIR" ] || [ ! -w "$HEALTH_LOG_DIR" ] || [ ! -w "$STATE_DIR" ]; then
    /usr/bin/notifyutil -p com.drivesync.app.notification.workingDirectoriesNotWritable
    exit 1
fi

record_issue() {
    local ISSUE_TYPE="$1"
    local LOCATION="${2:-}"
    local ISSUE_PATH="${3:-}"
    local RSYNC_CODE="${4:-}"
    local TECHNICAL_DETAIL="${5:-}"

    local ISSUE_TIMESTAMP
    ISSUE_TIMESTAMP=$(date -Iseconds)

    local TEMP_ISSUE
    TEMP_ISSUE="$STATE_DIR/.issue-$$.plist"

    /usr/bin/plutil -create xml1 "$TEMP_ISSUE" || return 1

    /usr/bin/plutil -insert timestamp \
        -string "$ISSUE_TIMESTAMP" \
        "$TEMP_ISSUE" || return 1

    /usr/bin/plutil -insert type \
        -string "$ISSUE_TYPE" \
        "$TEMP_ISSUE" || return 1

    /usr/bin/plutil -insert logFile \
        -string "$LOG_FILE" \
        "$TEMP_ISSUE" || return 1

    if [ -n "$LOCATION" ]; then
        /usr/bin/plutil -insert location \
            -string "$LOCATION" \
            "$TEMP_ISSUE" || return 1
    fi

    if [ -n "$ISSUE_PATH" ]; then
        /usr/bin/plutil -insert path \
            -string "$ISSUE_PATH" \
            "$TEMP_ISSUE" || return 1
    fi

    if [ -n "$RSYNC_CODE" ]; then
        /usr/bin/plutil -insert rsyncExitCode \
            -integer "$RSYNC_CODE" \
            "$TEMP_ISSUE" || return 1
    fi

    if [ -n "$TECHNICAL_DETAIL" ]; then
        /usr/bin/plutil -insert technicalDetail \
            -string "$TECHNICAL_DETAIL" \
            "$TEMP_ISSUE" || return 1
    fi

    /usr/bin/plutil -convert json -o - "$TEMP_ISSUE" \
        | /usr/bin/tr -d '\n' >> "$ISSUES_FILE"

    printf '\n' >> "$ISSUES_FILE"

    rm -f "$TEMP_ISSUE"
}

# Stop a currently running DriveSync operation
if [ "$1" = "--stop" ]; then
    if [ ! -f "$LOCK_DIR/pid" ]; then
        echo "DriveSync is not currently running."
        exit 0
    fi

    RUNNING_PID=$(cat "$LOCK_DIR/pid")

    if ! kill -0 "$RUNNING_PID" 2>/dev/null; then
        echo "DriveSync is not currently running. Removing stale lock."
        rm -rf "$LOCK_DIR"
        exit 0
    fi

    RUNNING_COMMAND=$(ps -ww -p "$RUNNING_PID" -o command=)

    if [[ "$RUNNING_COMMAND" != *"$SCRIPT_PATH"* ]]; then
        echo "The stored PID does not belong to DriveSync. Removing stale lock."
        rm -rf "$LOCK_DIR"
        exit 0
    fi

    echo "Stopping DriveSync..."

    if [ -f "$LOCK_DIR/rsync-pid" ]; then
    RSYNC_PID=$(cat "$LOCK_DIR/rsync-pid")

    if [ -f "$CURRENT_LOG" ]; then
        ACTIVE_LOG=$(cat "$CURRENT_LOG")
    else
        ACTIVE_LOG="$LOG_FILE"
    fi

    echo "$(date): Stop requested for rsync PID $RSYNC_PID." >> "$ACTIVE_LOG"

    if kill -0 "$RSYNC_PID" 2>/dev/null; then
        echo "$(date): rsync PID $RSYNC_PID is running." >> "$ACTIVE_LOG"

        if touch "$CANCEL_FLAG"; then
            echo "$(date): Cancellation flag created at $CANCEL_FLAG." >> "$ACTIVE_LOG"
        else
            echo "$(date): ERROR: Could not create cancellation flag at $CANCEL_FLAG." >> "$ACTIVE_LOG"
        fi

        if kill -TERM "$RSYNC_PID"; then
            echo "$(date): SIGTERM sent to rsync PID $RSYNC_PID." >> "$ACTIVE_LOG"
        else
            echo "$(date): ERROR: Could not send SIGTERM to rsync PID $RSYNC_PID." >> "$ACTIVE_LOG"
        fi
    else
        echo "$(date): rsync PID $RSYNC_PID was not running when Stop was requested." >> "$ACTIVE_LOG"
    fi
else
    if [ -f "$CURRENT_LOG" ]; then
        ACTIVE_LOG=$(cat "$CURRENT_LOG")
        echo "$(date): Stop requested, but no rsync PID file was found." >> "$ACTIVE_LOG"
    fi
fi

    exit 0
fi

config_error() {
    local MESSAGE="$1"

    echo "$(date): Configuration error: $MESSAGE Sync aborted." >> "$LOG_FILE"

    record_issue \
        "configurationProblem" \
        "" \
        "" \
        "" \
        "$MESSAGE"

    /usr/bin/notifyutil -p com.drivesync.app.notification.configurationProblem

    exit 1
}

if [ ! -f "$CONFIG" ]; then
    config_error "DriveSync's configuration file could not be found."
fi

PLIST_ERROR=$(/usr/bin/plutil -lint "$CONFIG" 2>&1)

if [ $? -ne 0 ]; then
    echo "$(date): Config validation detail: $PLIST_ERROR" >> "$LOG_FILE"
    config_error "DriveSync's configuration file is invalid."
fi

SOURCE=$(/usr/libexec/PlistBuddy -c "Print :SourcePath" "$CONFIG" 2>/dev/null) \
    || config_error "The source path is missing from DriveSync's configuration."

DEST=$(/usr/libexec/PlistBuddy -c "Print :DestinationPath" "$CONFIG" 2>/dev/null) \
    || config_error "The destination path is missing from DriveSync's configuration."

SCHEDULE_WINDOW=$(/usr/libexec/PlistBuddy -c "Print :ScheduleWindowMinutes" "$CONFIG" 2>/dev/null) \
    || config_error "The schedule window is missing from DriveSync's configuration."

STALE_SYNC_DAYS=$(/usr/libexec/PlistBuddy -c "Print :StaleSyncDays" "$CONFIG" 2>/dev/null) \
    || config_error "The stale sync threshold is missing from DriveSync's configuration."

LOG_RETENTION_DAYS=$(/usr/libexec/PlistBuddy -c "Print :LogRetentionDays" "$CONFIG" 2>/dev/null) \
    || config_error "The log retention period is missing from DriveSync's configuration."

if [ -z "$SOURCE" ]; then
    config_error "The source path is empty in DriveSync's configuration."
fi

if [ -z "$DEST" ]; then
    config_error "The destination path is empty in DriveSync's configuration."
fi

if ! [[ "$SCHEDULE_WINDOW" =~ ^[0-9]+$ ]] || [ "$SCHEDULE_WINDOW" -lt 1 ] || [ "$SCHEDULE_WINDOW" -gt 59 ]; then
    config_error "The schedule window in DriveSync's configuration is invalid."
fi

if ! [[ "$STALE_SYNC_DAYS" =~ ^[0-9]+$ ]] || [ "$STALE_SYNC_DAYS" -lt 1 ]; then
    config_error "The stale sync threshold in DriveSync's configuration is invalid."
fi

if ! [[ "$LOG_RETENTION_DAYS" =~ ^[0-9]+$ ]] || [ "$LOG_RETENTION_DAYS" -lt 1 ]; then
    config_error "The log retention period in DriveSync's configuration is invalid."
fi

SCHEDULE_HOURS=()
SCHEDULE_MINUTES=()
SCHEDULE_INDEX=0

while true; do
    SCHEDULE_HOUR=$(/usr/libexec/PlistBuddy \
        -c "Print :ScheduleTimes:$SCHEDULE_INDEX:Hour" \
        "$CONFIG" 2>/dev/null)

    if [ $? -ne 0 ]; then
        break
    fi

    SCHEDULE_MINUTE=$(/usr/libexec/PlistBuddy \
        -c "Print :ScheduleTimes:$SCHEDULE_INDEX:Minute" \
        "$CONFIG" 2>/dev/null)

    if [ $? -ne 0 ]; then
        config_error "The sync schedule in DriveSync's configuration contains a time without a minute."
    fi

    SCHEDULE_HOURS+=("$SCHEDULE_HOUR")
    SCHEDULE_MINUTES+=("$SCHEDULE_MINUTE")

    SCHEDULE_INDEX=$((SCHEDULE_INDEX + 1))
done

if [ "${#SCHEDULE_HOURS[@]}" -eq 0 ]; then
    config_error "The sync schedule in DriveSync's configuration is missing or empty."
fi

for ((i = 1; i <= ${#SCHEDULE_HOURS[@]}; i++)); do
    HOUR="${SCHEDULE_HOURS[$i]}"
    MINUTE="${SCHEDULE_MINUTES[$i]}"

    if ! [[ "$HOUR" =~ ^[0-9]+$ ]] ||
       [ "$HOUR" -lt 0 ] ||
       [ "$HOUR" -gt 23 ]; then
        config_error "The sync schedule in DriveSync's configuration contains an invalid hour."
    fi

    if ! [[ "$MINUTE" =~ ^[0-9]+$ ]] ||
       [ "$MINUTE" -lt 0 ] ||
       [ "$MINUTE" -gt 59 ]; then
        config_error "The sync schedule in DriveSync's configuration contains an invalid minute."
    fi
done

find "$LOG_DIR" -type f -name 'DriveSync-*.log' -mtime +"$LOG_RETENTION_DAYS" -delete
find "$HEALTH_LOG_DIR" -type f -name 'HealthCheck-*.log' -mtime +"$LOG_RETENTION_DAYS" -delete

# Lock Error
lock_error() {
    echo "$(date): Unable to create DriveSync process lock. Sync aborted." >> "$LOG_FILE"

    record_issue \
        "internalProblem" \
        "" \
        "$LOCK_DIR" \
        "" \
        "DriveSync could not establish its process lock."

    /usr/bin/notifyutil -p com.drivesync.app.notification.processLockFailed

    exit 1
}

# Stale Check
check_stale_sync() {
    local STALE_REMINDER_SECONDS=$((7 * 86400))

    if [ ! -f "$LAST_SUCCESS" ]; then
        echo "$(date): No successful sync has been recorded yet." >> "$LOG_FILE"

        rm -f "$STALE_NOTIFIED"

        return 1
    fi

    LAST_SUCCESS_EPOCH=$(stat -f %m "$LAST_SUCCESS")
    CURRENT_EPOCH=$(date +%s)

    AGE_SECONDS=$((CURRENT_EPOCH - LAST_SUCCESS_EPOCH))
    STALE_SECONDS=$((STALE_SYNC_DAYS * 86400))

    if [ "$AGE_SECONDS" -ge "$STALE_SECONDS" ]; then
        AGE_DAYS=$((AGE_SECONDS / 86400))

        echo "$(date): DriveSync is stale. Last successful sync was $AGE_DAYS days ago." >> "$LOG_FILE"

        SHOULD_NOTIFY=false

        if [ ! -f "$STALE_NOTIFIED" ]; then
            SHOULD_NOTIFY=true
        else
            LAST_STALE_NOTIFICATION_EPOCH=$(stat -f %m "$STALE_NOTIFIED")
            STALE_NOTIFICATION_AGE_SECONDS=$((CURRENT_EPOCH - LAST_STALE_NOTIFICATION_EPOCH))

            if [ "$STALE_NOTIFICATION_AGE_SECONDS" -ge "$STALE_REMINDER_SECONDS" ]; then
                SHOULD_NOTIFY=true
            fi
        fi

        if [ "$SHOULD_NOTIFY" = true ]; then
            /usr/bin/notifyutil -p com.drivesync.app.notification.staleSync
            touch "$STALE_NOTIFIED"

            echo "$(date): Stale-sync notification sent." >> "$LOG_FILE"
        else
            echo "$(date): Stale-sync reminder is not due yet." >> "$LOG_FILE"
        fi

        return 1
    fi

    rm -f "$STALE_NOTIFIED"

    AGE_DAYS=$((AGE_SECONDS / 86400))
    echo "$(date): DriveSync health check passed. Last successful sync was $AGE_DAYS days ago." >> "$LOG_FILE"

    return 0
}

# Check DriveSync health without running a sync
if [ "$1" = "--check" ]; then
    check_stale_sync
    exit $?
fi

# One-shot access probe. Walks the real source and destination with the real
# filters, transferring nothing, so Setup can surface macOS permission
# prompts without starting a full backup.
ACCESS_FLAG="$STATE_DIR/check-access"

if [ -f "$ACCESS_FLAG" ]; then
    rm -f "$ACCESS_FLAG"

    echo "$(date): Folder access check started." >> "$LOG_FILE"

    if [ -z "$RSYNC_BIN" ] || [ ! -x "$RSYNC_BIN" ]; then
        echo "$(date): Access check aborted: bundled rsync unavailable." >> "$LOG_FILE"
        exit 1
    fi

    if [ ! -f "$EXCLUDES" ] || [ ! -f "$USER_EXCLUDES" ]; then
        echo "$(date): Access check aborted: exclusions unavailable." >> "$LOG_FILE"
        exit 1
    fi

    if [ ! -d "$SOURCE" ]; then
        echo "$(date): Access check aborted: source folder unavailable." >> "$LOG_FILE"
        exit 1
    fi

    if [ ! -d "$DEST" ]; then
        echo "$(date): Access check aborted: destination folder unavailable." >> "$LOG_FILE"
        exit 1
    fi

    "$RSYNC_BIN" \
        --archive \
        --dry-run \
        --xattrs \
        --acls \
        --filter="merge $XATTR_EXCLUSIONS" \
        --exclude-from="$EXCLUDES" \
        --exclude-from="$USER_EXCLUDES" \
        "$SOURCE/" \
        "$DEST/" \
        >> "$LOG_FILE" 2>&1

    ACCESS_STATUS=$?

    # 23 and 24 mean files vanished or were skipped during the walk.
    # Normal on a live source; not an access failure.
    if [ "$ACCESS_STATUS" -ne 0 ] &&
       [ "$ACCESS_STATUS" -ne 23 ] &&
       [ "$ACCESS_STATUS" -ne 24 ]; then
        echo "$(date): Folder access check failed with status $ACCESS_STATUS." >> "$LOG_FILE"
        exit "$ACCESS_STATUS"
    fi

    # Confirm the destination is writable using the bundled rsync.
    PROBE_DIR="$STATE_DIR/probe-$$"
    PROBE_NAME=".drivesync-access-probe"

    if ! mkdir -p "$PROBE_DIR"; then
        echo "$(date): Access check aborted: could not stage write probe." >> "$LOG_FILE"
        exit 1
    fi

    printf 'DriveSync access probe\n' > "$PROBE_DIR/$PROBE_NAME"

    "$RSYNC_BIN" \
        --archive \
        "$PROBE_DIR/$PROBE_NAME" \
        "$DEST/" \
        >> "$LOG_FILE" 2>&1

    WRITE_STATUS=$?

    rm -rf "$PROBE_DIR"

    if [ "$WRITE_STATUS" -ne 0 ]; then
        echo "$(date): Destination is not writable." >> "$LOG_FILE"
        exit 1
    fi

    if ! rm -f "$DEST/$PROBE_NAME" 2>> "$LOG_FILE"; then
        echo "$(date): Note: probe file left in the destination." >> "$LOG_FILE"
    fi

    echo "$(date): Folder access check passed." >> "$LOG_FILE"
    exit 0
fi

# Manual runs bypass the schedule guard. The app also drops a one-shot flag
# when it needs an immediate run, so the sync happens under this launchd job
# rather than as a child of the app.
RUN_NOW_FLAG="$STATE_DIR/run-now"

FORCE_RUN=false

if [ "$1" = "--manual" ]; then
    FORCE_RUN=true
elif [ -f "$RUN_NOW_FLAG" ]; then
    FORCE_RUN=true
    rm -f "$RUN_NOW_FLAG"
    echo "$(date): Immediate run requested by DriveSync." >> "$LOG_FILE"
fi

if [ "$FORCE_RUN" != true ]; then

    CURRENT_HOUR=$(date +%H)
    CURRENT_MINUTE=$(date +%M)
    VALID_TIME=false

    CURRENT_HOUR_NUMBER=$((10#$CURRENT_HOUR))
    CURRENT_MINUTE_NUMBER=$((10#$CURRENT_MINUTE))

    CURRENT_TOTAL_MINUTES=$((CURRENT_HOUR_NUMBER * 60 + CURRENT_MINUTE_NUMBER))

    for ((i = 1; i <= ${#SCHEDULE_HOURS[@]}; i++)); do
        SCHEDULE_HOUR="${SCHEDULE_HOURS[$i]}"
        SCHEDULE_MINUTE="${SCHEDULE_MINUTES[$i]}"

        SCHEDULE_TOTAL_MINUTES=$((SCHEDULE_HOUR * 60 + SCHEDULE_MINUTE))

        MINUTES_SINCE_SCHEDULE=$((CURRENT_TOTAL_MINUTES - SCHEDULE_TOTAL_MINUTES))

        if [ "$MINUTES_SINCE_SCHEDULE" -ge 0 ] &&
           [ "$MINUTES_SINCE_SCHEDULE" -lt "$SCHEDULE_WINDOW" ]; then
            VALID_TIME=true
            break
        fi
    done

    if [ "$VALID_TIME" != true ]; then
        echo "$(date): DriveSync launched outside scheduled window. Sync skipped." >> "$LOG_FILE"
        exit 0
    fi

fi

# Validate the bundled rsync engine only when a sync is actually about to run
if [ -z "$RSYNC_BIN" ] || [ ! -x "$RSYNC_BIN" ]; then
    echo "$(date): DriveSync's bundled rsync engine is unavailable. Sync aborted." >> "$LOG_FILE"

    record_issue \
        "internalProblem" \
        "" \
        "$RSYNC_BIN" \
        "" \
        "DriveSync's bundled rsync engine is unavailable."

    exit 1
fi

# Start DriveSync
echo "$(date): DriveSync started." >> "$LOG_FILE"
echo "$LOG_FILE" > "$CURRENT_LOG"

# Check Lock Directory
if mkdir "$LOCK_DIR" 2>/dev/null; then
    echo $$ > "$LOCK_DIR/pid"
else
    if [ -f "$LOCK_DIR/pid" ]; then
        LOCK_PID=$(cat "$LOCK_DIR/pid")

        if kill -0 "$LOCK_PID" 2>/dev/null; then
    LOCK_COMMAND=$(ps -ww -p "$LOCK_PID" -o command=)

            if [[ "$LOCK_COMMAND" == *"$SCRIPT_PATH"* ]]; then
                echo "$(date): Another DriveSync operation is already running. Sync skipped." >> "$LOG_FILE"
                exit 0
        else
            echo "$(date): Lock PID belongs to another process. Removing stale lock." >> "$LOG_FILE"
            rm -rf "$LOCK_DIR"

            if ! mkdir "$LOCK_DIR" 2>/dev/null; then
                lock_error
            fi

            echo $$ > "$LOCK_DIR/pid"
        fi
    else
            echo "$(date): Stale DriveSync lock found. Removing it." >> "$LOG_FILE"
            rm -rf "$LOCK_DIR"

            if ! mkdir "$LOCK_DIR" 2>/dev/null; then
                lock_error
            fi

            echo $$ > "$LOCK_DIR/pid"
        fi
    else
        echo "$(date): DriveSync lock exists without a PID. Removing stale lock." >> "$LOG_FILE"
        rm -rf "$LOCK_DIR"

        if ! mkdir "$LOCK_DIR" 2>/dev/null; then
            lock_error
        fi

        echo $$ > "$LOCK_DIR/pid"
    fi
fi

trap 'rm -rf "$LOCK_DIR"; rm -f "$CURRENT_LOG"' EXIT INT TERM

if [ ! -f "$EXCLUDES" ]; then
    echo "$(date): Exclusions file unavailable. Sync aborted." >> "$LOG_FILE"

    record_issue \
        "internalProblem" \
        "" \
        "$EXCLUDES" \
        "" \
        "DriveSync's built-in exclusions file could not be found."

    /usr/bin/notifyutil -p com.drivesync.app.notification.systemExclusionsMissing
    exit 1
fi

if [ ! -f "$USER_EXCLUDES" ]; then
    echo "$(date): User exclusions file unavailable. Sync aborted." >> "$LOG_FILE"

    record_issue \
        "configurationProblem" \
        "" \
        "$USER_EXCLUDES" \
        "" \
        "DriveSync's user exclusions file could not be found."

    /usr/bin/notifyutil -p com.drivesync.app.notification.userExclusionsMissing
    exit 1
fi

if [ ! -d "$SOURCE" ]; then
    echo "$(date): Source path unavailable. Sync skipped." >> "$LOG_FILE"
    check_stale_sync
    exit 0
fi

if [ ! -d "$DEST" ]; then
    echo "$(date): Destination path unavailable. Sync skipped." >> "$LOG_FILE"
    check_stale_sync
    exit 0
fi

"$RSYNC_BIN" \
    --archive \
    --no-perms \
    --crtimes \
    --verbose \
    --human-readable \
    --xattrs \
    --acls \
    --partial \
    --stats \
    --itemize-changes \
    --filter="merge $XATTR_EXCLUSIONS" \
    --exclude-from="$EXCLUDES" \
    --exclude-from="$USER_EXCLUDES" \
    "$SOURCE/" \
    "$DEST/" \
    >> "$LOG_FILE" 2>&1 &

RSYNC_PID=$!
echo "$RSYNC_PID" > "$LOCK_DIR/rsync-pid"

wait "$RSYNC_PID"
RSYNC_STATUS=$?

ACCESS_ERROR=$(
    /usr/bin/grep -m 1 -E \
        'failed: (Operation not permitted|Permission denied)( \([0-9]+\))?' \
        "$LOG_FILE"
)

DESTINATION_FULL_ERROR=$(
    /usr/bin/grep -m 1 -F \
        'No space left on device' \
        "$LOG_FILE"
)

if [ -f "$CANCEL_FLAG" ]; then
    echo "$(date): Cancellation flag detected after rsync exited with code $RSYNC_STATUS." >> "$LOG_FILE"
else
    echo "$(date): No cancellation flag detected after rsync exited with code $RSYNC_STATUS." >> "$LOG_FILE"
fi

if [ -f "$CANCEL_FLAG" ]; then
    rm -f "$CANCEL_FLAG"
    echo "$(date): DriveSync cancelled by user." >> "$LOG_FILE"
    RSYNC_STATUS=0

elif [ "$RSYNC_STATUS" -eq 0 ]; then
    date > "$LAST_SUCCESS"
    rm -f "$STALE_NOTIFIED"
    echo "$(date): DriveSync completed successfully." >> "$LOG_FILE"

elif [ ! -d "$SOURCE" ] || [ ! -d "$DEST" ]; then
    echo "$(date): DriveSync was interrupted. Source or destination became unavailable during sync." >> "$LOG_FILE"

    if [ ! -d "$SOURCE" ]; then
        INTERRUPTED_LOCATION="source"
        INTERRUPTED_PATH="$SOURCE"
    else
        INTERRUPTED_LOCATION="destination"
        INTERRUPTED_PATH="$DEST"
    fi

    record_issue \
        "syncInterrupted" \
        "$INTERRUPTED_LOCATION" \
        "$INTERRUPTED_PATH" \
        "$RSYNC_STATUS" \
        "The source or destination became unavailable during the sync."

    check_stale_sync
    
elif [ -n "$ACCESS_ERROR" ]; then
    echo "$(date): DriveSync access denied. rsync exit code: $RSYNC_STATUS" >> "$LOG_FILE"

    if [[ "$ACCESS_ERROR" == *"$SOURCE"* ]]; then
        ACCESS_LOCATION="source"
        ACCESS_PATH="$SOURCE"
    elif [[ "$ACCESS_ERROR" == *"$DEST"* ]]; then
        ACCESS_LOCATION="destination"
        ACCESS_PATH="$DEST"
    else
        ACCESS_LOCATION=""
        ACCESS_PATH=""
    fi

    record_issue \
        "accessDenied" \
        "$ACCESS_LOCATION" \
        "$ACCESS_PATH" \
        "$RSYNC_STATUS" \
        "$ACCESS_ERROR"

    /usr/bin/notifyutil -p com.drivesync.app.notification.accessDenied
    check_stale_sync

elif [ -n "$DESTINATION_FULL_ERROR" ]; then
    echo "$(date): DriveSync destination is full. rsync exit code: $RSYNC_STATUS" >> "$LOG_FILE"

    record_issue \
        "destinationFull" \
        "destination" \
        "$DEST" \
        "$RSYNC_STATUS" \
        "$DESTINATION_FULL_ERROR"

    /usr/bin/notifyutil -p com.drivesync.app.notification.destinationFull
    check_stale_sync

elif [ "$RSYNC_STATUS" -eq 23 ] || [ "$RSYNC_STATUS" -eq 24 ]; then
    echo "$(date): DriveSync completed with a partial transfer. rsync exit code: $RSYNC_STATUS" >> "$LOG_FILE"

    record_issue \
        "partialTransfer" \
        "" \
        "" \
        "$RSYNC_STATUS" \
        "Some files or file attributes could not be transferred."

    /usr/bin/notifyutil -p com.drivesync.app.notification.partialTransfer
    check_stale_sync

else
    echo "$(date): DriveSync FAILED. rsync exit code: $RSYNC_STATUS" >> "$LOG_FILE"

    record_issue \
        "syncFailed" \
        "" \
        "" \
        "$RSYNC_STATUS" \
        "rsync exited with an unexpected error."

    /usr/bin/notifyutil -p com.drivesync.app.notification.syncFailed
    check_stale_sync
fi

exit "$RSYNC_STATUS"
