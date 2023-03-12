#!/bin/bash

source functions.sh
source log-functions.sh
source str-functions.sh
source file-functions.sh
source aws-functions.sh

CODE="$WORKSPACE/$CODEBASE_DIR"

logInfoMessage "I'll run pytest on the test suite for $CODE to ensure that all functionality is working as expected.."
sleep $SLEEP_DURATION

if [ -d "reports" ]; then
   true
else
   mkdir reports
fi

if [ -d $CODE ]; then
    logInfoMessage "Executing command"
    logInfoMessage "pytest --color=yes --code-highlight=yes --show-capture=all --junit-xml=reports/$OUTPUT_ARG"
    cd $CODE
    pytest --color=yes --code-highlight=yes --show-capture=all  --junit-xml=reports/$OUTPUT_ARG

exit_code=$?

    if [ $exit_code -ne 0 ]; then
        if [ "$VALIDATION_FAILURE_ACTION" == "FAILURE" ]
        then
            logErrorMessage "Pytest unit test failed! Please review the error messages and update the code as necessary."
            generateOutput $ACTIVITY_SUB_TASK_CODE false "pytest tests failed! Please review the error messages and update the code as necessary."
            logErrorMessage "Please review the Pytest report for more information."
            exit 1
        else
            logErrorMessage "Pytest unit test failed! Please review the error messages and update the code as necessary."
            generateOutput $ACTIVITY_SUB_TASK_CODE false "Pytest unit test failed! Please review the error messages and update the code as necessary."
            logWarningMessage "Please review the Pytest report for more information."
        fi
    else
        logInfoMessage "Congratulations Pytest unit test succeeded."
        generateOutput $ACTIVITY_SUB_TASK_CODE true "Congratulations Pytest unit test succeeded."
    fi
else
    logErrorMessage "$CODE: Codebase directory is not found"
    generateOutput $ACTIVITY_SUB_TASK_CODE false "$CODE Codebase directory is not found."
    logErrorMessage "Please check the Git repository Pytest unit test failed.!!!"
fi




