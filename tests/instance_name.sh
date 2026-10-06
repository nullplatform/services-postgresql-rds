#!/bin/bash
set -uo pipefail

BUILD_CONTEXT="$(cd "$(dirname "$0")/../rds-postgres-server/scripts/aws" && pwd)/build_context"
SERVICE_ID="11111111-2222-3333-4444-555555555555"
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
      if [ "$prev" = "--categories" ]; then category="$a"; fi
      prev="$a"
    done
    case "$category" in
      cloud-providers) echo '{"results":[{"attributes":{"account":{"region":"us-east-1"}}}]}' ;;
      vpc) echo '{"results":[{"attributes":{"vpc":{"id":"vpc-123","subnets":["subnet-a","subnet-b"]}}}]}' ;;
      *) echo '{"results":[]}' ;;
    esac
    ;;
  "service read") echo '{"id":"x","name":"Orders From Api","slug":"orders-from-api"}' ;;
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
	local resources="$1"
	jq -n --argjson resources "$resources" '{version: 4, resources: $resources}' > "$SANDBOX/state.json"
	echo "$SANDBOX/state.json"
}

instance_name_for_context() {
	local type="$1" service="$2" state_file="${3:-}" context
	context=$(jq -nc --arg id "$SERVICE_ID" --arg type "$type" --argjson service "$service" \
		'{type: $type, service: ({id: $id, nrn: "organization=1:account=2:namespace=3:application=4", attributes: {}} + $service)}')
	env PATH="$SANDBOX/bin:/usr/bin:/bin:/usr/sbin:/sbin" CONTEXT="$context" VALUES="$SANDBOX/values.yaml" \
		SERVICE_PATH="$SANDBOX" RDS_POSTGRES_S3_STATE_BUCKET="state-bucket" FAKE_STATE_FILE="$state_file" \
		bash "$SANDBOX/run_build_context.sh" "$BUILD_CONTEXT" "$SANDBOX/err.log" \
		| grep -o -- '-var=instance_name=[^ ]*' | cut -d= -f3
}

expect() {
	local name="$1" got="$2" want="$3"
	if [ "$got" = "$want" ]; then
		check "$name" ok
	else
		check "$name" fail "want: $want, got: $got $(cat "$SANDBOX/err.log")"
	fi
}

echo "build_context"

expect "a new instance is named after the service slug and id" \
	"$(instance_name_for_context create '{"slug":"orders-api","name":"Orders API"}')" "orders-api-${SERVICE_ID}"

expect "the service name is used when the context has no slug" \
	"$(instance_name_for_context create '{"name":"Orders API"}')" "orders-api-${SERVICE_ID}"

expect "the service is read from the api when the context carries neither slug nor name" \
	"$(instance_name_for_context create '{}')" "orders-from-api-${SERVICE_ID}"

expect "a slug that does not start with a letter is prefixed" \
	"$(instance_name_for_context create '{"slug":"42-orders"}')" "db-42-orders-${SERVICE_ID}"

LONG_NAME=$(instance_name_for_context create '{"slug":"a-very-long-service-slug-that-goes-past-the-rds-limit"}')
expect "the name never exceeds the 63 characters rds allows" "$([ "${#LONG_NAME}" -le 63 ] && echo ok)" "ok"
expect "a truncated slug never ends in a hyphen before the id" "$([[ "$LONG_NAME" != *--* ]] && echo ok)" "ok"

EXISTING='[{"mode":"managed","type":"aws_db_instance","name":"main","instances":[{"attributes":{"identifier":"np-test-db","kms_key_id":""}}]},
	{"mode":"managed","type":"aws_db_subnet_group","name":"main","instances":[{"attributes":{"name":"np-test-db"}}]},
	{"mode":"managed","type":"aws_security_group","name":"rds","instances":[{"attributes":{"name":"np-rds-np-test-db","vpc_id":"vpc-123"}}]}]'

expect "an update of an existing instance keeps the name from the state" \
	"$(instance_name_for_context update '{"slug":"orders-api"}' "$(write_state "$EXISTING")")" "np-test-db"

expect "a delete of an existing instance keeps the name from the state" \
	"$(instance_name_for_context delete '{"slug":"orders-api"}' "$(write_state "$EXISTING")")" "np-test-db"

expect "a retried create keeps the name of the resources it already created" \
	"$(instance_name_for_context create '{"slug":"orders-api"}' "$(write_state '[{"mode":"managed","type":"aws_security_group","name":"rds","instances":[{"attributes":{"name":"np-rds-np-test-db","vpc_id":"vpc-123"}}]}]')")" "np-test-db"

expect "a state holding only the master secret still yields its name" \
	"$(instance_name_for_context create '{"slug":"orders-api"}' "$(write_state '[{"mode":"managed","type":"aws_secretsmanager_secret","name":"master","instances":[{"attributes":{"name":"nullplatform/rds/np-test-db/master"}}]}]')")" "np-test-db"

expect "an empty state names the instance after the slug" \
	"$(instance_name_for_context update '{"slug":"orders-api"}' "$(write_state '[]')")" "orders-api-${SERVICE_ID}"

expect "a null identifier falls back to the subnet group name" \
	"$(instance_name_for_context update '{"slug":"orders-api"}' "$(write_state '[{"mode":"managed","type":"aws_db_instance","name":"main","instances":[{"attributes":{"identifier":null}}]},{"mode":"managed","type":"aws_db_subnet_group","name":"main","instances":[{"attributes":{"name":"np-test-db"}}]}]')")" "np-test-db"

expect "a state holding only the kms alias still yields its name" \
	"$(instance_name_for_context create '{"slug":"orders-api"}' "$(write_state '[{"mode":"managed","type":"aws_kms_alias","name":"rds","instances":[{"index_key":0,"attributes":{"name":"alias/nullplatform-rds-np-test-db"}}]}]')")" "np-test-db"

expect_abort() {
	local name="$1" got="$2" message="$3"
	if [ -z "$got" ] && grep -q "$message" "$SANDBOX/err.log"; then
		check "$name" ok
	else
		check "$name" fail "got: $got $(cat "$SANDBOX/err.log")"
	fi
}

printf '{"version":4,"resources":[' > "$SANDBOX/truncated.json"
expect_abort "a truncated state stops before tofu instead of renaming the instance" \
	"$(instance_name_for_context update '{"slug":"orders-api"}' "$SANDBOX/truncated.json")" "is not a valid tofu state"

: > "$SANDBOX/empty.json"
expect_abort "an empty state file stops before tofu instead of renaming the instance" \
	"$(instance_name_for_context update '{"slug":"orders-api"}' "$SANDBOX/empty.json")" "is not a valid tofu state"

printf '[1]' > "$SANDBOX/array.json"
expect_abort "a state that is not an object stops before tofu" \
	"$(instance_name_for_context create '{"slug":"orders-api"}' "$SANDBOX/array.json")" "is not a valid tofu state"

expect_abort "an update without a state never creates a new instance" \
	"$(instance_name_for_context update '{"slug":"orders-api"}')" "refusing to update"

rm -rf "${SANDBOX:?}" "/tmp/np-service-${SERVICE_ID:?}"

echo ""
echo "${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
