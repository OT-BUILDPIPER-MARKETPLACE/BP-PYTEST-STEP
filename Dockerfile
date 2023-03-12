FROM python:3.9-slim-buster
RUN apt-get update && apt-get install -y jq && rm -rf /var/lib/apt/lists/*
RUN pip install pytest
COPY build.sh .
COPY BP-BASE-SHELL-STEPS .
RUN chmod +x build.sh
ENV ACTIVITY_SUB_TASK_CODE BP-BANDIT-TASK
ENV SLEEP_DURATION 0s
ENV VALIDATION_FAILURE_ACTION WARNING
ENV OUTPUT_ARG="pytest.xml"
ENTRYPOINT [ "./build.sh" ]

