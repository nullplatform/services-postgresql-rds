#!/bin/bash
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DO_TOFU="$ROOT/rds-postgres-server/scripts/aws/do_tofu"
MODULE_DIR="$ROOT/rds-postgres-server/deployment"
PINNED="$(sed -n 's/^[[:space:]]*TOFU_VERSION="\([0-9.]*\)".*/\1/p' "$DO_TOFU" | head -1)"
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

db_instance_block() {
	awk '/^resource "aws_db_instance" "main"/,/^}/' "$1"
}

SANDBOX="$(mktemp -d)"
mkdir -p "$SANDBOX/bin"

cat > "$SANDBOX/bin/tofu" <<EOS
#!/bin/bash
if [ "\$1" = "version" ]; then echo "OpenTofu v${PINNED}"; exit 0; fi
[ "\$1" = "init" ] && exit 0
awk '/^resource "aws_db_instance" "main"/,/^}/' main.tf | grep -o 'prevent_destroy = [a-z]*' > "\$TOFU_SEEN"
exit 0
EOS
chmod +x "$SANDBOX/bin/tofu"

run_do_tofu() {
	local action="$1" out_dir="$SANDBOX/out-$1"
	mkdir -p "$out_dir"
	: > "$SANDBOX/seen"
	PATH="$SANDBOX/bin:$PATH" \
		TOFU_SEEN="$SANDBOX/seen" \
		OUTPUT_DIR="$out_dir" \
		TOFU_MODULE_DIR="$MODULE_DIR" \
		TOFU_INIT_VARIABLES="" \
		TOFU_VARIABLES="" \
		TOFU_ACTION="$action" \
		bash "$DO_TOFU" >/dev/null 2>&1
	cat "$SANDBOX/seen"
}

if db_instance_block "$MODULE_DIR/main.tf" | grep -q 'prevent_destroy = true'; then
	check "the rds instance refuses to be destroyed or replaced by default" ok
else
	check "the rds instance refuses to be destroyed or replaced by default" fail
fi

seen=$(run_do_tofu apply)
check "an apply keeps the instance protected" "$([ "$seen" = "prevent_destroy = true" ] && echo ok)" "saw '$seen'"

seen=$(run_do_tofu destroy)
check "a destroy lifts the protection so the service can be deleted" "$([ "$seen" = "prevent_destroy = false" ] && echo ok)" "saw '$seen'"

if db_instance_block "$MODULE_DIR/main.tf" | grep -q 'prevent_destroy = true'; then
	check "a destroy never edits the module in the repository" ok
else
	check "a destroy never edits the module in the repository" fail
fi

rm -rf "${SANDBOX:?}"

echo ""
echo "${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
