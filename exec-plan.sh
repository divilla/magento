#!/usr/bin/env bash
# Run one fresh Codex session per task; durable handoffs live in the repository.
set -euo pipefail
umask 077

usage() {
    cat <<'EOF'
Usage: ./exec-plan.sh [options]

Implement APIH-REST-PLAN.md, one task per fresh codex exec session.
Completed tasks are skipped on subsequent runs when their saved result and
progress entry agree. Blocked domain tasks are recorded and execution continues;
task 01 must complete before later tasks can run.

Options:
  --from NN             First task (default: 01)
  --to NN               Last task (default: 27)
  --attempts N          Maximum fresh-session attempts per task (default: 2)
  --model NAME          Override the configured Codex model
  --profile NAME        Use a Codex configuration profile
  --stop-on-blocked     Stop at the first blocked task
  --dry-run             Show tasks and prompts without invoking Codex or writing files
  -h, --help            Show this help

Requires: bash, codex, jq, flock, sha256sum, and existing Codex authentication.
Uses --approve-for-me (workspace sandbox with automatic approval review).
Logs and checkpoint results: var/apih-plan-exec/ (private, Git-ignored).
Exit codes: 0 = selected tasks complete; 1 = execution/validation failure;
            2 = blocked tasks remain; 130/143 = interrupted.
EOF
}

die() { printf 'exec-plan: %s\n' "$*" >&2; exit 1; }
task_number() {
    [[ $1 =~ ^[0-9]{1,2}$ ]] || die "Invalid task number: $1"
    local number=$((10#$1))
    ((number >= 1 && number <= 27)) || die "Task must be between 01 and 27: $1"
    printf '%s' "$number"
}

first=1
last=27
attempts=2
dry_run=false
stop_on_blocked=false
codex_options=()
while (($#)); do
    case $1 in
        --from|--to|--attempts|--model|--profile)
            (($# >= 2)) && [[ -n $2 ]] || die "Missing value for $1"
            case $1 in
                --from) first=$(task_number "$2") ;;
                --to) last=$(task_number "$2") ;;
                --attempts)
                    [[ $2 =~ ^[1-9][0-9]?$ ]] || die 'Attempts must be between 1 and 99'
                    attempts=$2 ;;
                --model|--profile) codex_options+=("$1" "$2") ;;
            esac
            shift 2 ;;
        --dry-run) dry_run=true; shift ;;
        --stop-on-blocked) stop_on_blocked=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown argument: $1 (see --help)" ;;
    esac
done
((first <= last)) || die '--from must be less than or equal to --to'

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
cd -- "$repo"
[[ -s APIH-REST-PLAN.md ]] || die "Missing plan in $repo"
progress="$repo/APIH-REST-PROGRESS.md"
state="$repo/var/apih-plan-exec"

progress_has_status() {
    [[ -s $progress ]] || return 1
    awk -F '|' -v id="$1" -v expected="$2" '
        { task=$2; status=$3; gsub(/^[[:space:]]+|[[:space:]]+$/, "", task);
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", status);
          if (task == id) { count++; if (status == expected) matching++ } }
        END { exit !(count == 1 && matching == 1) }
    ' "$progress"
}

valid_complete() {
    [[ -s $1 && -s apih-tests/coverage.md ]] || return 1
    jq -e --arg task "$2" '
        .task == $task and .status == "complete" and
        .validation_passed == true and .handoff_updated == true and
        (.summary | type == "string" and length > 0) and
        (.checks | type == "array" and length > 0) and
        all(.checks[]; (.command | type == "string" and length > 0) and
                      (.evidence | type == "string" and length > 0) and
                      .passed == true) and
        .blockers == []
    ' "$1" >/dev/null 2>&1 && progress_has_status "$2" complete
}

prompt_for() {
    cat <<EOF
Implement task $1, and only that task, from APIH-REST-PLAN.md in this fresh
Codex session. The Bash runner controls task sequencing; do not launch other
Codex sessions, agents, or exec-plan.sh, and do not implement the next task.

Read the plan, applicable repository instructions, APIH-REST-PROGRESS.md if
present, apih-tests/coverage.md, and the apih-build skill. Task 01 must create
the progress file with all 27 tasks. Its Markdown table must have Task and
Status as its first two columns, using two-digit IDs and the plain statuses
pending, in progress, complete, blocked. Preserve this format for the runner.

Verify prerequisites and current workspace changes. Preserve unrelated edits.
If this task is already marked complete, verify its implementation and required
checks before reporting success. Otherwise implement it and iterate on fixes
and checks until the plan's applicable completion criteria are satisfied.
Run the required focused and accumulated-suite checks against only the isolated
integration instance. Never weaken assertions or silently normalize behavior.
Never report checks as passed if they were not actually executed successfully.

This is unattended execution: resolve routine choices from the plan and repo.
If credentials, infrastructure, approvals, or prerequisite work prevent progress,
document the precise blocker and return status blocked. If required validation
fails and you cannot repair it, return failed. Do not ask a question and then
claim completion. Record demonstrated Magento defects and coverage gaps.

Before finishing, update APIH-REST-PROGRESS.md with changes, validation commands
and evidence/report paths, coverage, compatibility decisions, blockers, and the
next eligible task. Update apih-tests/coverage.md with verified results and gaps.
Keep credentials and tokens out of output and reports; avoid printing existing
credential-bearing fixtures. Do not commit, push, or modify this runner or plan.

This is attempt $2 of $attempts. Previous attempts, if any, are in $3.
Use concise handoff notes and result JSON to recover relevant work; do not load
entire event logs into context. An interrupted task may have left partial edits.

Return the final JSON required by the provided output schema. Use task "$1".
Set status complete only if all applicable criteria passed and the progress row
is complete. List actual validation commands in checks. validation_passed must
be false if any required check failed or was not run. For blocked or failed
tasks, list the concrete reasons in blockers and update the progress row to
blocked. Stop after this task.
EOF
}

if $dry_run; then
    for ((number=first; number<=last; number++)); do
        printf -v task '%02d' "$number"
        printf '\n=== Task %s ===\n' "$task"
        prompt_for "$task" 1 "$state/task-$task"
    done
    exit 0
fi

for dependency in codex jq flock sha256sum; do
    command -v "$dependency" >/dev/null || die "Missing command: $dependency"
done
codex_help=$(codex exec --help 2>/dev/null) || die 'Cannot inspect codex exec'
for option in --approve-for-me --ephemeral --output-schema --output-last-message; do
    [[ $codex_help == *"$option"* ]] || die "Installed codex exec lacks $option; update Codex"
done

mkdir -p -- "$state"
exec 9>"$state/run.lock"
flock -n 9 || die 'Another exec-plan.sh run is active in this repository'
plan_hash=$(sha256sum APIH-REST-PLAN.md)
plan_hash=${plan_hash%% *}
schema="$state/result.schema.json"
cat > "$schema" <<'EOF'
{
  "type": "object",
  "additionalProperties": false,
  "properties": {
    "task": {"type": "string"},
    "status": {"type": "string", "enum": ["complete", "blocked", "failed"]},
    "summary": {"type": "string"},
    "validation_passed": {"type": "boolean"},
    "handoff_updated": {"type": "boolean"},
    "checks": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "properties": {
          "command": {"type": "string"},
          "passed": {"type": "boolean"},
          "evidence": {"type": "string"}
        },
        "required": ["command", "passed", "evidence"]
      }
    },
    "blockers": {"type": "array", "items": {"type": "string"}}
  },
  "required": ["task", "status", "summary", "validation_passed",
               "handoff_updated", "checks", "blockers"]
}
EOF

child_pid=''
interrupt() {
    trap '' INT TERM
    if [[ -n $child_pid ]]; then
        kill -TERM "$child_pid" 2>/dev/null || true
        wait "$child_pid" 2>/dev/null || true
    fi
    printf '\nInterrupted. Rerun ./exec-plan.sh to resume unfinished work.\n' >&2
    exit "$1"
}
trap 'interrupt 130' INT
trap 'interrupt 143' TERM

blocked_tasks=()
for ((number=first; number<=last; number++)); do
    printf -v task '%02d' "$number"
    task_dir="$state/task-$task"
    checkpoint="$task_dir/complete.json"
    if valid_complete "$checkpoint" "$task" &&
       jq -e --arg hash "$plan_hash" '.plan_sha256 == $hash' "$checkpoint" >/dev/null; then
        printf 'Task %s already complete; skipping.\n' "$task"
        continue
    fi

    mkdir -p -- "$task_dir"
    outcome=failed
    for ((attempt=1; attempt<=attempts; attempt++)); do
        attempt_dir=$(mktemp -d "$task_dir/attempt-$attempt-XXXXXX")
        result="$attempt_dir/result.json"
        prompt_for "$task" "$attempt" "$task_dir" > "$attempt_dir/prompt.txt"
        printf 'Task %s, attempt %s/%s. Log: %s/events.jsonl\n' \
            "$task" "$attempt" "$attempts" "$attempt_dir"

        # Never use exec resume/fork: every attempt starts with fresh context.
        codex exec --cd "$repo" --approve-for-me --ephemeral --color never \
            --json --output-schema "$schema" --output-last-message "$result" \
            "${codex_options[@]}" - < "$attempt_dir/prompt.txt" \
            > "$attempt_dir/events.jsonl" 2> "$attempt_dir/stderr.log" &
        child_pid=$!
        code=0
        wait "$child_pid" || code=$?
        child_pid=''
        printf '%s\n' "$code" > "$attempt_dir/exit-code.txt"

        if ((code == 0)) && valid_complete "$result" "$task"; then
            jq --arg hash "$plan_hash" '. + {plan_sha256: $hash}' "$result" \
                > "$task_dir/complete.json.tmp"
            mv -- "$task_dir/complete.json.tmp" "$checkpoint"
            printf 'Task %s complete.\n' "$task"
            outcome=complete
            break
        fi
        if ((code == 0)) && progress_has_status "$task" blocked &&
           jq -e --arg task "$task" '
               .task == $task and .status == "blocked" and
               .handoff_updated == true and
               (.blockers | type == "array" and length > 0)
           ' "$result" >/dev/null 2>&1; then
            printf 'Task %s blocked:\n' "$task" >&2
            jq -r '.blockers[]' "$result" >&2
            outcome=blocked
            break
        fi
        printf 'Task %s attempt %s did not satisfy completion checks (Codex exit %s).\n' \
            "$task" "$attempt" "$code" >&2
    done

    case $outcome in
        complete) ;;
        blocked)
            blocked_tasks+=("$task")
            if $stop_on_blocked || ((number == 1)); then
                printf 'Stopped at blocked task %s. Resolve its blocker and rerun.\n' "$task" >&2
                exit 2
            fi ;;
        *) die "Task $task failed after $attempts attempts. Inspect $task_dir and rerun." ;;
    esac
done

if ((${#blocked_tasks[@]})); then
    printf 'Run finished with blocked tasks: %s. See APIH-REST-PROGRESS.md.\n' \
        "${blocked_tasks[*]}" >&2
    exit 2
fi
printf 'Selected tasks %02d–%02d completed. See APIH-REST-PROGRESS.md and apih-tests/coverage.md.\n' \
    "$first" "$last"
