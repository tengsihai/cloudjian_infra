#!/usr/bin/env bash
# 实测校验（apply 后）：get-parameters-by-path 校验全表与类型。
#
# 用法：
#   ./scripts/verify_ssm_live.sh
#   SNAPSHOT=ssm.json ./scripts/verify_ssm_live.sh
set -euo pipefail

REGION="${AWS_REGION:-ap-northeast-1}"
PATH_PREFIX="${CJ_SSM_PATH:-/cloudjian/}"

echo "==> path=${PATH_PREFIX} region=${REGION}"

# ————————————————— 值一致性：参数必须指向真实存在且互相自洽的资源 —————————————————
# 文档 05 §5：线上参数「值与模块输出一致」。这里不读 state，直接回查资源。
CROSS_FAIL=0
cerr() { echo "FAIL: $*" >&2; CROSS_FAIL=1; }
cok()  { echo "  ok: $*"; }
pget() { aws ssm get-parameter --name "/cloudjian/$1" --region "$REGION" \
           --query Parameter.Value --output text 2>/dev/null || true; }

BUCKET=$(pget bucket)
POOL=$(pget user-pool-id)
CLIENT=$(pget client-id)
API=$(pget api-id)
AUTHZ=$(pget jwt-authorizer-id)
CDN_ARN=$(pget cdn-arn)
CDN_DOMAIN=$(pget cdn-domain)
API_URL=$(pget api-url)
ROLE_ARN=$(pget lambda-exec-role-arn)
REGION_VAL=$(pget region)

[[ "$REGION_VAL" == "$REGION" ]] && cok "region 与环境一致" || cerr "region=$REGION_VAL 与环境 $REGION 不一致"

if [[ -n "$BUCKET" ]] && aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
  cok "bucket=$BUCKET 存在"
else
  cerr "bucket=$BUCKET 不可访问"
fi

if [[ -n "$POOL" ]] && aws cognito-idp describe-user-pool --user-pool-id "$POOL" \
     --region "$REGION" >/dev/null 2>&1; then
  cok "user-pool-id 存在"
else
  cerr "user-pool-id=$POOL 不存在"
fi

if [[ -n "$POOL" && -n "$CLIENT" ]] && aws cognito-idp describe-user-pool-client \
     --user-pool-id "$POOL" --client-id "$CLIENT" --region "$REGION" >/dev/null 2>&1; then
  cok "client-id 属于该用户池"
else
  cerr "client-id=$CLIENT 不属于用户池 $POOL"
fi

if [[ -n "$API" ]]; then
  EP=$(aws apigatewayv2 get-api --api-id "$API" --region "$REGION" \
        --query ApiEndpoint --output text 2>/dev/null || true)
  if [[ -z "$EP" ]]; then
    cerr "api-id=$API 不存在"
  elif [[ "$API_URL" == "${EP}/"* ]]; then
    cok "api-url 指向该 API（$API_URL）"
  else
    cerr "api-url=$API_URL 与 ApiEndpoint=$EP 不匹配"
  fi
  if [[ -n "$AUTHZ" ]]; then
    JWT=$(aws apigatewayv2 get-authorizer --api-id "$API" --authorizer-id "$AUTHZ" \
          --region "$REGION" --query JwtConfiguration --output json 2>/dev/null || true)
    if [[ -z "$JWT" ]]; then
      cerr "jwt-authorizer-id=$AUTHZ 不属于该 API"
    elif echo "$JWT" | grep -q "$POOL" && echo "$JWT" | grep -q "$CLIENT"; then
      cok "JWT 授权器 issuer/audience 与本池、本客户端一致"
    else
      cerr "JWT 授权器 issuer/audience 与 user-pool-id/client-id 不一致: $JWT"
    fi
  else
    cerr "缺 jwt-authorizer-id"
  fi
else
  cerr "缺 api-id"
fi

if [[ -n "$CDN_ARN" ]]; then
  DIST_ID="${CDN_ARN##*/}"
  ACTUAL_DOMAIN=$(aws cloudfront get-distribution --id "$DIST_ID" \
    --query 'Distribution.DomainName' --output text 2>/dev/null || true)
  if [[ -z "$ACTUAL_DOMAIN" || "$ACTUAL_DOMAIN" == "None" ]]; then
    cerr "cdn-arn=$CDN_ARN 指向的分发不存在"
  elif [[ "$ACTUAL_DOMAIN" == "$CDN_DOMAIN" ]]; then
    cok "cdn-domain 与该分发一致（$CDN_DOMAIN）"
  else
    cerr "cdn-domain=$CDN_DOMAIN 与分发实际域名 $ACTUAL_DOMAIN 不一致"
  fi
else
  cerr "缺 cdn-arn"
fi

if [[ -n "$ROLE_ARN" ]] && aws iam get-role --role-name "${ROLE_ARN##*/}" >/dev/null 2>&1; then
  cok "lambda-exec-role-arn 存在"
else
  cerr "lambda-exec-role-arn=$ROLE_ARN 不存在"
fi


PARAMS_JSON=$(aws ssm get-parameters-by-path \
  --path "$PATH_PREFIX" \
  --recursive \
  --region "$REGION" \
  --query 'Parameters[].{name:Name,type:Type,value:Value}' \
  --output json)

python - "$PARAMS_JSON" "${SNAPSHOT:-}" <<'PY'
import json, sys

params = json.loads(sys.argv[1])
snapshot_path = sys.argv[2] if len(sys.argv) > 2 else ""

fail = 0
def ok(m): print("  ok:", m)
def err(m):
    global fail
    print("FAIL:", m, file=sys.stderr)
    fail = 1

by_name = {p["name"]: p for p in params}

# infra 写入的 11 条
required = [
    "/cloudjian/bucket",
    "/cloudjian/cdn-domain",
    "/cloudjian/cdn-arn",
    "/cloudjian/api-url",
    "/cloudjian/user-pool-id",
    "/cloudjian/client-id",
    "/cloudjian/region",
    "/cloudjian/lambda-exec-role-arn",
    "/cloudjian/lambda-alias",
    "/cloudjian/api-id",
    "/cloudjian/jwt-authorizer-id",
]
missing = [n for n in required if n not in by_name]
if missing:
    err(f"缺参: {missing}（先跑 infra apply）")
else:
    ok(f"infra 11 条齐全")

# release/archive：infra 唯一写方，键应存在（值可被 main 流水线覆盖）
arch = "/cloudjian/release/archive"
if arch in by_name:
    ok("release/archive 存在")
else:
    err("缺 release/archive（infra 首 apply 应创建）")

# 类型必须是 String（非 SecureString/StringList）
bad_type = [n for n, p in by_name.items() if p.get("type") != "String"]
if bad_type:
    err(f"非 String 类型: {bad_type}")
else:
    ok("全部 String")

# 非空值
empty = [n for n, p in by_name.items() if not (p.get("value") or "").strip()]
if empty:
    err(f"空值参数: {empty}")
else:
    ok("无空值")

# 关键派生值形状
def val(key):
    return (by_name.get(f"/cloudjian/{key}") or {}).get("value", "")

alias = val("lambda-alias")
if alias != "live":
    err(f"lambda-alias={alias!r} (want 'live')")
else:
    ok("lambda-alias=live")

api_url = val("api-url")
if not api_url.startswith("https://") or not api_url.endswith("/dev"):
    err(f"api-url 形状异常: {api_url!r}（应 https://…/dev）")
else:
    ok("api-url 含 stage /dev")

region = val("region")
if region != "ap-northeast-1":
    err(f"region={region!r}")
else:
    ok("region=ap-northeast-1")

# 前缀外不得出现（递归 path 已限 /cloudjian/，再校验无 drill 串）
drill = [n for n in by_name if "drill" in n]
if drill:
    err(f"线上路径混入 drill 参数: {drill}")
else:
    ok("无 drill 前缀混入")

# 快照交接物
if snapshot_path:
    with open(snapshot_path, "w", encoding="utf-8") as f:
        json.dump(
            {
                "path": "/cloudjian/",
                "parameters": sorted(
                    [{"name": p["name"], "type": p["type"]} for p in params],
                    key=lambda x: x["name"],
                ),
            },
            f,
            ensure_ascii=False,
            indent=2,
        )
    print(f"  snapshot -> {snapshot_path}")

print(f"  totals: {len(params)}")
sys.exit(fail)
PY

if [[ "$CROSS_FAIL" -ne 0 ]]; then
  echo "verify_ssm_live: 参数值一致性 FAILED" >&2
  exit 1
fi
