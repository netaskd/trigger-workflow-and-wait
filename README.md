# Trigger Workflow and Wait

Github Action for trigger a workflow from another workflow. The action then waits for a response.

**When would you use it?**

When deploying an app you may need to deploy additional services, this Github Action helps with that.


## Arguments

| Argument Name         | Required   | Default     | Description           |
| --------------------- | ---------- | ----------- | --------------------- |
| `owner`               | True       | N/A         | The owner of the repository where the workflow is contained. |
| `repo`                | True       | N/A         | The repository where the workflow is contained. |
| `github_token`        | True       | N/A         | The Github access token with access to the repository. Its recommended you put it under secrets. |
| `workflow_file_name`  | True       | N/A         | The reference point. For example, you could use main.yml. |
| `github_user`         | False      | N/A         | The name of the github user whose access token is being used to trigger the workflow. |
| `ref`                 | False      | main        | The reference of the workflow run. The reference can be a branch, tag, or a commit SHA. |
| `wait_interval`    | False      | 10          | The number of seconds delay between checking for result of run. |
| `inputs`              | False      | `{}`        | Inputs to pass to the workflow, must be a JSON string |
| `propagate_failure`   | False      | `true`      | Fail current job if downstream job fails. |
| `trigger_workflow`    | False      | `true`      | Trigger the specified workflow. |
| `wait_workflow`       | False      | `true`      | Wait for workflow to finish. |
| `trigger_event`       | False      | `false`     | Trigger the specified event. |
| `event_payload`       | False      | `{}`        | Payload to pass to the repository_event, must be a JSON string |
| `event_type`          | False      | deploy      | The type of event to pass to the repository_event |

## Example

### Simple

Trigger workflow and wait the workflow

```yaml
- uses: netaskd/trigger-workflow-and-wait@master
  with:
    owner: netaskd
    repo: my-repo
    github_token: ${{ secrets.GITHUB_PERSONAL_ACCESS_TOKEN }}
```

Trigger event and wait the latest workflow

```yaml
- uses: netaskd/trigger-workflow-and-wait@master
  with:
    owner: netaskd
    repo: my-repo
    trigger_event: true
    event_type: deploy
    event_payload: '{}'
    trigger_workflow: false
    wait_workflow: true
    workflow_file_name: main.yml
    github_token: ${{ secrets.GITHUB_PERSONAL_ACCESS_TOKEN }}
```

### All Options

```yaml
- uses: netaskd/trigger-workflow-and-wait@master
  with:
    owner: netaskd
    repo: my-repo
    github_token: ${{ secrets.GITHUB_PERSONAL_ACCESS_TOKEN }}
    github_user: github-user
    workflow_file_name: main.yml
    ref: release-branch
    wait_interval: 10
    inputs: '{}'
    propagate_failure: false
    trigger_workflow: true
    trigger_event: false
    wait_workflow: true
```


## Testing

You can test out the action locally by cloning the repository to your computer. You can run:

```shell
  INPUT_WAITING_INTERVAL=10 \
  INPUT_PROPAGATE_FAILURE=false \
  INPUT_TRIGGER_WORKFLOW=true \
  INPUT_WORKFLOW_FILE_NAME="main.yml" \
  INPUT_GITHUB_USER="github-user" \
  INPUT_WAIT_WORKFLOW=true \
  INPUT_OWNER="keithconvictional" \
  INPUT_REPO="trigger-workflow-and-wait-example-repo1" \
  INPUT_GITHUB_TOKEN="<REDACTED>" \
  INPUT_INPUTS='{}' \
  bash entrypoint.sh
```

You will have to create a Github Personal access token. You can create a test workflow to be executed. In a repository, add a new `main.yml` to `.github/workflows/`. The workflow will be:

```shell
name: Main
on:
  workflow_dispatch
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@master
      - name: Pause for 25 seconds
        run: |
          sleep 25
```

You can see the example [here](https://github.com/keithconvictional/trigger-workflow-and-wait-example-repo1/blob/master/.github/workflows/main.yml). For testing a failure case, just add this line after the sleep:

```yaml
...
- name: Pause for 25 seconds
  run: |
    sleep 25
    echo "For testing failure"
    exit 1
```

## Potential Issues

### Timing

The actions dispatch is an asynchronous job and it at times can take a few seconds to start. If you do not have a delay, it may be started after the action has checked if it was successful. ie. Start dispatch call --> No delay --> Check if successful --> Actually starts. If the workflow has run before, it will just complete immediately as a successful run. You can solve this by simply increasing the delay to a few seconds. By default it is 10 seconds. Creating a large delay between checks will help the traffic to the Github API.

### Changes

If you do not want the latest build all of the time, please use a versioned copy of the Github Action. You specify the version after the `@` sign.

```yaml
- uses: netaskd/trigger-workflow-and-wait@master
  with:
    owner: netaskd
    repo: my-repo
    github_token: ${{ secrets.GITHUB_PERSONAL_ACCESS_TOKEN }}
```
