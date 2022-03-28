#!/usr/bin/env bash
set -e

usage_docs() {
  echo ""
  echo "You can use this Github Action with:"
  echo "- uses: netaskd/trigger-workflow-and-wait"
  echo "  with:"
  echo "    owner: netaskd"
  echo "    repo: my-repo"
  echo "    github_token: \${{ secrets.GITHUB_PERSONAL_ACCESS_TOKEN }}"
  echo "    workflow_file_name: main.yaml"
}
GITHUB_API_URL="${API_URL:-https://api.github.com}"
GITHUB_SERVER_URL="${SERVER_URL:-https://github.com}"

validate_args() {
  wait_interval=10 # Waits for 10 seconds
  if [ "${INPUT_WAIT_INTERVAL}" ]
  then
    wait_interval=${INPUT_WAIT_INTERVAL}
  fi

  propagate_failure=true
  if [ -n "${INPUT_PROPAGATE_FAILURE}" ]
  then
    propagate_failure=${INPUT_PROPAGATE_FAILURE}
  fi

  trigger_event=false
  if [ -n "${INPUT_TRIGGER_EVENT}" ]
  then
    trigger_event=${INPUT_TRIGGER_EVENT}
  fi

  trigger_workflow=true
  if [ -n "${INPUT_TRIGGER_WORKFLOW}" ]
  then
    trigger_workflow=${INPUT_TRIGGER_WORKFLOW}
  fi

  wait_workflow=true
  if [ -n "${INPUT_WAIT_WORKFLOW}" ]
  then
    wait_workflow=${INPUT_WAIT_WORKFLOW}
  fi

  last_workflow_interval=0
  if [ -n "${INPUT_LAST_WORKFLOW_INTERVAL}" ]
  then
    last_workflow_interval=${INPUT_LAST_WORKFLOW_INTERVAL}
  fi

  if [ -z "${INPUT_OWNER}" ]
  then
    echo "== Error: Owner is a required argument."
    usage_docs
    exit 1
  fi

  if [ -z "${INPUT_REPO}" ]
  then
    echo "== Error: Repo is a required argument."
    usage_docs
    exit 1
  fi

  if [ -z "${INPUT_GITHUB_TOKEN}" ]
  then
    echo "== Error: Github token is required. You can head over settings and"
    echo "under developer, you can create a personal access tokens. The"
    echo "token requires repo access."
    usage_docs
    exit 1
  fi

  if [ -z "${INPUT_WORKFLOW_FILE_NAME}" ]
  then
    echo "== Error: Workflow File Name is required"
    usage_docs
    exit 1
  fi

  client_payload=$(echo '{}' | jq)
  if [ "${INPUT_CLIENT_PAYLOAD}" ]
  then
    client_payload=$(echo "${INPUT_CLIENT_PAYLOAD}" | jq)
  fi

  ref="main"
  if [ "$INPUT_REF" ]
  then
    ref="${INPUT_REF}"
  fi

  event_type="deploy"
  if [ "$INPUT_EVENT_TYPE" ]
  then
    event_type="${INPUT_EVENT_TYPE}"
  fi

  event_payload=$(echo '{}' | jq)
  if [ "${INPUT_EVENT_PAYLOAD}" ]
  then
    event_payload=$(echo "${INPUT_EVENT_PAYLOAD}" | jq)
  fi
}

trigger_event() {
  echo "Send event ${event_type} to ${GITHUB_API_URL}/repos/${INPUT_OWNER}/${INPUT_REPO}/dispatches"
  curl -4sL --show-error --fail -X POST "${GITHUB_API_URL}/repos/${INPUT_OWNER}/${INPUT_REPO}/dispatches" \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${INPUT_GITHUB_TOKEN}" \
    --data "{\"event_type\":\"${event_type}\",\"event_payload\":${event_payload}}"
  echo "== Sleeping for 10 seconds before start checking"
  sleep 10
}

api() {
  path=$1; shift
  if response=$(curl --fail-with-body -sSL \
      "${GITHUB_API_URL}/repos/${INPUT_OWNER}/${INPUT_REPO}/actions/$path" \
      -H "Authorization: Bearer ${INPUT_GITHUB_TOKEN}" \
      -H 'Accept: application/vnd.github.v3+json' \
      -H 'Content-Type: application/json' \
      "$@")
  then
    echo "$response"
  else
    echo >&2 "api failed:"
    echo >&2 "path: $path"
    echo >&2 "response: $response"
    exit 1
  fi
}

# Return the ids of the most recent workflow runs, optionally filtered by user
get_workflow_runs() {
  since=${1:?}

  query="event=workflow_dispatch&created=>=$since${INPUT_GITHUB_USER+&actor=}${INPUT_GITHUB_USER}&per_page=100"

  echo "Getting workflow runs using query: ${query}" >&2

  api "workflows/${INPUT_WORKFLOW_FILE_NAME}/runs?${query}" |
  jq '.workflow_runs[].id' |
  sort # Sort to ensure repeatable order, and lexicographically for compatibility with join
}

trigger_workflow() {
  START_TIME=$(date +%s)
  SINCE=$(date -u -Iseconds -d "@$((START_TIME - 120))") # Two minutes ago, to overcome clock skew

  OLD_RUNS=$(get_workflow_runs "$SINCE")

  echo >&2 "Triggering workflow:"
  echo >&2 "  workflows/${INPUT_WORKFLOW_FILE_NAME}/dispatches"
  echo >&2 "  {\"ref\":\"${ref}\",\"inputs\":${client_payload}}"

  api "workflows/${INPUT_WORKFLOW_FILE_NAME}/dispatches" \
    --data "{\"ref\":\"${ref}\",\"inputs\":${client_payload}}"

  NEW_RUNS=$OLD_RUNS
  while [ "$NEW_RUNS" = "$OLD_RUNS" ]; do
    echo >&2 "Sleeping for ${wait_interval} seconds"
    sleep "$wait_interval"
    NEW_RUNS=$(get_workflow_runs "$SINCE")
  done

  # Return new run ids
  join -v2 <(echo "$OLD_RUNS") <(echo "$NEW_RUNS")
}

wait_for_workflow_to_finish() {
  last_workflow_id=${1:?}
  last_workflow_url="${GITHUB_SERVER_URL}/${INPUT_OWNER}/${INPUT_REPO}/actions/runs/${last_workflow_id}"
  echo "== The workflow id is [${last_workflow_id}]."
  echo "== The workflow logs can be found at ${last_workflow_url}"
  echo "::set-output name=workflow_id::${last_workflow_id}"
  echo "::set-output name=workflow_url::${last_workflow_url}"
  echo ""

  conclusion=null
  status=

  while [[ "${conclusion}" == "null" && "${status}" != "completed" ]]; do
    sleep "${wait_interval}"
    workflow=$(api "runs/$last_workflow_id")
    conclusion=$(echo "${workflow}" | jq -r '.conclusion')
    status=$(echo "${workflow}" | jq -r '.status')    
    echo "== Status is [${status}]"
  done

  if [[ "${conclusion}" == "success" && "${status}" == "completed" ]]; then
    echo "== Success. All done!"
  else
    # Alternative "failure"
    echo "== Conclusion is not success, its [${conclusion}]."
    if [ "${propagate_failure}" = true ]; then
      echo "== Propagating failure to upstream job"
      exit 1
    fi
  fi
}

main() {
  validate_args

  if [ "${trigger_workflow}" = true ]
  then
    run_ids=$(trigger_workflow)
  else
    echo "== Skipping triggering the workflow."
  fi

  if [ "${trigger_event}" = true ]
  then
    trigger_event
  else
    echo "== Skipping triggering the event."
  fi

  if [ "${wait_workflow}" = true ]
  then
    for run_id in $run_ids
    do
      wait_for_workflow_to_finish "$run_id"
    done
  else
    echo "== Skipping waiting for workflow."
  fi
}

main
