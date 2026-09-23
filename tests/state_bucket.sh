#!/bin/bash
# Usage: tests/state_bucket.sh [package-dir]
#
# Drives the package's build_context and delete_tfstate_bucket against fake
# aws/np binaries. Both packages carry the same state-resolution block, so the
# last section fails if they ever drift apart.
set -uo pipefail

PACKAGE="${1:-rds-postgres-db}"
BUILD_CONTEXT="${PACKAGE}/scripts/aws/build_context"
DELETE_STATE="${PACKAGE}/scripts/aws/delete_tfstate_objects"
BUCKET_VAR="RDS_S3_STATE_BUCKET"
SERVICE_ID="11111111-2222-3333-4444-555555555555"
PASS=0
FAIL=0

for f in "$BUILD_CONTEXT" "$DELETE_STATE"; do
	if [ ! -f "$f" ]; then
		echo "not found: $f" >&2
		exit 1
	fi
done

BUILD_CONTEXT="$(cd "$(dirname "$BUILD_CONTEXT")" && pwd)/$(basename "$BUILD_CONTEXT")"
DELETE_STATE="$(cd "$(dirname "$DELETE_STATE")" && pwd)/$(basename "$DELETE_STATE")"

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

setup_sandbox() {
	SANDBOX="$(mktemp -d)"
	mkdir -p "$SANDBOX/bin"
	: > "$SANDBOX/aws.log"
	printf 'region: us-east-1\n' > "$SANDBOX/values.yaml"

	printf '%s\n' "$@" > "$SANDBOX/existing_buckets"

	cat > "$SANDBOX/bin/aws" <<'EOS'
#!/bin/bash
echo "aws $*" >> "$AWS_LOG"
bucket=""
prev=""
for a in "$@"; do
  if [ "$prev" = "--bucket" ]; then bucket="$a"; fi
  prev="$a"
done
if [ "$1 $2" = "s3api head-bucket" ]; then
  grep -qxF "$bucket" "$EXISTING_BUCKETS" || exit 255
  exit 0
fi
if [ "$1 $2" = "s3api create-bucket" ]; then
  echo "$bucket" >> "$EXISTING_BUCKETS"
  exit 0
fi
if [ "$1 $2" = "s3api list-object-versions" ]; then
  echo 'null'
  exit 0
fi
exit 0
EOS

	cat > "$SANDBOX/bin/np" <<'EOS'
#!/bin/bash
case "$1 $2" in
  "provider list")
    echo '{"results":[{"id":"prov-region","data_source":{"stored_keys":["account.region"]}},{"id":"prov-vpc","data_source":{"stored_keys":["vpc.id"]}}]}'
    ;;
  "provider read")
    echo '{"attributes":{"account":{"region":"us-east-1"},"vpc":{"id":"vpc-123"}}}'
    ;;
  "service read")
    echo '{"attributes":{"hostname":"db.example.com","port":"5432","database_name":"app","username":"app"}}'
    ;;
  *)
    echo '{}'
    ;;
esac
exit 0
EOS

	cat > "$SANDBOX/run_build_context.sh" <<'EOS'
#!/bin/bash
source "$1" >"$2" 2>"$3"
printf 'TFSTATE_BUCKET=%s\n' "${TFSTATE_BUCKET-}"
printf 'TFSTATE_KEY_PREFIX=%s\n' "${TFSTATE_KEY_PREFIX-}"
printf 'TOFU_INIT_VARIABLES=%s\n' "${TOFU_INIT_VARIABLES-}"
EOS

	chmod +x "$SANDBOX/bin/aws" "$SANDBOX/bin/np" "$SANDBOX/run_build_context.sh"

	CONTEXT_JSON="{\"service\":{\"id\":\"${SERVICE_ID}\",\"name\":\"test-db\",\"nrn\":\"organization=1:account=2:namespace=3:application=4\",\"attributes\":{}}}"
}

teardown_sandbox() {
	rm -rf "${SANDBOX:?}"
	rm -rf "/tmp/np-service-${SERVICE_ID:?}"
}

run_build_context() {
	local mode="$1" value="${2:-}"
	local common=(
		PATH="$SANDBOX/bin:/usr/bin:/bin:/usr/sbin:/sbin"
		AWS_LOG="$SANDBOX/aws.log"
		EXISTING_BUCKETS="$SANDBOX/existing_buckets"
		CONTEXT="$CONTEXT_JSON"
		VALUES="$SANDBOX/values.yaml"
		SERVICE_PATH="$SANDBOX"
	)
	if [ "$mode" = "unset" ]; then
		env -u "$BUCKET_VAR" "${common[@]}" \
			bash "$SANDBOX/run_build_context.sh" "$BUILD_CONTEXT" "$SANDBOX/out.log" "$SANDBOX/err.log"
	else
		env "$BUCKET_VAR=$value" "${common[@]}" \
			bash "$SANDBOX/run_build_context.sh" "$BUILD_CONTEXT" "$SANDBOX/out.log" "$SANDBOX/err.log"
	fi
}

run_delete_state() {
	local mode="$1" value="${2:-}" prefix="${3:-}"
	local common=(
		PATH="$SANDBOX/bin:/usr/bin:/bin:/usr/sbin:/sbin"
		AWS_LOG="$SANDBOX/aws.log"
		EXISTING_BUCKETS="$SANDBOX/existing_buckets"
		REGION=us-east-1
		VALUES="$SANDBOX/values.yaml"
		TFSTATE_BUCKET=state-bucket
	)
	if [ "$mode" = "unset" ]; then
		env -u "$BUCKET_VAR" "${common[@]}" TFSTATE_KEY_PREFIX="$prefix" bash "$DELETE_STATE" 2>&1
	else
		env "$BUCKET_VAR=$value" "${common[@]}" TFSTATE_KEY_PREFIX="$prefix" bash "$DELETE_STATE" 2>&1
	fi
}

field() {
	echo "$1" | sed -n "s/^$2=//p"
}

echo "### package: ${PACKAGE}"
echo

echo "=== shared bucket configured and reachable ==="
setup_sandbox shared-state
out="$(run_build_context set shared-state)"
if [ "$(field "$out" TFSTATE_BUCKET)" = "shared-state" ]; then
	check "uses the configured bucket" "ok"
else
	check "uses the configured bucket" "bad" "got '$(field "$out" TFSTATE_BUCKET)'"
fi
if [ "$(field "$out" TFSTATE_KEY_PREFIX)" = "services/${SERVICE_ID}/" ]; then
	check "prefixes the key with the service id" "ok"
else
	check "prefixes the key with the service id" "bad" "got '$(field "$out" TFSTATE_KEY_PREFIX)'"
fi
if ! grep -q 'TOFU_INIT_VARIABLES=' "$BUILD_CONTEXT"; then
	echo "  SKIP: backend key lands under the prefix (this package builds it in a later step)"
elif field "$out" TOFU_INIT_VARIABLES | grep -qF -- "-backend-config=key=services/${SERVICE_ID}/terraform.tfstate"; then
	check "backend key lands under the prefix" "ok"
else
	check "backend key lands under the prefix" "bad" "got '$(field "$out" TOFU_INIT_VARIABLES)'"
fi
if grep -q 'create-bucket' "$SANDBOX/aws.log"; then
	check "never creates a bucket" "bad" "$(grep create-bucket "$SANDBOX/aws.log" | head -1)"
else
	check "never creates a bucket" "ok"
fi
teardown_sandbox

echo "=== shared bucket configured but missing ==="
setup_sandbox some-other-bucket
out="$(run_build_context set shared-state)"
rc=$?
err="$(cat "$SANDBOX/err.log" 2>/dev/null)"
if [ "$rc" -ne 0 ]; then
	check "aborts when the bucket does not exist" "ok"
else
	check "aborts when the bucket does not exist" "bad" "rc=$rc"
fi
if echo "$err" | grep -q 'does not exist or is not reachable'; then
	check "says the bucket is unreachable" "ok"
else
	check "says the bucket is unreachable" "bad" "stderr: $(echo "$err" | tr '\n' '|')"
fi
if grep -q 'create-bucket' "$SANDBOX/aws.log"; then
	check "does not fall back to creating it" "bad"
else
	check "does not fall back to creating it" "ok"
fi
teardown_sandbox

echo "=== bucket variable set but empty ==="
setup_sandbox shared-state
out="$(run_build_context set "")"
rc=$?
err="$(cat "$SANDBOX/err.log" 2>/dev/null)"
if [ "$rc" -ne 0 ]; then
	check "rejects an empty bucket name" "ok"
else
	check "rejects an empty bucket name" "bad" "rc=$rc bucket='$(field "$out" TFSTATE_BUCKET)'"
fi
if echo "$err" | grep -q 'is not set'; then
	check "names the variable to set" "ok"
else
	check "names the variable to set" "bad" "stderr: $(echo "$err" | tr '\n' '|')"
fi
if grep -q 'create-bucket' "$SANDBOX/aws.log"; then
	check "never creates a bucket" "bad" "$(grep create-bucket "$SANDBOX/aws.log" | head -1)"
else
	check "never creates a bucket" "ok"
fi
teardown_sandbox

echo "=== bucket variable unset ==="
setup_sandbox
out="$(run_build_context unset)"
rc=$?
err="$(cat "$SANDBOX/err.log" 2>/dev/null)"
if [ "$rc" -ne 0 ]; then
	check "aborts when no bucket is configured" "ok"
else
	check "aborts when no bucket is configured" "bad" "rc=$rc bucket='$(field "$out" TFSTATE_BUCKET)'"
fi
if grep -q 'create-bucket' "$SANDBOX/aws.log"; then
	check "never falls back to creating a bucket" "bad" "$(grep create-bucket "$SANDBOX/aws.log" | head -1)"
else
	check "never falls back to creating a bucket" "ok"
fi
if echo "$err" | grep -q 'RDS_S3_STATE_BUCKET'; then
	check "names the variable to set" "ok"
else
	check "names the variable to set" "bad" "stderr: $(echo "$err" | tr '\n' '|')"
fi
teardown_sandbox

echo "=== delete: empties only this prefix ==="
setup_sandbox state-bucket
out="$(run_delete_state set shared-state "services/${SERVICE_ID}/")"
if grep -q -- "--prefix services/${SERVICE_ID}/" "$SANDBOX/aws.log"; then
	check "scopes the listing to its own prefix" "ok"
else
	check "scopes the listing to its own prefix" "bad" "$(tr '\n' '|' < "$SANDBOX/aws.log")"
fi
if grep -q 'delete-bucket' "$SANDBOX/aws.log"; then
	check "never deletes the bucket" "bad" "$(grep delete-bucket "$SANDBOX/aws.log" | head -1)"
else
	check "never deletes the bucket" "ok"
fi
teardown_sandbox

echo "=== delete: an empty prefix is refused ==="
setup_sandbox state-bucket
out="$(run_delete_state set shared-state "")"
rc=$?
if [ "$rc" -ne 0 ]; then
	check "refuses the dangerous combination" "ok"
else
	check "refuses the dangerous combination" "bad" "rc=$rc"
fi
if echo "$out" | grep -q 'every service'; then
	check "explains it would wipe every service's state" "ok"
else
	check "explains it would wipe every service's state" "bad" "out: $(echo "$out" | tr '\n' '|')"
fi
if grep -qE 'delete-objects|delete-bucket' "$SANDBOX/aws.log"; then
	check "deletes nothing at all" "bad" "$(tr '\n' '|' < "$SANDBOX/aws.log")"
else
	check "deletes nothing at all" "ok"
fi
teardown_sandbox

echo "=== both packages resolve state the same way ==="
extract_block() {
	# shellcheck disable=SC2016
	sed -n '/^if \[ -z "${RDS_S3_STATE_BUCKET:-}" \]; then$/,/^export TFSTATE_BUCKET TFSTATE_KEY_PREFIX$/p' "$1"
}
ROOT="$(cd "$(dirname "$BUILD_CONTEXT")/../../.." && pwd)"
BLOCK_DB="$(extract_block "$ROOT/rds-postgres-db/scripts/aws/build_context")"
BLOCK_SERVER="$(extract_block "$ROOT/rds-postgres-server/scripts/aws/build_context")"
if [ -z "$BLOCK_DB" ] || [ -z "$BLOCK_SERVER" ]; then
	check "the state block is present in both packages" "bad" "db=${#BLOCK_DB} server=${#BLOCK_SERVER}"
elif [ "$BLOCK_DB" = "$BLOCK_SERVER" ]; then
	check "the state block is identical in both packages" "ok"
else
	check "the state block is identical in both packages" "bad" "they drifted — drive both through this suite"
fi

echo "=== every backend key is scoped to the instance ==="
# shellcheck disable=SC2016
UNPREFIXED="$(grep -rn 'backend-config=key=' "$ROOT"/rds-postgres-*/scripts/aws/ \
	| grep -v 'backend-config=key=\${TFSTATE_KEY_PREFIX}' || true)"
if [ -z "$UNPREFIXED" ]; then
	check "no backend key is written to the bucket root" "ok"
else
	check "no backend key is written to the bucket root" "bad" "$(echo "$UNPREFIXED" | sed "s|$ROOT/||" | tr '\n' '|')"
fi

echo
echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
