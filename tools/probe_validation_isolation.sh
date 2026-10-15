#!/usr/bin/env bash
# Harmless, bounded hosted-runner diagnostic. No policy or privilege changes.
set -euo pipefail
printf 'validation-isolation: image=%s version=%s\n' "${ImageOS:-unavailable}" "${ImageVersion:-unavailable}"
uname -srmo
id
bwrap --version
for path in /etc/os-release /proc/self/attr/current /proc/sys/kernel/unprivileged_userns_clone /proc/sys/kernel/apparmor_restrict_unprivileged_userns /proc/sys/user/max_user_namespaces /sys/module/apparmor/parameters/enabled; do
  printf 'validation-isolation: %s\n' "$path"
  if [[ -r "$path" ]]; then
    head -c 4096 -- "$path" || printf 'diagnostic unavailable\n'
  else
    printf 'diagnostic unavailable (not proof of absent policy)\n'
  fi
done
awk '/^(Uid|Gid|CapInh|CapPrm|CapEff|CapBnd|CapAmb|NoNewPrivs|Seccomp):/' /proc/self/status
[[ "$(id -u)" != 0 ]] || { printf 'validation-isolation: refusing root execution\n' >&2; exit 3; }
args=(--die-with-parent --new-session --unshare-net --unshare-pid --tmpfs / --ro-bind /usr /usr)
for name in bin sbin lib lib64; do
  if [[ -L "/$name" ]]; then
    args+=(--symlink "$(readlink -- "/$name")" "/$name")
  elif [[ -d "/$name" ]]; then
    args+=(--ro-bind "/$name" "/$name")
  fi
done
[[ ! -e /etc/ld.so.cache ]] || args+=(--ro-bind /etc/ld.so.cache /etc/ld.so.cache)
printf 'validation-isolation: probing actual unprivileged network/PID namespace setup (30s bound)\n'
timeout --signal=TERM --kill-after=2s 30s bwrap "${args[@]}" --dev /dev --proc /proc --clearenv -- /usr/bin/bash -c '
  set -euo pipefail
  [[ "$UID" != 0 ]]
  /usr/bin/awk "/^(Uid|CapEff|NoNewPrivs|Seccomp):/" /proc/self/status
  /usr/bin/cat /proc/net/route
  printf "validation-isolation: setup executed\n"
'
# Successful setup is only a preflight, not the executor containment proof.
