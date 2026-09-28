#!/bin/bash

# ==============================================================================
# Load BuildPiper Base Functions
# ==============================================================================
source /opt/buildpiper/shell-functions/functions.sh
source /opt/buildpiper/shell-functions/mi-functions.sh
source /opt/buildpiper/shell-functions/log-functions.sh
source /opt/buildpiper/shell-functions/file-functions.sh
source /opt/buildpiper/shell-functions/str-functions.sh
source /opt/buildpiper/shell-functions/getDataFile.sh

# ==============================================================================
# Debug
# ==============================================================================
if [ "${DEBUG:-false}" = true ]; then
    set -x
fi

# ==============================================================================
# Environment Setup
# ==============================================================================
WORKSPACE="${WORKSPACE:-/bp/workspace}"

CODEBASE_LOCATION="${WORKSPACE}/${CODEBASE_DIR}"

REPORTS_DIR="${CODEBASE_LOCATION}/reports"

JUNIT_REPORT="${REPORTS_DIR}/${OUTPUT_ARG:-pytest.xml}"
CONSOLE_LOG="${REPORTS_DIR}/pytest_console.log"
REPORT_CSV="${REPORTS_DIR}/pytest_summary.csv"

TASK_STATUS=0
MI_SEND_STATUS=0

# ==============================================================================
# Environment / Service Information
# ==============================================================================
environment="${PROJECT_ENV_NAME:-$(getProjectEnv 2>/dev/null)}"
service="${COMPONENT_NAME:-$(getServiceName 2>/dev/null)}"

logInfoMessage "Pytest environment: ${environment}"
logInfoMessage "Pytest service: ${service}"
logInfoMessage "Codebase location: ${CODEBASE_LOCATION}"

sleep "${SLEEP_DURATION:-0s}"

if [ ! -d "${CODEBASE_LOCATION}" ]; then

    logErrorMessage "${CODEBASE_LOCATION}: Codebase directory is not found"
    generateOutput "${ACTIVITY_SUB_TASK_CODE}" false "${CODEBASE_LOCATION} Codebase directory is not found."
    exit 1

fi

mkdir -p "${REPORTS_DIR}"

# ==============================================================================
# Create Execution Directory
# ==============================================================================
if [ -n "${GLOBAL_TASK_ID:-}" ]; then

    EXEC_DIR="/bp/execution_dir/${GLOBAL_TASK_ID}"

    mkdir -p "${EXEC_DIR}"

    logInfoMessage "Execution directory created: ${EXEC_DIR}"

else

    logErrorMessage "GLOBAL_TASK_ID is not set. Cannot create execution directory."
    exit 1

fi

# ==============================================================================
# CSV Locations
# ==============================================================================
#
# Summary CSV (sent to MI):
#
#   ${EXEC_DIR}/pytest_summary.csv
#
# This file contains ONLY:
#
#   PASSED,FAILED,SKIPPED,ERRORS,WARNINGS,TOTAL
#   2,1,1,0,1,4
#
# A copy is also kept at ${REPORTS_DIR}/pytest_summary.csv
#
# ==============================================================================

SUMMARY_CSV="${EXEC_DIR}/pytest_summary.csv"

logInfoMessage "Pytest summary CSV path: ${SUMMARY_CSV}"

# ==============================================================================
# Step 1: Run Pytest
# ==============================================================================

logInfoMessage "Running pytest on ${CODEBASE_LOCATION}..."
logInfoMessage "pytest --color=yes --code-highlight=yes --show-capture=all --junit-xml=${JUNIT_REPORT}"

cd "${CODEBASE_LOCATION}" || exit 1

pytest --color=yes --code-highlight=yes --show-capture=all \
    --junit-xml="${JUNIT_REPORT}" 2>&1 | tee "${CONSOLE_LOG}"

PYTEST_EXIT_CODE=${PIPESTATUS[0]}

if [ "${PYTEST_EXIT_CODE}" -ne 0 ]; then

    logErrorMessage "Pytest unit test failed (exit code ${PYTEST_EXIT_CODE}). Please review the error messages and update the code as necessary."
    TASK_STATUS=1

else

    logInfoMessage "Congratulations Pytest unit test succeeded."

fi

# ==============================================================================
# Step 2: Generate Summary CSV
# ==============================================================================
#
# Counts are read from the final pytest summary line, e.g.
#
#   ===== 1 failed, 2 passed, 1 skipped, 1 warning in 0.04s =====
#
# Warnings are only available here (JUnit XML does not record them).
#
# ==============================================================================

logInfoMessage "Generating Pytest summary CSV..."

getPytestCount() {

    local keyword="$1"

    sed 's/\x1b\[[0-9;]*m//g' "${CONSOLE_LOG}" |
        grep -E '^=+ .* in [0-9.]+s' |
        tail -1 |
        grep -oE "[0-9]+ ${keyword}\b" |
        grep -oE '^[0-9]+' || echo 0
}

PASSED=$(getPytestCount "passed")
FAILED=$(getPytestCount "failed")
SKIPPED=$(getPytestCount "skipped")
ERRORS=$(getPytestCount "errors?")
WARNINGS=$(getPytestCount "warnings?")
TOTAL=$((PASSED + FAILED + SKIPPED + ERRORS))

{
    echo "PASSED,FAILED,SKIPPED,ERRORS,WARNINGS,TOTAL"
    echo "${PASSED},${FAILED},${SKIPPED},${ERRORS},${WARNINGS},${TOTAL}"
} > "${SUMMARY_CSV}"

cp "${SUMMARY_CSV}" "${REPORT_CSV}"

if [ -f "${SUMMARY_CSV}" ]; then

    logInfoMessage "Pytest summary CSV generated:"
    logInfoMessage "${SUMMARY_CSV}"

else

    logErrorMessage "Failed to generate Pytest summary CSV."

    MI_SEND_STATUS=1

fi

# ==============================================================================
# Step 2b: Generate Detailed CSV
# ==============================================================================
#
# One row per test case, built from the JUnit XML report:
#
#   filename,test_name,status,duration,message
#
# Sorted FAILED > ERROR > SKIPPED > PASSED. Used ONLY for display in the logs;
# MI receives the summary CSV.
#
# ==============================================================================

DETAILED_CSV="${REPORTS_DIR}/pytest_detailed_report.csv"

logInfoMessage "Generating Pytest detailed CSV report..."

export CODEBASE_LOCATION
export JUNIT_REPORT
export DETAILED_CSV

python3 <<'PYTHON'

import csv
import os
import re
import xml.etree.ElementTree as ET

codebase_location = os.environ["CODEBASE_LOCATION"]
junit_file = os.environ["JUNIT_REPORT"]
detailed_file = os.environ["DETAILED_CSV"]

STATUS_ORDER = {"FAILED": 0, "ERROR": 1, "SKIPPED": 2, "PASSED": 3}


def filename_from(testcase):

    # "tests.test_api.TestUsers" -> "/bp/workspace/<repo>/tests/test_api.py"
    parts = (testcase.get("classname") or "").split(".")

    if len(parts) > 1 and parts[-1][:1].isupper():
        parts = parts[:-1]

    if not parts or not parts[0]:
        return ""

    return os.path.normpath(os.path.join(codebase_location, "/".join(parts) + ".py"))


def clean(text):

    # Strip pytest --color codes (raw or XML-escaped as "#x1B")
    text = re.sub(r"(\x1b|#x1B)\[[0-9;]*m", "", text or "")

    # Double quotes break print_table.py's CSV sniffing (same as OWASP step)
    text = " ".join(text.split()).replace('"', "'")

    return text[:97] + "..." if len(text) > 100 else text


rows = []

try:

    for testcase in ET.parse(junit_file).getroot().iter("testcase"):

        status, message = "PASSED", ""

        for tag, name in (("failure", "FAILED"), ("error", "ERROR"), ("skipped", "SKIPPED")):

            result = testcase.find(tag)

            if result is not None:
                status = name
                message = result.get("message") or ""

                if not message and (result.text or "").strip():
                    message = result.text.strip().splitlines()[0]

                break

        rows.append([
            filename_from(testcase),
            testcase.get("name", ""),
            status,
            "{:.3f}".format(float(testcase.get("time") or 0)),
            clean(message),
        ])

except Exception as exc:

    print("Unable to read JUnit report {}: {}".format(junit_file, exc))


rows.sort(key=lambda r: (STATUS_ORDER[r[2]], r[0], r[1]))

with open(detailed_file, "w", newline="", encoding="utf-8") as f:

    writer = csv.writer(f)

    writer.writerow(["filename", "test_name", "status", "duration", "message"])

    writer.writerows(rows)

PYTHON

if [ -f "${DETAILED_CSV}" ]; then

    logInfoMessage "Pytest detailed CSV generated at:"
    logInfoMessage "${DETAILED_CSV}"

else

    logWarningMessage "Failed to generate Pytest detailed CSV."

fi

# ==============================================================================
# Step 3: Display Summary Table in Logs
# ==============================================================================

logInfoMessage "Pytest Summary"

echo "================================================================================"

python3 /opt/buildpiper/shell-functions/print_table.py \
    "${SUMMARY_CSV}" || {

    logWarningMessage "Unable to display formatted Pytest summary table."

    cat "${SUMMARY_CSV}"

}

echo "================================================================================"

# ==============================================================================
# Step 3b: Display Detailed Report in Logs
# ==============================================================================

if [ -f "${DETAILED_CSV}" ]; then

    logInfoMessage "Displaying Pytest Detailed Report"

    echo "================================================================================"

    python3 /opt/buildpiper/shell-functions/print_table.py \
        "${DETAILED_CSV}" || {

        logWarningMessage "Unable to display formatted Pytest detailed table."

    }

    echo "================================================================================"

fi

# ==============================================================================
# Step 4: Push Data to Maturity Index Server
# ==============================================================================
#
# IMPORTANT: MI receives the SUMMARY CSV (base64 encoded) as report_data.
#
# ==============================================================================

if [ -n "${MI_SERVER_ADDRESS:-}" ] &&
   [ "${MI_SEND_STATUS}" -eq 0 ]; then

    MI_SERVER_ADDRESS="${MI_SERVER_ADDRESS%/}"

    logInfoMessage "MI server configured: ${MI_SERVER_ADDRESS}"

    logInfoMessage "Preparing Summary report for MI upload"

    export base64EncodedResponse=$(encodeFileContent "${SUMMARY_CSV}" | tr -d '\n')

    export application="${APPLICATION_NAME}"
    export environment="${environment}"
    export service="${service}"
    export organization="${ORGANIZATION}"
    export source_key="${SOURCE_KEY:-pytest}"
    export report_file_path="${REPORT_FILE_PATH:-null}"

    MI_PAYLOAD="${REPORTS_DIR}/pytest.mi"

    generateMIDataJson \
        /opt/buildpiper/data/mi.template \
        "${MI_PAYLOAD}"

    logInfoMessage "Generated MI Payload"

    cat "${MI_PAYLOAD}"

    if ! jq empty "${MI_PAYLOAD}" >/dev/null 2>&1; then

        logErrorMessage "Generated MI payload is not valid JSON. Skipping MI push."

        MI_SEND_STATUS=1

    elif sendMIData \
        "${MI_PAYLOAD}" \
        "${MI_SERVER_ADDRESS}"; then

        logInfoMessage "Successfully pushed '${source_key}' metrics to MI server."

    else

        logErrorMessage "Failed to push '${source_key}' metrics to MI server."

        MI_SEND_STATUS=1

    fi

else

    if [ -z "${MI_SERVER_ADDRESS:-}" ]; then

        logWarningMessage "MI_SERVER_ADDRESS is not configured. Skipping Maturity Index data push."

    else

        logWarningMessage "Pytest summary is unavailable. Skipping Maturity Index data push."

    fi

fi

unset base64EncodedResponse

# ==============================================================================
# Step 5: Final Pipeline Status
# ==============================================================================

logInfoMessage "JUnit report available at: ${JUNIT_REPORT}"
logInfoMessage "Summary CSV available at: ${SUMMARY_CSV}"

if [ "${MI_SEND_STATUS}" -ne 0 ]; then

    logWarningMessage "Pytest completed, but MI metrics failed to send."

fi

saveTaskStatus \
    "${TASK_STATUS}" \
    "${ACTIVITY_SUB_TASK_CODE}"