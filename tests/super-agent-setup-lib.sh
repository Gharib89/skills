# The setup tests' shared prelude: setup.sh over fake probes on PATH
# (tests/super-agent-fake.sh), with the fixtures each provider answers.
source tests/lib.sh
source tests/super-agent-fake.sh

s=skills/super-agent/scripts
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/tools" "$tmp/fake"
# Hermetic: only the tools the script itself needs are linked in, so the real
# nvidia-smi, claude, codex and agy cannot answer for a fake that is removed.
for t in bash env jq awk sed grep cat mktemp mv rm mkdir dirname basename tr head tail date timeout sort cut find wc diff chmod cp cmp; do
  ln -s "$(command -v $t)" "$tmp/tools/$t" || exit 2
done
export PATH="$tmp/bin:$tmp/tools" SA_FAKE=$tmp/fake
sa_fake_install "$tmp/bin"
fleet=$tmp/config/fleet.json
S() { bash "$s/setup.sh" --fleet "$fleet" "$@"; }
P() { S --propose "$@"; }

# shellcheck disable=SC2034  # the fixtures are read by the tests that source this
{
claude_ok='{"type":"result","result":"Current session: 3% used · resets 14:00"}'
agy_ok='{"conversation_id":"","status":"SUCCESS","response":"Gemini Models\tWeekly Limit Remaining\t96%"}'
codex_ok=$'{"id":1,"result":{"codexHome":"/x"}}\n{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":0}}}}'
}
