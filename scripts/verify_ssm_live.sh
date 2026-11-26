#!/usr/bin/env bash
# P-07 实测门禁（apply 后）：get-parameters-by-path 断言全表与类型。
#
# 用法：
#   ./scripts/verify_ssm_live.sh
#   SNAPSHOT=ssm.json ./scripts/verify_ssm_live.sh
set -euo pipefail

REGION="${AWS_REGION:-ap-northeast-1}"
PATH_PREFIX="${CJ_SSM_PATH:-/cloudjian/}"

echo "==> path=${PATH_PREFIX} region=${REGION}"

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

# 架构 10.2：infra 写入的 11 条
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

# 前缀外不得出现（递归 path 已限 /cloudjian/，再断言无 drill 串）
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
