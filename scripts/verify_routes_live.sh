#!/usr/bin/env bash
# 实测校验（apply 后）：apigatewayv2 get-routes 逐条校验。
# 归档快照（含授权方式）作为交接物。
#
# 用法：
#   ./scripts/verify_routes_live.sh            # 校验 + 打印快照
#   SNAPSHOT=routes.json ./scripts/verify_routes_live.sh   # 另存 JSON
set -euo pipefail

REGION="${AWS_REGION:-ap-northeast-1}"
AUTHORIZER_ID=$(aws ssm get-parameter --name /cloudjian/jwt-authorizer-id \
  --query 'Parameter.Value' --output text --region "$REGION")
API_ID=$(aws ssm get-parameter --name /cloudjian/api-id \
  --query 'Parameter.Value' --output text --region "$REGION")

echo "==> api=$API_ID authorizer=$AUTHORIZER_ID"

ROUTES_JSON=$(aws apigatewayv2 get-routes --api-id "$API_ID" --region "$REGION")

python - "$ROUTES_JSON" "$AUTHORIZER_ID" "${SNAPSHOT:-}" <<'PY'
import json, sys

routes = json.loads(sys.argv[1])
authorizer_id = sys.argv[2]
snapshot_path = sys.argv[3] if len(sys.argv) > 3 else ""

fail = 0
def ok(m): print("  ok:", m)
def err(m):
    global fail
    print("FAIL:", m, file=sys.stderr)
    fail = 1

# 硬性约束 1：无 $default
if any(r.get("RouteKey") == "$default" for r in routes):
    err("存在 $default 路由")
else:
    ok("无 $default")

# 按 key 索引
by_key = {r["RouteKey"]: r for r in routes}

# N8：NONE 且无 authorizer
n8 = by_key.get("GET /public/notes/{public_token}")
if not n8:
    err("缺少 N8 GET /public/notes/{public_token}")
elif n8.get("AuthorizationType") != "NONE":
    err(f"N8 AuthorizationType={n8.get('AuthorizationType')} (want NONE)")
elif n8.get("AuthorizerId"):
    err("N8 挂了 authorizer")
else:
    ok("N8 = NONE 且无 authorizer")

# 其余业务路由：JWT + authorizer_id 一致（N8 之外不允许 NONE）
expected_jwt = [
    "GET /notes", "POST /notes",
    "GET /notes/{note_id}", "PUT /notes/{note_id}", "DELETE /notes/{note_id}",
    "POST /trash/purge",
    "GET /notes/{note_id}/versions",
    "POST /notes/{note_id}/versions/{ts}/restore",
    "GET /search", "GET /dirs", "POST /dirs/move",
    "GET /shares", "POST /shares", "DELETE /shares/{share_id}",
    "POST /assets/presign", "POST /assets/register",
    "GET /assets/{asset_id}/url", "POST /assets/urls",
    "GET /admin/users", "POST /admin/users", "PATCH /admin/users/{sub}",
    "DELETE /admin/users/{sub}",
    "POST /admin/users/{sub}/reset",
    "POST /exports", "GET /exports/{job_id}",
    "POST /notes/{note_id}/visibility",
    "POST /profile/password",
]
missing = [k for k in expected_jwt if k not in by_key]
if missing:
    err(f"缺少路由: {missing}")
else:
    ok(f"核心路由齐全 ({len(expected_jwt)} 条)")

# 全量：除 N8 外每条路由都必须 JWT 且 authorizer 与 SSM 一致
bad = []
for k, r in by_key.items():
    if k in ("GET /public/notes/{public_token}", "$default"):
        continue
    if r.get("AuthorizationType") != "JWT":
        bad.append(f"{k}: type={r.get('AuthorizationType')}")
    elif r.get("AuthorizerId") != authorizer_id:
        bad.append(f"{k}: authorizer={r.get('AuthorizerId')}")
if bad:
    err("JWT 校验失败: " + "; ".join(bad))
else:
    ok("N8 之外全部路由均为 JWT 且 authorizer 与 SSM 一致")

# 删除普通用户：必须已挂载，且是 JWT
m4 = by_key.get("DELETE /admin/users/{sub}")
if not m4:
    err("缺少 DELETE /admin/users/{sub}（共同文档已列为正式接口）")
elif m4.get("AuthorizationType") != "JWT":
    err(f"DELETE /admin/users/{sub} AuthorizationType={m4.get('AuthorizationType')} (want JWT)")
else:
    ok("DELETE /admin/users/{sub} 已挂载且为 JWT")

# maintenance 不暴露
if any("maintenance" in (r.get("RouteKey") or "") for r in routes):
    err("路由含 maintenance")
else:
    ok("无 maintenance 路由")

# 快照（交接物）
snapshot = {
    "api_id": None,  # 由 shell 补
    "authorizer_id": authorizer_id,
    "routes": sorted([
        {
            "route_key": r["RouteKey"],
            "authorization_type": r.get("AuthorizationType"),
            "authorizer_id": r.get("AuthorizerId"),
            "target": r.get("Target"),
        }
        for r in routes
    ], key=lambda x: x["route_key"]),
}
if snapshot_path:
    with open(snapshot_path, "w", encoding="utf-8") as f:
        json.dump(snapshot, f, ensure_ascii=False, indent=2)
    print(f"  snapshot -> {snapshot_path}")

# 统计
jwt_n = sum(1 for r in routes if r.get("AuthorizationType") == "JWT")
none_n = sum(1 for r in routes if r.get("AuthorizationType") == "NONE")
print(f"  totals: jwt={jwt_n} none={none_n} all={len(routes)}")

sys.exit(fail)
PY
