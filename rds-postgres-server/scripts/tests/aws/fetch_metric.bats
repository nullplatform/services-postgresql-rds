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
		service_id: "0f3a6b1e-9c2d-4e8f-a1b2-c3d4e5f60718",
		service: $service
	}')")
}

@test "queries cloudwatch for the instance with the window, period and statistic of the metric" {
	run_script fetch_metric
	[ "$status" -eq 0 ]
	assert_equal "$(grep '^aws ' "$MOCK_LOG")" "aws cloudwatch get-metric-statistics --region us-west-2 --namespace AWS/RDS --metric-name CPUUtilization --dimensions Name=DBInstanceIdentifier,Value=np-my-db-0f3a6 --start-time 2026-10-02T10:00:00.000Z --end-time 2026-10-02T11:00:00.000Z --period 300 --statistics Average --output json"
}

@test "returns the datapoints sorted by timestamp in the telemetry format" {
	export MOCK_CW_RESPONSE='{"Label":"CPUUtilization","Datapoints":[{"Timestamp":"2026-10-02T10:05:00+00:00","Average":91.5,"Unit":"Percent"},{"Timestamp":"2026-10-02T10:00:00+00:00","Average":8,"Unit":"Percent"}]}'
	run_script fetch_metric
	[ "$status" -eq 0 ]
	assert_equal "$captured_stdout" '{"metric":"CPUUtilization","type":"gauge","period_in_seconds":300,"unit":"percent","results":[{"selector":{"db_instance_identifier":"np-my-db-0f3a6"},"data":[{"timestamp":"2026-10-02T10:00:00+00:00","value":8},{"timestamp":"2026-10-02T10:05:00+00:00","value":91.5}]}]}'
}

@test "prints only the result and logs nothing when the query succeeds" {
	export MOCK_CW_RESPONSE='{"Label":"CPUUtilization","Datapoints":[{"Timestamp":"2026-10-02T10:00:00+00:00","Average":8}]}'
	run_script fetch_metric
	[ "$status" -eq 0 ]
	assert_equal "$(echo "$captured_stdout" | wc -l | tr -d ' ')" "1"
	echo "$captured_stdout" | jq -e '.results[0].data[0].value == 8'
	assert_equal "$captured_stderr" ""
}

@test "uses the statistic and unit that belong to each metric" {
	for row in "CPUUtilization:Average:percent" "DatabaseConnections:Maximum:count" "FreeStorageSpace:Minimum:bytes" "FreeableMemory:Minimum:bytes" "ReadIOPS:Average:count" "WriteIOPS:Average:count" "ReadLatency:Average:seconds" "WriteLatency:Average:seconds"; do
		IFS=: read -r metric statistic unit <<<"$row"
		CONTEXT=$(echo "$CONTEXT" | jq --arg metric "$metric" '.arguments.metric = $metric')
		: >"$MOCK_LOG"
		run_script fetch_metric
		[ "$status" -eq 0 ]
		assert_contains "$(cat "$MOCK_LOG")" "--metric-name ${metric} "
		assert_contains "$(cat "$MOCK_LOG")" "--statistics ${statistic} "
		assert_contains "$(cat "$MOCK_LOG")" "--namespace AWS/RDS "
		assert_equal "$(echo "$captured_stdout" | jq -r '.unit')" "$unit"
	done
}

@test "reads the statistic of the metric from each datapoint" {
	export MOCK_CW_RESPONSE='{"Datapoints":[{"Timestamp":"2026-10-02T10:00:00+00:00","Minimum":5000000,"Average":7000000}]}'
	CONTEXT=$(echo "$CONTEXT" | jq '.arguments.metric = "FreeStorageSpace"')
	run_script fetch_metric
	[ "$status" -eq 0 ]
	assert_equal "$(echo "$captured_stdout" | jq -c '[.results[0].data[].value]')" '[5000000]'
}

@test "rounds the period up to a multiple of sixty seconds" {
	CONTEXT=$(echo "$CONTEXT" | jq '.arguments.period = 90')
	run_script fetch_metric
	[ "$status" -eq 0 ]
	assert_contains "$(cat "$MOCK_LOG")" "--period 120 "
	assert_equal "$(echo "$captured_stdout" | jq '.period_in_seconds')" "120"

	CONTEXT=$(echo "$CONTEXT" | jq '.arguments.period = 15')
	run_script fetch_metric
	assert_contains "$(cat "$MOCK_LOG")" "--period 60 "

	CONTEXT=$(echo "$CONTEXT" | jq 'del(.arguments.period)')
	run_script fetch_metric
	[ "$status" -eq 0 ]
	assert_equal "$(echo "$captured_stdout" | jq '.period_in_seconds')" "60"
}

@test "falls back to the last hour when the request has no window" {
	CONTEXT=$(echo "$CONTEXT" | jq 'del(.arguments.start_time, .arguments.end_time)')
	run_script fetch_metric
	[ "$status" -eq 0 ]
	[[ "$(cat "$MOCK_LOG")" =~ --start-time\ [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z\ --end-time\ [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z ]]
}

@test "returns an empty series without calling cloudwatch or np while the instance does not exist yet" {
	CONTEXT=$(echo "$CONTEXT" | jq 'del(.arguments.service.attributes)')
	run_script fetch_metric
	[ "$status" -eq 0 ]
	assert_equal "$captured_stdout" '{"metric":"CPUUtilization","type":"gauge","period_in_seconds":300,"unit":"percent","results":[]}'
	assert_equal "$captured_stderr" ""
	assert_equal "$(cat "$MOCK_LOG")" ""
}

@test "returns an empty series when only the hostname is missing" {
	CONTEXT=$(echo "$CONTEXT" | jq 'del(.arguments.service.attributes.hostname)')
	run_script fetch_metric
	[ "$status" -eq 0 ]
	assert_equal "$(echo "$captured_stdout" | jq -c '.results')" '[]'
	assert_equal "$(cat "$MOCK_LOG")" ""
}

@test "fails on an unknown metric" {
	CONTEXT=$(echo "$CONTEXT" | jq '.arguments.metric = "NetworkReceiveThroughput"')
	run_script fetch_metric
	[ "$status" -ne 0 ]
	assert_contains "$captured_stderr" "unknown metric 'NetworkReceiveThroughput'"
	assert_equal "$(cat "$MOCK_LOG")" ""
}

@test "fails on a malformed time window" {
	for field in start_time end_time; do
		CONTEXT=$(echo "$CONTEXT" | jq --arg field "$field" '.arguments[$field] = "yesterday --region evil"')
		run_script fetch_metric
		[ "$status" -ne 0 ]
		assert_contains "$captured_stderr" "is not a UTC ISO 8601 timestamp"
		assert_equal "$(cat "$MOCK_LOG")" ""
	done
}

@test "fails when the hostname does not carry a valid region" {
	CONTEXT=$(echo "$CONTEXT" | jq '.arguments.service.attributes.hostname = "db.abc.bad region.rds.amazonaws.com"')
	run_script fetch_metric
	[ "$status" -ne 0 ]
	assert_contains "$captured_stderr" "is not an AWS region"
	assert_equal "$(cat "$MOCK_LOG")" ""
}

@test "fails when the instance identifier is not a valid identifier" {
	CONTEXT=$(echo "$CONTEXT" | jq '.arguments.service.attributes.db_instance_identifier = "db,Name=x;touch"')
	run_script fetch_metric
	[ "$status" -ne 0 ]
	assert_contains "$captured_stderr" "is not a valid DB instance identifier"
	assert_equal "$(cat "$MOCK_LOG")" ""
}

@test "fails instead of returning an empty series when cloudwatch rejects the query" {
	export MOCK_CW_EXIT=254
	run_script fetch_metric
	[ "$status" -ne 0 ]
	assert_contains "$captured_stderr" "AccessDenied"
	assert_contains "$captured_stderr" "CloudWatch rejected the CPUUtilization query for np-my-db-0f3a6 in us-west-2"
}

@test "makes exactly one aws call and none to np for every metric" {
	for metric in CPUUtilization DatabaseConnections FreeStorageSpace FreeableMemory ReadIOPS WriteIOPS ReadLatency WriteLatency; do
		CONTEXT=$(echo "$CONTEXT" | jq --arg metric "$metric" '.arguments.metric = $metric')
		: >"$MOCK_LOG"
		run_script fetch_metric
		[ "$status" -eq 0 ]
		assert_equal "$(grep -c '^aws ' "$MOCK_LOG")" "1"
		assert_contains "$(grep '^aws ' "$MOCK_LOG")" "aws cloudwatch get-metric-statistics"
		assert_not_contains "$(cat "$MOCK_LOG")" "np "
	done
}

@test "uses the aws_profile from values.yaml when set" {
	printf 'aws_profile: "sso-rds"\nother: x\n' >"$VALUES"
	cat >"$BATS_TEST_TMPDIR/bin/aws" <<MOCK
#!/bin/bash
echo "profile=\${AWS_PROFILE:-none}" >>"$MOCK_LOG"
echo '{"Datapoints":[]}'
MOCK
	run_script fetch_metric
	[ "$status" -eq 0 ]
	assert_contains "$(cat "$MOCK_LOG")" "profile=sso-rds"
}

@test "never runs a command smuggled in a non-string request field" {
	marker="$BATS_TEST_TMPDIR/pwned"
	for field in metric start_time end_time period; do
		CONTEXT=$(echo "$CONTEXT" | jq --arg field "$field" --arg marker "$marker" '.arguments[$field] = ["x", "touch", $marker]')
		run_script fetch_metric
		[ ! -e "$marker" ]
	done
	for field in db_instance_identifier hostname; do
		CONTEXT=$(echo "$CONTEXT" | jq --arg field "$field" --arg marker "$marker" '.arguments.service.attributes[$field] = ["x", "touch", $marker]')
		run_script fetch_metric
		[ ! -e "$marker" ]
	done
}
