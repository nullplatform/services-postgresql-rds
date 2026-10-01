#!/bin/bash
set -uo pipefail

BUILD_CONTEXT="$(cd "$(dirname "$0")/../rds-postgres-server/scripts/aws" && pwd)/build_context"
SERVICE_ID="11111111-2222-3333-4444-555555555555"
ACCOUNT_NRN="organization=1:account=2"
SERVICE_NRN="${ACCOUNT_NRN}:namespace=3:application=4"
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
  if [ -n "${FAKE_STATE_FILE:-}" ]; then
    cp "$FAKE_STATE_FILE" "$4"
    exit 0
  fi
  echo "fatal error: An error occurred (404) when calling the HeadObject operation: Key \"$3\" does not exist" >&2
  exit 1
fi
exit 0
EOS

cat > "$SANDBOX/bin/np" <<EOS
#!/bin/bash
echo "np \$*" >> "\$NP_LOG"
[ "\$1 \$2" = "provider list" ] || { echo '{}'; exit 0; }
nrn=""
category=""
dimensions=""
prev=""
for a in "\$@"; do
  case "\$prev" in
    --nrn) nrn="\$a" ;;
    --categories) category="\$a" ;;
    --dimensions) dimensions="\$a" ;;
    --limit) [ -n "\$category" ] && { echo '{"error":"cannot use flag limit when using categories flag"}'; exit 1; } ;;
  esac
  prev="\$a"
done
if [ -z "\$category" ] || [[ "\$nrn" != "${ACCOUNT_NRN}"* ]]; then
  echo '{"results":[]}'
  exit 0
fi
case "\$category:\$dimensions" in
  cloud-providers:*) echo '{"results":[{"attributes":{"account":{"region":"sa-east-1"}}}]}' ;;
  vpc:environment:prod) echo '{"results":[{"attributes":{"vpc":{"id":"vpc-prod","subnets":["subnet-prod-a","subnet-prod-b"]}}}]}' ;;
  vpc:*) echo "{\"results\":[{\"attributes\":{\"vpc\":{\"id\":\"vpc-default\",\"subnets\":\${FAKE_SUBNETS:-[\"subnet-a\",\"subnet-b\"]}}}}]}" ;;
  *) echo '{"results":[]}' ;;
esac
EOS

cat > "$SANDBOX/run_build_context.sh" <<'EOS'
#!/bin/bash
source "$1" >/dev/null 2>"$2"
printf '%s\n' "${TOFU_VARIABLES-}"
EOS

chmod +x "$SANDBOX/bin/aws" "$SANDBOX/bin/np" "$SANDBOX/run_build_context.sh"

tofu_variables_for() {
	local context="$1" state_file="${2:-}"
	: > "$SANDBOX/np.log"
	(
		cd "$SANDBOX" || exit 1
		PATH="$SANDBOX/bin:$PATH" \
			NP_LOG="$SANDBOX/np.log" \
			FAKE_STATE_FILE="$state_file" \
			CONTEXT="$context" \
			VALUES="$SANDBOX/values.yaml" \
			SERVICE_PATH="$SANDBOX" \
			RDS_POSTGRES_S3_STATE_BUCKET="state-bucket" \
			"$SANDBOX/run_build_context.sh" "$BUILD_CONTEXT" "$SANDBOX/err.log"
	)
}

context_with() {
	local nrn="$1" dimensions="$2"
	jq -nc --arg id "$SERVICE_ID" --arg nrn "$nrn" --argjson dims "$dimensions" \
		'{type: "create", entity_nrn: $nrn, service: {id: $id, name: "orders", nrn: $nrn, dimensions: $dims, attributes: {}}, parameters: {}}'
}

out=$(tofu_variables_for "$(context_with "$SERVICE_NRN" '{"environment":"prod"}')")
if [[ "$out" == *"-var=vpc_id=vpc-prod "* ]] && [[ "$out" == *"-var=region=sa-east-1 "* ]]; then
	check "the vpc and region come from the provider matching the service dimensions" ok
else
	check "the vpc and region come from the provider matching the service dimensions" fail "$out $(cat "$SANDBOX/err.log")"
fi

calls=$(grep -c -- "provider list --nrn ${SERVICE_NRN} --categories cloud-providers --dimensions environment:prod" "$SANDBOX/np.log")
check "the region is looked up by entity nrn, category and dimensions" "$([ "$calls" = "1" ] && echo ok)" "$(cat "$SANDBOX/np.log")"

calls=$(grep -c -- "provider list --nrn ${SERVICE_NRN} --categories vpc --dimensions environment:prod" "$SANDBOX/np.log")
check "the vpc is looked up by entity nrn, category and dimensions" "$([ "$calls" = "1" ] && echo ok)" "$(cat "$SANDBOX/np.log")"

out=$(tofu_variables_for "$(context_with "$SERVICE_NRN" '{}')")
if [[ "$out" == *"-var=vpc_id=vpc-default "* ]] && ! grep -q -- "--dimensions" "$SANDBOX/np.log"; then
	check "a service without dimensions omits the dimensions flag" ok
else
	check "a service without dimensions omits the dimensions flag" fail "$out $(cat "$SANDBOX/np.log")"
fi

out=$(tofu_variables_for "$(context_with "organization=9:account=8:namespace=7" '{}')")
if [[ -z "$out" ]] && grep -q "no cloud-providers provider with account.region found" "$SANDBOX/err.log"; then
	check "a missing provider stops before tofu" ok
else
	check "a missing provider stops before tofu" fail "$out"
fi

LINK_NRN="${ACCOUNT_NRN}:namespace=3:application=9"
LINK_CONTEXT=$(jq -nc --arg id "$SERVICE_ID" --arg nrn "$SERVICE_NRN" --arg link_nrn "$LINK_NRN" \
	'{type: "create", entity_nrn: $link_nrn, service: {id: $id, name: "orders", nrn: $nrn, attributes: {}}, link: {id: "l1"}, parameters: {}}')
out=$(tofu_variables_for "$LINK_CONTEXT")
if [[ "$out" == *"-var=vpc_id=vpc-default "* ]] && grep -q -- "--nrn ${LINK_NRN} " "$SANDBOX/np.log" && ! grep -q -- "--nrn ${SERVICE_NRN} " "$SANDBOX/np.log"; then
	check "a link resolves providers from its entity nrn" ok
else
	check "a link resolves providers from its entity nrn" fail "$out $(cat "$SANDBOX/np.log")"
fi

jq -n '{version: 4, resources: [
	{mode: "managed", type: "aws_security_group", name: "rds", instances: [{attributes: {vpc_id: "vpc-original"}}]},
	{mode: "managed", type: "aws_db_instance", name: "main", instances: [{attributes: {arn: "arn:aws:rds:us-west-2:111111111111:db:np-orders", kms_key_id: ""}}]}]}' > "$SANDBOX/state.json"
UPDATE_CONTEXT=$(context_with "$SERVICE_NRN" '{"environment":"prod"}' | jq -c '.type = "update"')
out=$(tofu_variables_for "$UPDATE_CONTEXT" "$SANDBOX/state.json")
if [[ "$out" == *"-var=vpc_id=vpc-original "* ]] && [[ "$out" == *"-var=region=us-west-2 "* ]] && grep -q "keeping vpc-original" "$SANDBOX/err.log"; then
	check "an existing instance keeps the vpc and region in its state" ok
else
	check "an existing instance keeps the vpc and region in its state" fail "$out $(cat "$SANDBOX/err.log")"
fi

NETWORK_TFVARS="/tmp/np-service-${SERVICE_ID}/network.auto.tfvars.json"

tofu_variables_for "$(context_with "$SERVICE_NRN" '{"environment":"prod"}')" >/dev/null
subnets=$(jq -c '.subnet_ids' "$NETWORK_TFVARS" 2>/dev/null)
check "the vpc provider subnets reach tofu through an auto tfvars file" "$([ "$subnets" = '["subnet-prod-a","subnet-prod-b"]' ] && echo ok)" "got '$subnets'"

out=$(FAKE_SUBNETS='[]' tofu_variables_for "$(context_with "$SERVICE_NRN" '{}')")
if [[ -z "$out" ]] && grep -q "has no vpc.subnets" "$SANDBOX/err.log"; then
	check "a vpc provider without subnets stops before tofu" ok
else
	check "a vpc provider without subnets stops before tofu" fail "$out $(cat "$SANDBOX/err.log")"
fi

out=$(FAKE_SUBNETS='["subnet-a"]' tofu_variables_for "$(context_with "$SERVICE_NRN" '{}')")
if [[ -z "$out" ]] && grep -q "needs at least two" "$SANDBOX/err.log"; then
	check "a vpc provider with a single subnet stops before tofu" ok
else
	check "a vpc provider with a single subnet stops before tofu" fail "$out $(cat "$SANDBOX/err.log")"
fi

jq -n '{version: 4, resources: [
	{mode: "managed", type: "aws_security_group", name: "rds", instances: [{attributes: {vpc_id: "vpc-prod"}}]},
	{mode: "managed", type: "aws_db_subnet_group", name: "main", instances: [{attributes: {subnet_ids: ["subnet-old-2", "subnet-old-1"]}}]}]}' > "$SANDBOX/state.json"
tofu_variables_for "$UPDATE_CONTEXT" "$SANDBOX/state.json" >/dev/null
subnets=$(jq -c '.subnet_ids' "$NETWORK_TFVARS" 2>/dev/null)
if [ "$subnets" = '["subnet-old-1","subnet-old-2"]' ] && grep -q "keeping them" "$SANDBOX/err.log"; then
	check "an existing instance keeps the subnets in its state" ok
else
	check "an existing instance keeps the subnets in its state" fail "got '$subnets' $(cat "$SANDBOX/err.log")"
fi

jq -n '{version: 4, resources: [
	{mode: "managed", type: "aws_security_group", name: "rds", instances: [{attributes: {vpc_id: "vpc-prod"}}]},
	{mode: "managed", type: "aws_db_subnet_group", name: "main", instances: [{attributes: {subnet_ids: ["subnet-prod-b", "subnet-prod-a"]}}]}]}' > "$SANDBOX/state.json"
tofu_variables_for "$UPDATE_CONTEXT" "$SANDBOX/state.json" >/dev/null
if grep -q "WARNING" "$SANDBOX/err.log"; then
	check "the same subnets in another order are not reported as a change" fail "$(cat "$SANDBOX/err.log")"
else
	check "the same subnets in another order are not reported as a change" ok
fi

rm -rf "${SANDBOX:?}" "/tmp/np-service-${SERVICE_ID:?}"

echo ""
echo "${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
