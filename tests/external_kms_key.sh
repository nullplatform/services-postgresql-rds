#!/bin/bash
set -uo pipefail

BUILD_CONTEXT="$(cd "$(dirname "$0")/../rds-postgres-server/scripts/aws" && pwd)/build_context"
SERVICE_ID="11111111-2222-3333-4444-555555555555"
ENV_KEY="arn:aws:kms:us-east-1:111111111111:key/from-env"
STATE_KEY="arn:aws:kms:us-east-1:111111111111:key/in-state"
MANAGED_KEY="arn:aws:kms:us-east-1:111111111111:key/managed"
PASS=0
FAIL=0

check() {
	local name="$1" verdict="$2" detail="${3:-}"
	if [ "$verdict" = "ok" ]; then
		echo "  PASS: $name"
		PASS=$((PASS + 1))
	else
		echo "  FAIL: $name"
		if [ -n "$detail" ]; then echo "        $detail"; fi
		FAIL=$((FAIL + 1))
	fi
}

SANDBOX="$(mktemp -d)"
mkdir -p "$SANDBOX/bin"
printf 'region: us-east-1\n' > "$SANDBOX/values.yaml"

cat > "$SANDBOX/bin/aws" <<'EOS'
#!/bin/bash
if [ "$1 $2" = "s3 cp" ]; then
  if [ -n "${FAKE_STATE_ERROR:-}" ]; then
    echo "fatal error: An error occurred (403) when calling the HeadObject operation: Forbidden" >&2
    exit 1
  fi
  if [ -z "${FAKE_STATE_FILE:-}" ]; then
    echo "fatal error: An error occurred (404) when calling the HeadObject operation: Key \"$3\" does not exist" >&2
    exit 1
  fi
  cp "$FAKE_STATE_FILE" "$4"
fi
exit 0
EOS

cat > "$SANDBOX/bin/np" <<'EOS'
#!/bin/bash
case "$1 $2" in
  "provider list")
    category=""
    prev=""
    for a in "$@"; do
      case "$prev" in
        --categories) category="$a" ;;
        --limit) [ -n "$category" ] && { echo '{"error":"cannot use flag limit when using categories flag"}'; exit 1; } ;;
      esac
      prev="$a"
    done
    case "$category" in
      cloud-providers) echo '{"results":[{"attributes":{"account":{"region":"us-east-1"}}}]}' ;;
      vpc) echo '{"results":[{"attributes":{"vpc":{"id":"vpc-123"}}}]}' ;;
      *) echo '{"results":[]}' ;;
    esac
    ;;
esac
exit 0
EOS

cat > "$SANDBOX/run_build_context.sh" <<'EOS'
#!/bin/bash
source "$1" >/dev/null 2>"$2"
printf '%s\n' "${TOFU_VARIABLES-}"
EOS

chmod +x "$SANDBOX/bin/aws" "$SANDBOX/bin/np" "$SANDBOX/run_build_context.sh"

write_state() {
	local instance_key="$1" managed="$2"
	jq -n --arg key "$instance_key" --argjson managed "$managed" '{version: 4, resources: (
		[{mode: "managed", type: "aws_db_instance", name: "main", instances: [{attributes: {kms_key_id: $key}}]}]
		+ (if $managed then [{mode: "managed", type: "aws_kms_key", name: "rds", instances: [{index_key: 0, attributes: {arn: $key}}]}] else [] end))}' \
		> "$SANDBOX/state.json"
	echo "$SANDBOX/state.json"
}

tofu_variables_for() {
	local type="$1" state_file="$2" env_key="$3" state_error="${4:-}" context
	context=$(jq -nc --arg id "$SERVICE_ID" --arg type "$type" \
		'{type: $type, service: {id: $id, name: "test-db", nrn: "organization=1:account=2:namespace=3:application=4", attributes: {}}}')
	env PATH="$SANDBOX/bin:/usr/bin:/bin:/usr/sbin:/sbin" CONTEXT="$context" VALUES="$SANDBOX/values.yaml" \
		SERVICE_PATH="$SANDBOX" RDS_POSTGRES_S3_STATE_BUCKET="state-bucket" RDS_POSTGRES_KMS_KEY_ARN="$env_key" \
		FAKE_STATE_FILE="$state_file" FAKE_STATE_ERROR="$state_error" \
		bash "$SANDBOX/run_build_context.sh" "$BUILD_CONTEXT" "$SANDBOX/err.log"
}

expect() {
	local name="$1" out="$2" must="$3" must_not="${4:-}"
	if [[ -n "$must" && "$out" != *"$must"* ]] || [[ -n "$must_not" && "$out" == *"$must_not"* ]]; then
		check "$name" fail "$out"
	else
		check "$name" ok
	fi
}

echo "build_context"

expect "a first create uses the key from the env var" \
	"$(tofu_variables_for create "" "$ENV_KEY")" "-var=kms_key_arn=${ENV_KEY}"

expect "a first create without the env var lets the module create its key" \
	"$(tofu_variables_for create "" "")" "" "-var=kms_key_arn="

expect "an update of an instance on its own key ignores the env var" \
	"$(tofu_variables_for update "$(write_state "$MANAGED_KEY" true)" "$ENV_KEY")" "" "-var=kms_key_arn="

expect "an update of an instance on an external key keeps the key from the state" \
	"$(tofu_variables_for update "$(write_state "$STATE_KEY" false)" "$ENV_KEY")" "-var=kms_key_arn=${STATE_KEY}" "$ENV_KEY"

expect "a retried create keeps the key the instance already has" \
	"$(tofu_variables_for create "$(write_state "$STATE_KEY" false)" "$ENV_KEY")" "-var=kms_key_arn=${STATE_KEY}" "$ENV_KEY"

expect "a retried create of an instance on its own key never switches to the env var" \
	"$(tofu_variables_for create "$(write_state "$MANAGED_KEY" true)" "$ENV_KEY")" "" "-var=kms_key_arn="

expect "a delete of an instance on an external key passes that key" \
	"$(tofu_variables_for delete "$(write_state "$STATE_KEY" false)" "")" "-var=kms_key_arn=${STATE_KEY}"

out=$(tofu_variables_for update "" "$ENV_KEY" 1)
if [[ -z "$out" ]] && grep -q "could not read the tofu state" "$SANDBOX/err.log"; then
	check "an unreadable state stops before tofu instead of guessing the key" ok
else
	check "an unreadable state stops before tofu instead of guessing the key" fail "$out"
fi

out=$(tofu_variables_for create "" "alias/my-key")
if [[ -z "$out" ]] && grep -q "is not a KMS key ARN" "$SANDBOX/err.log"; then
	check "an env var that is not a kms key arn never reaches tofu" ok
else
	check "an env var that is not a kms key arn never reaches tofu" fail "$out"
fi

rm -rf "${SANDBOX:?}" "/tmp/np-service-${SERVICE_ID:?}"

echo ""
echo "${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
