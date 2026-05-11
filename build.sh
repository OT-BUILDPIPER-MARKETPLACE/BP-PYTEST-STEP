#!/bin/bash
set -euo pipefail

source /opt/buildpiper/shell-functions/functions.sh
source /opt/buildpiper/shell-functions/log-functions.sh

###############################################
### DEBUG
###############################################
if [[ "${DEBUG:-false}" == "true" ]]; then
  set -x
fi

###############################################
### PATHS
###############################################
CODEBASE_LOCATION="${WORKSPACE}/${CODEBASE_DIR}"
REPORTS_DIR="${CODEBASE_LOCATION}/reports"

REPORT_FILE_JSON="${REPORTS_DIR}/pytest_report.json"
REPORT_FILE_CSV="${REPORTS_DIR}/pytest_report.csv"

###############################################
### EXECUTION DIRECTORY
###############################################
if [[ -z "${GLOBAL_TASK_ID:-}" ]]; then
    logErrorMessage "GLOBAL_TASK_ID not set"
    exit 1
fi

EXEC_DIR="/bp/execution_dir/${GLOBAL_TASK_ID}"
mkdir -p "${EXEC_DIR}"
chmod -R 777 "${EXEC_DIR}" 2>/dev/null || true

###############################################
### OUTPUT FILE
###############################################
PYTEST_OUTPUT_FILE="${PYTEST_OUTPUT_FILE:-${ACTIVITY_SUB_TASK_CODE}_output.json}"

###############################################
### EVENTS TRACKING
###############################################
EVENTS='{}'

add_event() {
  local key="${1:-}"
  local status="${2:-}"
  local reason="${3:-}"
  local message="${4:-}"

  if [[ -z "$key" || -z "$status" ]]; then
    echo "Error: add_event requires key and status" >&2
    return 1
  fi

  key="$(echo "$key" \
      | tr '_' ' ' \
      | tr '-' ' ' \
      | tr '[:upper:]' '[:lower:]')"

  EVENTS=$(jq \
    --arg k "$key" \
    --arg status "$status" \
    --arg reason "$reason" \
    --arg message "$message" \
    '. + {
      ($k): {
        status: $status,
        reason: $reason,
        message: $message
      }
    }' <<< "$EVENTS")
}

###############################################
### INITIALIZATION
###############################################
STATUS=0

logInfoMessage "========================================="
logInfoMessage "Starting Pytest Scan"
logInfoMessage "========================================="

add_event "start pytest scan" "Successful" \
"Pytest scan started" \
"Initializing pytest execution"

###############################################
### CREATE REPORT DIRECTORY
###############################################
mkdir -p "${REPORTS_DIR}"

chmod -R 777 "${CODEBASE_LOCATION}" "${REPORTS_DIR}" 2>/dev/null || true

logInfoMessage "REPORTS_DIR=${REPORTS_DIR}"

add_event "create reports dir" "Successful" \
"Reports directory created" \
"Created ${REPORTS_DIR}"

###############################################
### CHANGE DIRECTORY
###############################################
cd "${CODEBASE_LOCATION}" || {

    logErrorMessage "Unable to access ${CODEBASE_LOCATION}"

    add_event "change directory" "Failed" \
    "Directory change failed" \
    "Unable to access ${CODEBASE_LOCATION}"

    generateOutput "${ACTIVITY_SUB_TASK_CODE}" false \
    "Unable to access ${CODEBASE_LOCATION}"

    exit 1
}

add_event "change directory" "Successful" \
"Directory changed" \
"Changed to ${CODEBASE_LOCATION}"

###############################################
### INSTALL DEPENDENCIES
###############################################
logInfoMessage "Installing pytest dependencies"

if [[ -f "${CODEBASE_LOCATION}/requirements.txt" ]]; then
    pip install -r "${CODEBASE_LOCATION}/requirements.txt" || true
fi

if ! pip install --no-cache-dir pytest pytest-json-report pytest-cases jq >/dev/null 2>&1; then

    logErrorMessage "Unable to install pytest dependencies"

    add_event "install dependencies" "Failed" \
    "Dependency installation failed" \
    "Unable to install pytest packages"

    generateOutput "${ACTIVITY_SUB_TASK_CODE}" false \
    "Unable to install pytest dependencies"

    exit 1
fi

add_event "install dependencies" "Successful" \
"Dependencies installed" \
"Installed pytest pytest-json-report pytest-cases jq"

###############################################
### RUN PYTEST
###############################################
logInfoMessage "Running pytest scan"

set +e

pytest \
  --maxfail=1 \
  --disable-warnings \
  -q \
  --json-report \
  --json-report-file="${REPORT_FILE_JSON}"

PYTEST_EXIT_CODE=$?

set -e

chmod 777 "${REPORT_FILE_JSON}" 2>/dev/null || true

###############################################
### VERIFY JSON REPORT
###############################################
if [[ -s "${REPORT_FILE_JSON}" ]]; then

    logInfoMessage "Pytest JSON report generated at ${REPORT_FILE_JSON}"

    add_event "generate json report" "Successful" \
    "JSON report generated" \
    "Generated ${REPORT_FILE_JSON}"

else

    logWarningMessage "Pytest did not produce any output"

    add_event "generate json report" "Failed" \
    "JSON report empty" \
    "Pytest generated empty report"

    echo '{"tests":[]}' > "${REPORT_FILE_JSON}"
fi

###############################################
### CHECK TEST DISCOVERY
###############################################
TEST_COUNT=$(jq '.tests | length' "${REPORT_FILE_JSON}" 2>/dev/null || echo 0)

if [[ "${TEST_COUNT}" -eq 0 ]]; then

    logWarningMessage "No test cases found"

    add_event "detect test cases" "Failed" \
    "No test cases found" \
    "Pytest discovered zero test cases"

else

    add_event "detect test cases" "Successful" \
    "Test cases discovered" \
    "Detected ${TEST_COUNT} test case(s)"
fi

###############################################
### GENERATE CSV REPORT
###############################################
echo "test_name,outcome,duration_sec,nodeid,message" > "${REPORT_FILE_CSV}"

jq -r '
  .tests[]? | [
    (.name // ""),
    (.outcome // ""),
    (.duration // 0),
    (.nodeid // ""),
    (
      (
        .longrepr // .call.longrepr // ""
      )
      | tostring
      | gsub("\n"; " ")
      | gsub("\""; "'\''")
    )
  ] | @csv
' "${REPORT_FILE_JSON}" >> "${REPORT_FILE_CSV}" || true

chmod 777 "${REPORT_FILE_CSV}" 2>/dev/null || true

###############################################
### VERIFY CSV REPORT
###############################################
if [[ -s "${REPORT_FILE_CSV}" ]]; then

    logInfoMessage "Pytest CSV report generated at ${REPORT_FILE_CSV}"

    add_event "generate csv report" "Successful" \
    "CSV report generated" \
    "Generated ${REPORT_FILE_CSV}"

else

    logWarningMessage "CSV conversion failed"

    add_event "generate csv report" "Failed" \
    "CSV generation failed" \
    "Unable to generate CSV report"
fi

###############################################
### PARSE RESULTS
###############################################
PASSED_COUNT=$(jq '[.tests[]? | select(.outcome=="passed")] | length' "${REPORT_FILE_JSON}" 2>/dev/null || echo 0)

FAILED_COUNT=$(jq '[.tests[]? | select(.outcome=="failed")] | length' "${REPORT_FILE_JSON}" 2>/dev/null || echo 0)

SKIPPED_COUNT=$(jq '[.tests[]? | select(.outcome=="skipped")] | length' "${REPORT_FILE_JSON}" 2>/dev/null || echo 0)

ERROR_COUNT=$(jq '[.tests[]? | select(.outcome=="error")] | length' "${REPORT_FILE_JSON}" 2>/dev/null || echo 0)

TOTAL_COUNT=$(jq '.tests | length' "${REPORT_FILE_JSON}" 2>/dev/null || echo 0)

###############################################
### HANDLE PYTEST COLLECTION ERRORS
###############################################
COLLECT_ERRORS=$(jq '.summary.collected // 0' "${REPORT_FILE_JSON}" 2>/dev/null || echo 0)

if [[ "${PYTEST_EXIT_CODE}" -ne 0 && "${FAILED_COUNT}" -eq 0 && "${ERROR_COUNT}" -eq 0 ]]; then
    ERROR_COUNT=1
fi

add_event "parse scan results" "Successful" \
"Metrics extracted" \
"TOTAL=${TOTAL_COUNT} PASSED=${PASSED_COUNT} FAILED=${FAILED_COUNT} ERROR=${ERROR_COUNT}"

###############################################
### COPY REPORTS TO EXECUTION DIRECTORY
###############################################
logInfoMessage "Copying reports to execution directory"

cp -f "${REPORT_FILE_JSON}" "${EXEC_DIR}/" 2>/dev/null || true
cp -f "${REPORT_FILE_CSV}" "${EXEC_DIR}/" 2>/dev/null || true

chmod -R 777 "${EXEC_DIR}" 2>/dev/null || true

add_event "copy reports" "Successful" \
"Reports copied" \
"Copied reports to ${EXEC_DIR}"

###############################################
### FINAL STATUS
###############################################
FINAL_MESSAGE="TOTAL=${TOTAL_COUNT} PASSED=${PASSED_COUNT} FAILED=${FAILED_COUNT} SKIPPED=${SKIPPED_COUNT} ERROR=${ERROR_COUNT}"

if [[ "${PYTEST_EXIT_CODE}" -ne 0 || \
      "${FAILED_COUNT}" -gt 0 || \
      "${ERROR_COUNT}" -gt 0 || \
      "${TEST_COUNT}" -eq 0 ]]; then

    FINAL_STATUS="Failed"

    add_event "pytest scan summary" "Failed" \
    "Pytest failures detected" \
    "${FINAL_MESSAGE}"

else

    FINAL_STATUS="Successful"

    add_event "pytest scan summary" "Successful" \
    "Pytest completed successfully" \
    "${FINAL_MESSAGE}"
fi

###############################################
### ERROR EVENTS
###############################################
ERROR_EVENTS=$(echo "$EVENTS" | jq '
[
  to_entries[]
  | select(.value.status == "Failed")
  | .key
]')

###############################################
### OUTPUT JSON
###############################################
jq -n \
  --argjson events "$EVENTS" \
  --argjson error_events "$ERROR_EVENTS" \
  --arg status "$FINAL_STATUS" \
  --arg message "$FINAL_MESSAGE" \
  --arg total "$TOTAL_COUNT" \
  --arg passed "$PASSED_COUNT" \
  --arg failed "$FAILED_COUNT" \
  --arg skipped "$SKIPPED_COUNT" \
  --arg errors "$ERROR_COUNT" \
  --arg pytest_exit_code "$PYTEST_EXIT_CODE" \
'{
  build: {
    status: ($status == "Successful"),
    message: $message,
    events: $events,
    error_events: $error_events
  },
  output_vars: {
    pytest_scan: {
      status: $status,
      message: $message,
      pytest_exit_code: ($pytest_exit_code|tonumber),
      tests: {
        total: ($total|tonumber),
        passed: ($passed|tonumber),
        failed: ($failed|tonumber),
        skipped: ($skipped|tonumber),
        errors: ($errors|tonumber)
      }
    }
  }
}' > "${EXEC_DIR}/${PYTEST_OUTPUT_FILE}"

chmod 777 "${EXEC_DIR}/${PYTEST_OUTPUT_FILE}" 2>/dev/null || true

logInfoMessage "Output written -> ${EXEC_DIR}/${PYTEST_OUTPUT_FILE}"

###############################################
### FINAL SUMMARY
###############################################
logInfoMessage "========================================="
logInfoMessage "Pytest Scan Summary"
logInfoMessage "========================================="
logInfoMessage "${FINAL_MESSAGE}"

if [[ "${STATUS}" -eq 0 ]]; then
    logInfoMessage "Pytest scan completed successfully"
else
    logWarningMessage "Pytest issues detected"
fi

saveTaskStatus "${STATUS}" "${ACTIVITY_SUB_TASK_CODE}"

exit 0