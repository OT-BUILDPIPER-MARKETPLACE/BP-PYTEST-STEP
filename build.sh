#!/bin/bash
set -euo pipefail

# ==============================================================================
#  Determine Codebase and Reports Directory
# ==============================================================================
CODEBASE_LOCATION="${WORKSPACE}/${CODEBASE_DIR}"
REPORTS_DIR="${CODEBASE_LOCATION}/reports"
REPORT_FILE_JSON="${REPORTS_DIR}/pytest_report.json"
REPORT_FILE_CSV="${REPORTS_DIR}/pytest_report.csv"

# Ensure reports directory exists
mkdir -p "${REPORTS_DIR}"
chmod -R 777 "${REPORTS_DIR}" 2>/dev/null || true

# Navigate to codebase
cd "${CODEBASE_LOCATION}" || exit 1

# ==============================================================================
#  Install Dependencies
# ==============================================================================
pip install --no-cache-dir pytest pytest-json-report jq >/dev/null

# ==============================================================================
#  Run Pytest & Generate JSON
# ==============================================================================
pytest --maxfail=1 --disable-warnings -q \
       --json-report \
       --json-report-file="${REPORT_FILE_JSON}" || true

# Verify JSON report existence
if [ ! -s "${REPORT_FILE_JSON}" ]; then
    echo "Pytest did not produce any output."
    exit 0
fi

# ==============================================================================
#  Check if any test cases were discovered
# ==============================================================================
TEST_COUNT=$(jq '.tests | length' "${REPORT_FILE_JSON}")

if [ "${TEST_COUNT}" -eq 0 ]; then
    echo "WARNING: No test cases found — pytest did not produce any output."
fi

echo "Pytest JSON report generated at ${REPORT_FILE_JSON}"

# ==============================================================================
#  Convert JSON → CSV
# ==============================================================================
echo "test_name,outcome,duration_sec,nodeid,message" > "${REPORT_FILE_CSV}"

jq -r '
  .tests[]? | [
    (.name // ""),
    (.outcome // ""),
    (.duration // 0),
    (.nodeid // ""),
    ((.longrepr // .call.longrepr // "") 
        | tostring 
        | gsub("\n"; " ") 
        | gsub("\""; "'"'"'"))
  ] | @csv
' "${REPORT_FILE_JSON}" >> "${REPORT_FILE_CSV}"

# ==============================================================================
#  Validate CSV Creation
# ==============================================================================
if [ -s "${REPORT_FILE_CSV}" ]; then
    echo "Pytest CSV report generated at ${REPORT_FILE_CSV}"
else
    echo "CSV conversion failed or no test cases found."
fi

