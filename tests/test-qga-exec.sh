#!/usr/bin/env bash
set -euo pipefail

qga_exec=${1:?usage: test-qga-exec QGA-EXEC}
test_root=$(mktemp -d)
listener_pid=

cleanup() {
  if [[ ${listener_pid:-} =~ ^[0-9]+$ ]]; then
    kill "$listener_pid" 2>/dev/null || true
    wait "$listener_pid" 2>/dev/null || true
  fi
  rm -rf -- "$test_root"
}
trap cleanup EXIT

handler="$test_root/qga-handler"
printf '#!%s\n' "${BASH:?}" >"$handler"
cat >>"$handler" <<'EOF'
set -euo pipefail
# Simulate a response retained from a probe that disconnected before reading it.
printf '{"return":{"pid":999}}\n'
while IFS= read -r request; do
  printf '%s\n' "$request" >>"$QGA_REQUEST_LOG"
  case "$(jq -r .execute <<<"$request")" in
    guest-sync)
      jq -cn --argjson id "$(jq -er .arguments.id <<<"$request")" \
        '{return:$id}'
      ;;
    guest-ping)
      printf '{"return":{}}\n'
      ;;
    guest-exec)
      printf '{"return":{"pid":42}}\n'
      ;;
    guest-exec-status)
      printf '{"return":{"exited":true,"exitcode":%s,"out-data":"%s","err-data":"%s"}}\n' \
        "${QGA_GUEST_EXIT_CODE:-0}" "${QGA_OUT_DATA:-}" "${QGA_ERR_DATA:-}"
      ;;
    *)
      printf '{"error":{"class":"CommandNotFound","desc":"unexpected request"}}\n'
      ;;
  esac
done
EOF
chmod +x "$handler"

start_listener() {
  socket="$test_root/qga.sock"
  request_log="$test_root/qga.log"
  : >"$request_log"
  export QGA_REQUEST_LOG=$request_log
  socat "UNIX-LISTEN:$socket,fork" "EXEC:$handler" &
  listener_pid=$!
  for _ in $(seq 1 100); do
    [[ -S $socket ]] && return 0
    sleep 0.01
  done
  printf 'fake QGA socket did not appear\n' >&2
  return 1
}

stop_listener() {
  kill "$listener_pid" 2>/dev/null || true
  wait "$listener_pid" 2>/dev/null || true
  listener_pid=
  rm -f -- "$test_root/qga.sock"
}

# A clean guest exit forwards stdout and exits 0.
QGA_OUT_DATA=$(printf 'hello\n' | base64 -w0)
export QGA_OUT_DATA
start_listener
"$qga_exec" "$test_root/qga.sock" /run/current-system/sw/bin/echo hello \
  >"$test_root/stdout" 2>"$test_root/stderr"
[[ $(cat "$test_root/stdout") == hello ]]
if [[ -s $test_root/stderr ]]; then
  printf 'qga-exec wrote unexpected stderr: %s\n' "$(cat "$test_root/stderr")" >&2
  exit 1
fi
jq -se '
  map(select(.execute == "guest-exec"))[0].arguments
  == {
    path: "/run/current-system/sw/bin/env",
    arg: [
      "PATH=/run/current-system/sw/bin:/run/current-system/sw/sbin",
      "HOME=/root",
      "USER=root",
      "LOGNAME=root",
      "SHELL=/run/current-system/sw/bin/bash",
      "TERM=dumb",
      "/run/current-system/sw/bin/echo",
      "hello"
    ],
    "capture-output": true
  }
' "$test_root/qga.log" >/dev/null
stop_listener

# The guest command runs in a normalized environment, not in the environment of
# qemu-guest-agent.service: `nft` and friends must resolve through the system
# profile and $HOME must be populated.  Regression test for operators having to
# spell out /run/current-system/sw/bin/... for every diagnostic.
QGA_OUT_DATA=$(printf 'normalized\n' | base64 -w0)
export QGA_OUT_DATA
start_listener
"$qga_exec" "$test_root/qga.sock" /run/current-system/sw/bin/env \
  >"$test_root/env.stdout" 2>"$test_root/env.stderr"
jq -se '
  map(select(.execute == "guest-exec"))[0].arguments.arg
  | index("PATH=/run/current-system/sw/bin:/run/current-system/sw/sbin") != null
    and index("HOME=/root") != null
' "$test_root/qga.log" >/dev/null
stop_listener

# QGA_GUEST_ENV=0 keeps the raw "no shell, no environment" passthrough for
# callers that deliberately need the agent's own environment.
QGA_OUT_DATA=$(printf 'raw\n' | base64 -w0)
export QGA_OUT_DATA
export QGA_GUEST_ENV=0
start_listener
"$qga_exec" "$test_root/qga.sock" /run/current-system/sw/bin/echo raw \
  >/dev/null 2>&1
jq -se '
  map(select(.execute == "guest-exec"))[0].arguments
  == {
    path: "/run/current-system/sw/bin/echo",
    arg: ["raw"],
    "capture-output": true
  }
' "$test_root/qga.log" >/dev/null
stop_listener
unset QGA_GUEST_ENV

# Individual variables can be overridden without disabling normalization.
QGA_OUT_DATA=$(printf 'override\n' | base64 -w0)
export QGA_OUT_DATA
export QGA_GUEST_PATH=/opt/bin:/run/current-system/sw/bin
export QGA_GUEST_HOME=/home/operator
start_listener
"$qga_exec" "$test_root/qga.sock" /run/current-system/sw/bin/echo hi \
  >/dev/null 2>&1
jq -se '
  map(select(.execute == "guest-exec"))[0].arguments.arg
  | index("PATH=/opt/bin:/run/current-system/sw/bin") != null
    and index("HOME=/home/operator") != null
' "$test_root/qga.log" >/dev/null
stop_listener
unset QGA_GUEST_PATH QGA_GUEST_HOME

# The guest exit status is preserved, and stderr is forwarded.
export QGA_GUEST_EXIT_CODE=3
QGA_ERR_DATA=$(printf 'boom\n' | base64 -w0)
export QGA_ERR_DATA
start_listener
if "$qga_exec" "$test_root/qga.sock" /run/current-system/sw/bin/false \
  >"$test_root/status.out" 2>"$test_root/status.err"; then
  printf 'qga-exec ignored a failing guest exit status\n' >&2
  exit 1
fi
[[ $(cat "$test_root/status.err") == boom ]]
stop_listener

# A missing socket is reported clearly.
if "$qga_exec" "$test_root/absent.sock" true >/dev/null 2>"$test_root/absent.err"; then
  printf 'qga-exec accepted a missing socket\n' >&2
  exit 1
fi
grep -q 'guest-agent socket is not available' "$test_root/absent.err"

printf 'QEMU guest-agent exec tests passed\n'
