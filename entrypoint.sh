#!/bin/bash
set -e

usage_docs() {
  echo ""
  echo "You can use this Github Action with:"
  echo "- uses: convictional/trigger-workflow-and-wait"
  echo "  with:"
  echo "    owner: keithconvictional"
  echo "    repo: myrepo"
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

  inputs=$(echo '{}' | jq)
  if [ "${INPUT_INPUTS}" ]
  then
    inputs=$(echo "${INPUT_INPUTS}" | jq)
  fi

  ref="main"
  if [ "$INPUT_REF" ]
  then
    ref="${INPUT_REF}"
  fi

  max_count=180
  wait_timeout=$(echo ${max_count}*${wait_interval} | bc)
}

trigger_workflow() {
  echo "${GITHUB_API_URL}/repos/${INPUT_OWNER}/${INPUT_REPO}/actions/workflows/${INPUT_WORKFLOW_FILE_NAME}/dispatches"
  curl -4sL --show-error --fail -X POST "${GITHUB_API_URL}/repos/${INPUT_OWNER}/${INPUT_REPO}/actions/workflows/${INPUT_WORKFLOW_FILE_NAME}/dispatches" \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${INPUT_GITHUB_TOKEN}" \
    --data "{\"ref\":\"${ref}\",\"inputs\":${inputs}}"
  echo "== Sleeping for 10 seconds before start checking"
  sleep 10
}

wait_for_workflow_to_finish() {
  # Find the id of the last run using filters to identify the workflow triggered by this action
  echo "== Getting the ID of the workflow..."
  workflow_id=$(curl -4sL --show-error --fail -X GET \
    -H 'Accept: application/vnd.github.v3+json' \
    -H "Authorization: Bearer ${INPUT_GITHUB_TOKEN}" \
    "${GITHUB_API_URL}/repos/${INPUT_OWNER}/${INPUT_REPO}/actions/workflows" \
    | jq -r '.workflows[] | select (.path==".github/workflows/'${INPUT_WORKFLOW_FILE_NAME}'") | .id' \
  )

  last_workflow=""; count=0
  while [[ "${last_workflow}" == "" ]]; do

    echo "== Using the following params to filter the workflow runs to get the triggered run id."
    echo "== Workflow id: ${workflow_id}"
    echo "== Will check status every \"${wait_interval}\" seconds"

    last_workflow=$(curl -4sL --show-error --fail -X GET \
      -H 'Accept: application/vnd.github.v3+json' \
      -H "Authorization: Bearer ${INPUT_GITHUB_TOKEN}" \
      "${GITHUB_API_URL}/repos/${INPUT_OWNER}/${INPUT_REPO}/actions/workflows/${INPUT_WORKFLOW_FILE_NAME}/runs" \
      | jq -r '.workflow_runs[] | select ((.event=="'"workflow_dispatch"'") and (.workflow_id=='${workflow_id}') and (.status=="'"queued"'"))' \
    )

    count=$(($count+1))
    [ ${count} -ge ${max_count} ] && echo "ERR: timeout ${wait_timeout}s is reached" && exit 1

    if [[ "$last_workflow" == "" ]]; then
      sleep ${wait_interval}
    fi

  done
  last_workflow_id=$(echo "${last_workflow}" | jq '.id')
  last_workflow_url="${GITHUB_SERVER_URL}/${INPUT_OWNER}/${INPUT_REPO}/actions/runs/${last_workflow_id}"
  echo "== The workflow run id is [${last_workflow_id}]."
  echo "== The workflow logs can be found at ${last_workflow_url}"
  echo "::set-output name=workflow_id::${last_workflow_id}"
  echo "::set-output name=workflow_url::${last_workflow_url}"
  echo ""
  conclusion=$(echo "${last_workflow}" | jq '.conclusion')
  status=$(echo "${last_workflow}" | jq '.status')

  while [[ "${conclusion}" == "null" && "${status}" != "\"completed\"" ]]
  do
    sleep "${wait_interval}"
    workflow=$(curl -4sL --show-error --fail -X GET "${GITHUB_API_URL}/repos/${INPUT_OWNER}/${INPUT_REPO}/actions/workflows/${INPUT_WORKFLOW_FILE_NAME}/runs" \
      -H 'Accept: application/vnd.github.v3+json' \
      -H "Authorization: Bearer ${INPUT_GITHUB_TOKEN}" | jq '.workflow_runs[] | select(.id == '${last_workflow_id}')')
    conclusion=$(echo "${workflow}" | jq '.conclusion')
    status=$(echo "${workflow}" | jq '.status')
    echo "== Status is [${status}]"
  done

  if [[ "${conclusion}" == "\"success\"" && "${status}" == "\"completed\"" ]]
  then
    echo "== Success. All done!"
  else
    # Alternative "failure"
    echo "== Conclusion is not success, its [${conclusion}]."
    if [ "${propagate_failure}" = true ]
    then
      echo "== Propagating failure to upstream job"
      exit 1
    fi
  fi
}

main() {
  validate_args

  if [ "${trigger_workflow}" = true ]
  then
    trigger_workflow
  else
    echo "== Skipping triggering the workflow."
  fi

  if [ "${wait_workflow}" = true ]
  then
    wait_for_workflow_to_finish
  else
    echo "== Skipping waiting for workflow."
  fi
}

main
