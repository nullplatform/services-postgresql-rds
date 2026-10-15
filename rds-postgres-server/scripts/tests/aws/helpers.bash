setup_mocks() {
	TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
	SERVICE_PATH="$(cd "$TEST_DIR/../../.." && pwd)"
	SCRIPTS_DIR="$SERVICE_PATH/scripts/aws"
	MOCK_BIN="$BATS_TEST_TMPDIR/bin"
	MOCK_LOG="$BATS_TEST_TMPDIR/mock.log"
	VALUES="$BATS_TEST_TMPDIR/values.yaml"
	mkdir -p "$MOCK_BIN"
	: >"$MOCK_LOG"
	printf 'aws_profile: ""\n' >"$VALUES"
	export SERVICE_PATH MOCK_LOG VALUES
	export PATH="$MOCK_BIN:$PATH"
	export MOCK_CW_EXIT="${MOCK_CW_EXIT:-0}"
	if [ -z "${MOCK_CW_RESPONSE+set}" ]; then
		MOCK_CW_RESPONSE='{"Label":"x","Datapoints":[]}'
	fi
	export MOCK_CW_RESPONSE
	unset AWS_PROFILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN ACTION_SOURCE NOTIFICATION_ACTION OVERRIDES_PATH

	cat >"$MOCK_BIN/aws" <<'MOCK'
#!/bin/bash
echo "aws $*" >> "$MOCK_LOG"
case "$*" in
	"cloudwatch get-metric-statistics"*)
		echo "cloudwatch credentials: ${AWS_ACCESS_KEY_ID:-agent}" >> "$MOCK_LOG"
		if [ "$MOCK_CW_EXIT" != "0" ]; then
			echo "An error occurred (AccessDenied) when calling the GetMetricStatistics operation" >&2
			exit "$MOCK_CW_EXIT"
		fi
		echo "$MOCK_CW_RESPONSE" ;;
esac
exit 0
MOCK

	cat >"$MOCK_BIN/np" <<'MOCK'
#!/bin/bash
echo "np $*" >> "$MOCK_LOG"
echo "{}"
exit 0
MOCK

	chmod +x "$MOCK_BIN"/*
}

run_script() {
	local script="$1"
	run bash -c "source '$SCRIPTS_DIR/$script' >'$BATS_TEST_TMPDIR/stdout' 2>'$BATS_TEST_TMPDIR/stderr'"
	captured_stdout=$(cat "$BATS_TEST_TMPDIR/stdout")
	captured_stderr=$(cat "$BATS_TEST_TMPDIR/stderr")
}

assert_equal() {
	if [ "$1" != "$2" ]; then
		echo "expected: $2"
		echo "actual:   $1"
		return 1
	fi
}

assert_contains() {
	if [[ "$1" != *"$2"* ]]; then
		echo "expected to contain: $2"
		echo "actual: $1"
		return 1
	fi
}

assert_not_contains() {
	if [[ "$1" == *"$2"* ]]; then
		echo "expected not to contain: $2"
		echo "actual: $1"
		return 1
	fi
}

metric_context() {
	jq -n --argjson arguments "$1" '{arguments: $arguments}'
}

server_service() {
	jq -n '{
		id: "0f3a6b1e-9c2d-4e8f-a1b2-c3d4e5f60718",
		attributes: {
			hostname: "np-my-db-0f3a6.cabc123xyz.us-west-2.rds.amazonaws.com",
			port: 5432,
			db_instance_identifier: "np-my-db-0f3a6",
			master_secret_arn: "arn:aws:secretsmanager:us-west-2:222222222222:secret:np-my-db-0f3a6-master"
		}
	}'
}
