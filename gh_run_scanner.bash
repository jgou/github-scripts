#!/bin/bash

# Usage: ./gh_run_scanner.bash FlyrInc/ooms-retail
REPO=$1
START_DATE="2026-03-18T00:00:00Z"
END_DATE="2026-03-21T23:59:59Z"
KEYWORDS="trivy:latest@sha256"

if [ -z "$REPO" ]; then echo "Usage: $0 <OWNER/REPO>"; exit 1; fi

echo "--- Starting UNLIMITED Audit for $REPO ---"
echo "Time Window: $START_DATE to $END_DATE"

# Fetch EVERY Run ID and its workflow name using pagination
# This bypasses the 1000-run limit of the 'gh run list' command
echo "Fetching all run IDs and workflow names (this may take a moment)..."
RUN_DATA=$(gh api --paginate "/repos/$REPO/actions/runs?created=$START_DATE..$END_DATE" \
          --jq '.workflow_runs[] | "\(.id):\(.name)"')

COUNT=$(echo "$RUN_DATA" | wc -l)
echo "Found $COUNT total runs. Starting deep scan..."

echo "$RUN_DATA" | while read -r RUN_INFO; do
    ID=$(echo "$RUN_INFO" | cut -d: -f1)
    WORKFLOW_NAME=$(echo "$RUN_INFO" | cut -d: -f2-)
    echo -n "Checking Run $ID (Workflow: $WORKFLOW_NAME)... "
    ZIP_FILE="logs_$ID.zip"
    TEMP_DIR="audit_$ID"

    # Download raw logs
    gh api "/repos/$REPO/actions/runs/$ID/logs" > "$ZIP_FILE" 2>/dev/null

    # Check if the file is a real zip file before trying to unzip
    if file "$ZIP_FILE" | grep -q "Zip archive data"; then
        mkdir -p "$TEMP_DIR"
        unzip -q "$ZIP_FILE" -d "$TEMP_DIR"
        
        # Search for the pattern in the logs
        MATCHES=$(grep -riE "$KEYWORDS" "$TEMP_DIR")

        if [ ! -z "$MATCHES" ]; then
            echo -e "\033[0;31m!! MATCH FOUND !!\033[0m"
            echo "URL: https://github.com/$REPO/actions/runs/$ID"
            echo "Workflow: $WORKFLOW_NAME"
            echo "$MATCHES" | sed 's/^/  /' 
            echo "--------------------------------------------------------"
        else
            echo "No matches found."
        fi
        rm -rf "$TEMP_DIR" "$ZIP_FILE"
    else
        echo "No logs (deleted, expired, or not a zip file)."
        rm -f "$ZIP_FILE"
    fi
done

echo "--- Unlimited Audit Complete ---"