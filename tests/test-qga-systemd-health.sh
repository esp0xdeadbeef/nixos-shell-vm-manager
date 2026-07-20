#!/usr/bin/env bash
set -euo pipefail

health_check=${1:?usage: test-qga-systemd-health HEALTH-CHECK}
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
IFS= read -r request
printf '%s\n' "$request" >>"$QGA_REQUEST_LOG"
case "$(jq -r .execute <<<"$request")" in
  guest-ping)
    printf '{"return":{}}\n'
    ;;
  guest-exec)
    printf '{"return":{"pid":42}}\n'
    ;;
  guest-exec-status)
    if [[ $QGA_GUEST_EXIT_CODE == 0 ]]; then
      printf '{"return":{"exited":true,"exitcode":0}}\n'
    else
      printf '{"return":{"exited":true,"exitcode":1,"err-data":"Y3JpdGljYWwgdW5pdCBmYWlsZWQK"}}\n'
    fi
    ;;
  *)
    printf '{"error":{"class":"CommandNotFound","desc":"unexpected request"}}\n'
    ;;
esac
EOF
chmod +x "$handler"

start_listener() {
  local exit_code=$1
  socket="$test_root/qga-$exit_code.sock"
  request_log="$test_root/qga-$exit_code.log"
  : >"$request_log"
  export QGA_GUEST_EXIT_CODE=$exit_code
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

guest_command=/run/current-system/sw/bin/systemctl
guest_arguments=(
  is-active
  --quiet
  systemd-networkd.service
  container@core.service
)

start_listener 0
"$health_check" "$socket" "$guest_command" "${guest_arguments[@]}"
expected_arguments=$(printf '%s\n' "${guest_arguments[@]}" | jq -R . | jq -s .)
jq -se --arg path "$guest_command" --argjson expected "$expected_arguments" '
  map(select(.execute == "guest-exec"))[0].arguments
  == {
    path: $path,
    arg: $expected,
    "capture-output": true
  }
' "$request_log" >/dev/null
kill "$listener_pid"
wait "$listener_pid" 2>/dev/null || true
listener_pid=

start_listener 1
if "$health_check" "$socket" "$guest_command" "${guest_arguments[@]}" \
  >"$test_root/failure.out" 2>"$test_root/failure.err"; then
  printf 'failed guest command was accepted as healthy\n' >&2
  exit 1
fi
grep -Fx 'critical unit failed' "$test_root/failure.err" >/dev/null

printf 'QEMU guest-agent systemd health tests passed\n'
