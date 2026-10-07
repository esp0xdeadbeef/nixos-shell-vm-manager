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
    path: "/run/current-system/sw/bin/echo",
    arg: ["hello"],
    "capture-output": true
  }
' "$test_root/qga.log" >/dev/null
stop_listener

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
