#!/usr/bin/env bats

load helpers

setup() {
	setup_mocks
	export CONTEXT
	CONTEXT=$(metric_context "$(jq -n --argjson service "$(server_service)" '{
		metric: "CPUUtilization",
		start_time: "2026-10-02T10:00:00.000Z",
		end_time: "2026-10-02T11:00:00.000Z",
		period: 300,
		service: $service
	}')")
}

run_metric() {
	export NOTIFICATION_ACTION="$1"
	run bash -c "bash '$SERVICE_PATH/entrypoint/metric' >'$BATS_TEST_TMPDIR/stdout' 2>'$BATS_TEST_TMPDIR/stderr'"
	captured_stdout=$(cat "$BATS_TEST_TMPDIR/stdout")
	captured_stderr=$(cat "$BATS_TEST_TMPDIR/stderr")
}

@test "answers metric:list with the metric list and touches neither np nor aws" {
	run_metric "metric:list"
	[ "$status" -eq 0 ]
	assert_equal "$(echo "$captured_stdout" | jq '.results | length')" "8"
	assert_equal "$captured_stderr" ""
	assert_equal "$(cat "$MOCK_LOG")" ""
}

@test "answers metric:data with only the metric result on the agent credentials" {
	run_metric "metric:data"
	[ "$status" -eq 0 ]
	assert_equal "$(echo "$captured_stdout" | jq -r '.metric')" "CPUUtilization"
	assert_equal "$(echo "$captured_stdout" | wc -l | tr -d ' ')" "1"
	assert_equal "$captured_stderr" ""
	assert_equal "$(grep -c '^aws ' "$MOCK_LOG")" "1"
	assert_not_contains "$(cat "$MOCK_LOG")" "np "
	assert_not_contains "$(cat "$MOCK_LOG")" "sts"
	assert_contains "$(cat "$MOCK_LOG")" "cloudwatch credentials: agent"
}

@test "answers log requests with no entries" {
	run bash "$SERVICE_PATH/entrypoint/log"
	[ "$status" -eq 0 ]
	assert_equal "$output" '{"results":[]}'
	assert_equal "$(cat "$MOCK_LOG")" ""
}

@test "routes metric notifications away from the service action runner" {
	export NP_ACTION_CONTEXT
	NP_ACTION_CONTEXT=$(jq -nc '{notification: {action: "metric:list", arguments: {}}}')
	run bash "$SERVICE_PATH/entrypoint/entrypoint" --service-path="$SERVICE_PATH"
	[ "$status" -eq 0 ]
	assert_equal "$(echo "$output" | jq '.results | length')" "8"
	assert_not_contains "$(cat "$MOCK_LOG")" "service-action exec"
}

@test "routes metric:data notifications through the single cloudwatch call" {
	export NP_ACTION_CONTEXT
	NP_ACTION_CONTEXT=$(echo "$CONTEXT" | jq -c '{notification: {action: "metric:data", arguments: .arguments}}')
	run bash "$SERVICE_PATH/entrypoint/entrypoint" --service-path="$SERVICE_PATH"
	[ "$status" -eq 0 ]
	assert_equal "$(echo "$output" | jq -r '.metric')" "CPUUtilization"
	assert_equal "$(grep -c '^aws ' "$MOCK_LOG")" "1"
	assert_not_contains "$(cat "$MOCK_LOG")" "np "
}

@test "routes log notifications away from the service action runner" {
	export NP_ACTION_CONTEXT
	NP_ACTION_CONTEXT=$(jq -nc '{notification: {action: "log:read", arguments: {}}}')
	run bash "$SERVICE_PATH/entrypoint/entrypoint" --service-path="$SERVICE_PATH"
	[ "$status" -eq 0 ]
	assert_equal "$output" '{"results":[]}'
	assert_not_contains "$(cat "$MOCK_LOG")" "service-action exec"
}

@test "still hands service notifications to the service action runner" {
	export NP_ACTION_CONTEXT
	NP_ACTION_CONTEXT=$(jq -nc '{notification: {action: "service:create", slug: "create", type: "custom", arguments: {}}}')
	run bash "$SERVICE_PATH/entrypoint/entrypoint" --service-path="$SERVICE_PATH"
	assert_contains "$(cat "$MOCK_LOG")" "np service-action exec --live-output --live-report --script=$SERVICE_PATH/entrypoint/service"
}

@test "hands link notifications to the link script" {
	export NP_ACTION_CONTEXT
	NP_ACTION_CONTEXT=$(jq -nc '{notification: {action: "link:create", slug: "create", type: "custom", link: {id: "l1"}, arguments: {}}}')
	run bash "$SERVICE_PATH/entrypoint/entrypoint" --service-path="$SERVICE_PATH"
	assert_contains "$(cat "$MOCK_LOG")" "--script=$SERVICE_PATH/entrypoint/link"
}
