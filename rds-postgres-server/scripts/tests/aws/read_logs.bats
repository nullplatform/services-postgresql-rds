#!/usr/bin/env bats

load helpers

setup() {
	setup_mocks
}

@test "answers log requests with no entries and nothing else" {
	run_script read_logs
	[ "$status" -eq 0 ]
	assert_equal "$captured_stdout" '{"results":[]}'
	assert_equal "$captured_stderr" ""
}
