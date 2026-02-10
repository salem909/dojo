#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${PUBLIC_KEY:-}" ]]; then
  install -d -m 700 -o ctf -g ctf /home/ctf/.ssh
  echo "$PUBLIC_KEY" > /home/ctf/.ssh/authorized_keys
  chown ctf:ctf /home/ctf/.ssh/authorized_keys
  chmod 600 /home/ctf/.ssh/authorized_keys
fi

mkdir -p /run/sshd
/usr/sbin/sshd -e -p 2222 &

chmod -R a+rX /challenge || true
chmod -R go-w /challenge || true

exec sleep infinity
