#!/bin/bash
set -uo pipefail

WRITE_LINK_OUTPUTS="$(cd "$(dirname "$0")/../rds-postgres-db/scripts/aws" && pwd)/write_link_outputs"
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
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/bin"

cat > "$SANDBOX/bin/np" <<'EOS'
#!/bin/bash
echo "$*" >> "$NP_LOG"
case "$1 $2" in
  "service read") echo "$FAKE_SERVICE_JSON" ;;
  "link patch")
    prev=""
    for a in "$@"; do
      if [ "$prev" = "--body" ]; then printf '%s' "$a" > "$PATCH_BODY"; fi
      prev="$a"
    done
    ;;
  *) echo "unexpected np call: $*" >&2; exit 1 ;;
esac
EOS
chmod +x "$SANDBOX/bin/np"

run_link_outputs() {
	rm -f "$SANDBOX/body.json" "$SANDBOX/np.log"
	PATH="$SANDBOX/bin:$PATH" \
		NP_LOG="$SANDBOX/np.log" \
		PATCH_BODY="$SANDBOX/body.json" \
		FAKE_SERVICE_JSON="$1" \
		CONTEXT='{"link":{"id":"link-1"},"service":{"id":"svc-1"}}' \
		bash "$WRITE_LINK_OUTPUTS" > "$SANDBOX/out.log" 2>&1
}

echo "write_link_outputs"

run_link_outputs '{"attributes":{"hostname":"pg.example.rds.amazonaws.com","port":5432,"username":"app_42","password":"s3cret","database_name":"app_42"}}'
STATUS=$?
check "exits 0" "$([ "$STATUS" -eq 0 ] && echo ok)" "$(cat "$SANDBOX/out.log")"
JDBC_URL=$(jq -r '.attributes.jdbc_url' "$SANDBOX/body.json" 2>/dev/null)
EXPECTED="jdbc:postgresql://pg.example.rds.amazonaws.com:5432/app_42?sslmode=require"
check "link body carries a ready to use jdbc url" "$([ "$JDBC_URL" = "$EXPECTED" ] && echo ok)" "got: $JDBC_URL"
check "jdbc url carries no password" "$([[ "$JDBC_URL" != *s3cret* ]] && echo ok)" "got: $JDBC_URL"
CONNECTION_STRING=$(jq -r '.attributes.connection_string' "$SANDBOX/body.json" 2>/dev/null)
EXPECTED_CONNECTION_STRING="postgresql://app_42:s3cret@pg.example.rds.amazonaws.com:5432/app_42?sslmode=require"
check "link body carries a connection string with credentials" "$([ "$CONNECTION_STRING" = "$EXPECTED_CONNECTION_STRING" ] && echo ok)" "got: $CONNECTION_STRING"

run_link_outputs '{"attributes":{"hostname":"pg.example.rds.amazonaws.com","port":5432,"username":"app_42","password":"p@ss:w/rd%","database_name":"app_42"}}'
CONNECTION_STRING=$(jq -r '.attributes.connection_string' "$SANDBOX/body.json" 2>/dev/null)
EXPECTED_CONNECTION_STRING="postgresql://app_42:p%40ss%3Aw%2Frd%25@pg.example.rds.amazonaws.com:5432/app_42?sslmode=require"
check "connection string percent-encodes the password" "$([ "$CONNECTION_STRING" = "$EXPECTED_CONNECTION_STRING" ] && echo ok)" "got: $CONNECTION_STRING"

run_link_outputs '{"attributes":{"hostname":"pg.example.rds.amazonaws.com","username":"app_42","password":"s3cret","database_name":"app_42"}}'
JDBC_URL=$(jq -r '.attributes.jdbc_url' "$SANDBOX/body.json" 2>/dev/null)
check "jdbc url falls back to port 5432" "$([ "$JDBC_URL" = "$EXPECTED" ] && echo ok)" "got: $JDBC_URL"

run_link_outputs '{"attributes":{"hostname":"pg.example.rds.amazonaws.com"}}'
check "no link patch without a username" "$(grep -q 'link patch' "$SANDBOX/np.log" || echo ok)" "$(cat "$SANDBOX/np.log")"

echo ""
echo "${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
