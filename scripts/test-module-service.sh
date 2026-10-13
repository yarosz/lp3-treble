#!/usr/bin/env bash
# Host test for module/service.sh: feeds it a sequence of qcril process ids (one per poll) and counts how often it
# starts lp3-atel-ready. Device paths are rewritten into a temp dir; getprop, pidof, log and sleep are stubs.
# Usage: scripts/test-module-service.sh
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
fail=0

# run <name> <expected starts> <qcril binary present: 1|0> <pidof output per poll>...
run() {
  local name=$1 want=$2 has_qcril=$3; shift 3
  local t; t=$(mktemp -d)
  mkdir -p "$t/bin" "$t/vendor/bin/hw" "$t/product/overlay" "$t/system/bin"
  [ "$has_qcril" = 1 ] && touch "$t/vendor/bin/hw/qcrilNrd"
  printf '%s\n' "$@" >"$t/pids"
  cat >"$t/bin/getprop" <<'EOF'
#!/bin/sh
echo 1
EOF
  # One line of $t/pids per call; when the lines run out, stop the script under test.
  cat >"$t/bin/pidof" <<EOF
#!/bin/sh
n=\$(cat "$t/n" 2>/dev/null || echo 0); n=\$((n + 1)); echo \$n >"$t/n"
line=\$(sed -n "\${n}p" "$t/pids")
[ "\$n" -le "\$(wc -l <"$t/pids")" ] || kill -TERM \$PPID
[ "\$line" = - ] || echo "\$line"
EOF
  printf '#!/bin/sh\necho "$*" >>"%s/log"\n' "$t" >"$t/bin/log"
  printf '#!/bin/sh\n/bin/sleep 0.5\n' >"$t/bin/sleep"
  printf '#!/bin/sh\necho start >>"%s/starts"\n' "$t" >"$t/system/bin/app_process"
  chmod +x "$t"/bin/* "$t/system/bin/app_process"
  sed -e "s|/vendor/|$t/vendor/|g" -e "s|/product/|$t/product/|g" -e "s|/system/bin/app_process|$t/system/bin/app_process|" \
    "$root/module/service.sh" >"$t/service.sh"
  # Background + wait, so bash doesn't report the stub's SIGTERM.
  PATH=$t/bin:$PATH sh "$t/service.sh" >/dev/null 2>&1 &
  wait $! 2>/dev/null || true
  /bin/sleep 0.5  # the stub app_process runs in the background
  local got=0
  [ -f "$t/starts" ] && got=$(wc -l <"$t/starts" | tr -d ' ')
  if [ "$got" = "$want" ]; then echo "ok   $name ($got)"; else echo "FAIL $name: want $want starts, got $got"; fail=1; fi
  [ -n "${KEEP:-}" ] && echo "kept $t" || rm -rf "$t"
}

run "boot, both slots up"              1 1 "100 101" "100 101" "100 101"
run "fast restart of one slot"         2 1 "100 101" "100 205" "100 205"
run "restart of both between polls"    2 1 "100 101" "300 301" "300 301"
run "qcril not up yet at boot"         1 1 - - "100 101" "100 101"
run "slot 2 starts late"               2 1 "100" "100 101" "100 101"
run "qcril dies and comes back"        2 1 "100 101" - "102 103"
run "no qcril binary: exits at once"   0 0 "100 101"
exit $fail
