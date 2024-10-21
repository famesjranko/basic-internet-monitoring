#!/bin/bash

# Targets array
TARGETS=("8.8.8.8" "1.1.1.1" "9.9.9.9")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DB_FILE="$SCRIPT_DIR/logs/internet_status.db"
RETENTION_DAYS=14 # Set db retention period in days (default is 14 days, can be preset as a positive number)

FAILURE_COUNT_FILE="$SCRIPT_DIR/logs/failure_count.txt"
LOG_FILE="$SCRIPT_DIR/logs/check_internet.log"

now=$(date '+%Y-%m-%d %H:%M:%S')

SUCCESS_COUNT=0
LATENCIES=()
PING_COUNT_PER_TARGET=33
TOTAL_COUNT=$(( ${#TARGETS[@]} * PING_COUNT_PER_TARGET ))

# Initialize failure count file if it doesn't exist
if [ ! -f $FAILURE_COUNT_FILE ]; then
    echo "0" > $FAILURE_COUNT_FILE
fi

# Initialize SQLite database and table if not exists
sqlite3 $DB_FILE "CREATE TABLE IF NOT EXISTS internet_status (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME,
    status TEXT,
    success_percentage INTEGER,
    avg_latency_ms REAL,
    max_latency_ms REAL,
    min_latency_ms REAL,
    packet_loss REAL
);" 2>> $LOG_FILE  # Log any errors

# Function to ping targets and collect latency
check_internet() {
    for target in ${TARGETS[@]}; do
        for i in $(seq 1 $PING_COUNT_PER_TARGET); do
            PING_RESULT=$(ping -c 1 -W 5 $target | grep 'time=')
            if [[ $PING_RESULT ]]; then
                # Extract the latency in ms and add it to the list
                LATENCY=$(echo $PING_RESULT | sed -e 's/.*time=\([0-9.]*\).*/\1/')
                LATENCIES+=($LATENCY)
                SUCCESS_COUNT=$((SUCCESS_COUNT+1))
            fi
        done
    done
}

# Run the check
check_internet
echo "finished running internet check" >> $LOG_FILE

# Calculate the success percentage
SUCCESS_PERCENTAGE=$((SUCCESS_COUNT * 100 / TOTAL_COUNT))

# Calculate average, min, max latency if there are successful pings
if [[ $SUCCESS_COUNT -gt 0 ]]; then
    AVG_LATENCY=$(echo "${LATENCIES[@]}" | awk '{for(i=1;i<=NF;i++) sum+=$i; print sum/NF}')
    MAX_LATENCY=$(echo "${LATENCIES[@]}" | awk '{for(i=1;i<=NF;i++) if($i>max) max=$i; print max}')
    MIN_LATENCY=$(echo "${LATENCIES[@]}" | awk '{for(i=1;i<=NF;i++) if(min=="" || $i<min) min=$i; print min}')
else
    AVG_LATENCY="NULL"
    MAX_LATENCY="NULL"
    MIN_LATENCY="NULL"
fi

# Log the calculated latencies regardless of success
echo "Latencies calculated - AVG: $AVG_LATENCY, MAX: $MAX_LATENCY, MIN: $MIN_LATENCY" >> $LOG_FILE

# Calculate packet loss
LOSS_COUNT=$((TOTAL_COUNT - SUCCESS_COUNT))
PACKET_LOSS_PERCENTAGE=$((LOSS_COUNT * 100 / TOTAL_COUNT))

# Determine status based on success percentage
if [[ $SUCCESS_PERCENTAGE -eq 100 ]]; then
    STATUS="Internet is fully up (100% success)"
elif [[ $SUCCESS_PERCENTAGE -gt 0 ]]; then
    STATUS="Internet is partially up ($SUCCESS_PERCENTAGE% success)"
else
    STATUS="Internet is down (0% success)"
fi

# Insert log into the database with error handling
sqlite3 $DB_FILE "INSERT INTO internet_status (timestamp, status, success_percentage, avg_latency_ms, max_latency_ms, min_latency_ms, packet_loss)
VALUES ('$now', '$STATUS', $SUCCESS_PERCENTAGE, $AVG_LATENCY, $MAX_LATENCY, $MIN_LATENCY, $PACKET_LOSS_PERCENTAGE);" 2>> $LOG_FILE

if [[ $? -eq 0 ]]; then
    echo "Log successfully inserted into db" >> $LOG_FILE
else
    echo "Failed to insert log into db" >> $LOG_FILE
fi

# Clean up old data (keep only last RETENTION_DAYS days worth of data)
sqlite3 $DB_FILE "DELETE FROM internet_status WHERE timestamp < datetime('now', '-$RETENTION_DAYS days');" 2>> $LOG_FILE

if [[ $? -eq 0 ]]; then
    echo "Old data successfully cleaned up (kept last $RETENTION_DAYS days)" >> $LOG_FILE
    echo "Old data successfully cleaned up (kept last $RETENTION_DAYS days)"
else
    echo "Failed to clean up old data" >> $LOG_FILE
    echo "Failed to clean up old data"
fi

# Handle consecutive failures
FAILURE_COUNT=$(cat $FAILURE_COUNT_FILE)

if [[ $SUCCESS_PERCENTAGE -eq 0 ]]; then
    # Increase failure count
    FAILURE_COUNT=$((FAILURE_COUNT + 1))
    echo $FAILURE_COUNT > $FAILURE_COUNT_FILE

    # If failure count exceeds 5 (indicating 5 minutes of downtime), trigger modem power cycle
    if [[ $FAILURE_COUNT -ge 5 ]]; then
        echo "Internet down for 5+ minutes. Power cycling modem..." >> $LOG_FILE

        # Activate the virtual environment
        source venv/bin/activate

        # Run the power cycle script within the virtual environment
        venv/bin/python3 scripts/power_cycle_p100.py >> $LOG_FILE 2>&1  # power cycle nbn

        # Log the power cycle action with error handling
        #sqlite3 $DB_FILE "INSERT INTO internet_status (timestamp, status) VALUES ('$now', 'Modem power cycled due to network failure');" 2>> $LOG_FILE

        if [[ $? -eq 0 ]]; then
            echo "Power cycle action logged successfully" >> $LOG_FILE
        else
            echo "Failed to log power cycle action" >> $LOG_FILE
        fi

        # Deactivate the virtual environment after running the script
        deactivate

        # Reset failure count after power cycle
        echo "0" > $FAILURE_COUNT_FILE

        # Create cooldown file with the current timestamp
        #date +%s > $COOLDOWN_FILE
    fi
else
    # Reset failure count if internet is back up
    echo "0" > $FAILURE_COUNT_FILE
fi
