# Key-only SSH to a fleet machine's `ssh` string, shared by setup's test and the
# machine check: batch mode, so no password or passphrase prompt; strict host
# keys, so a host key ssh does not already know is never accepted; one attempt
# with a 6 second connect timeout.
# shellcheck disable=SC2034  # read by the scripts that source this
sa_ssh_opts=(-o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=6)

# sa_ssh_reason <ssh's stderr>: why a call that exited 255 failed, `unknown-host-key`
# when the host key is not known (the owner connects once by hand), else ssh's last
# error line.
sa_ssh_reason() {
  if grep -q 'Host key verification failed' <<<"$1"; then echo unknown-host-key
  else grep -v '^[[:space:]]*$' <<<"$1" | tail -n1; fi
}
