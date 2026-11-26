#!/usr/bin/env bash
# P-06 结构门禁（apply 前可跑）：路由表必须满足红线。
# apply 后的 get-routes 实测见 verify_routes_live.sh。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF="$ROOT/modules/apigw/main.tf"
FAIL=0
err() { echo "FAIL: $*" >&2; FAIL=1; }
ok()  { echo "  ok: $*"; }

[[ -f "$TF" ]] || { err "缺少 $TF"; exit 1; }

# 1) 禁止 $default（只看 route_key 字面量，忽略注释）
if grep -E 'route_key\s*=\s*"\$default"' "$TF" >/dev/null \
  || grep -E 'key\s*=\s*"\$default"' "$TF" >/dev/null; then
  err "出现 \$default 路由（红线1：OPTIONS 会被拦成 401）"
else
  ok "无 \$default"
fi

# 2) N8 单独 NONE
if grep -q 'GET /public/notes/{public_token}' "$TF" \
  && grep -q 'auth = "NONE"' "$TF"; then
  ok "N8 路由存在且标记 NONE"
else
  err "N8 未注册为 NONE"
fi
# N8 行必须带 NONE（同行断言）
if grep 'public/notes' "$TF" | grep -q 'NONE'; then
  ok "N8 行 auth=NONE"
else
  err "N8 行不是 NONE"
fi

# 3) DELETE /admin/users 不挂载（只匹配路由 key 定义，忽略注释）
if grep -E 'key\s*=\s*"DELETE /admin/users' "$TF" >/dev/null \
  || grep -E 'route_key\s*=\s*"DELETE /admin/users' "$TF" >/dev/null; then
  err "挂载了 DELETE /admin/users（M4 不实现）"
else
  ok "M4 不挂载"
fi

# 4) maintenance 不出现集成
if grep -q 'cloudjian-maintenance-api' "$TF"; then
  err "maintenance 出现在 API 模块（不暴露）"
else
  ok "无 maintenance 集成"
fi

# 5) 显式 authorization_type=JWT（防默认 NONE）
jwt_count=$(grep -c 'auth = "JWT"' "$TF" || true)
if [[ "$jwt_count" -ge 30 ]]; then
  ok "JWT 路由数 = $jwt_count (≥30)"
else
  err "JWT 路由数异常：$jwt_count"
fi

# 6) 集成必须指向 :live 别名
if grep -q ':live"' "$TF" || grep -q ':live`' "$TF"; then
  ok "集成 URI 指向 live 别名"
else
  # ARN 拼在 local.fn_arn
  if grep -q 'function:cloudjian-.*:live' "$TF"; then
    ok "集成 URI 指向 live 别名"
  else
    err "集成未指向 live 别名"
  fi
fi

# 7) CORS 含 if-match 与 etag
grep -q 'if-match' "$TF" && ok "AllowHeaders 含 if-match" || err "缺 if-match"
grep -q 'etag' "$TF" && ok "ExposeHeaders 含 etag" || err "缺 etag expose"

# 8) 授权器 Audience=client id、Issuer=池
grep -q 'audience = \[var.cognito_client_id\]' "$TF" \
  && ok "Audience=client_id" || err "Audience 不是 client_id"
grep -q 'cognito-idp' "$TF" && ok "Issuer 指向用户池" || err "Issuer 缺失"

# 9) 一路由一函数（契约 §2.6）：37 条路由、37 个不同函数、每函数恰接 1 条
python - "$TF" <<'PY' || FAIL=1
import re, sys, pathlib
tf = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
fail = 0
def err(m):
    global fail
    print("FAIL:", m, file=sys.stderr)
    fail = 1
def ok(m):
    print("  ok:", m)

fn_block = tf.split("function_names = [", 1)[1].split("\n  ]", 1)[0]
names = re.findall(r'"(cloudjian-[a-z0-9-]+-api)"', fn_block)
route_fns = re.findall(r'fn = "(cloudjian-[a-z0-9-]+-api)"', tf)
if len(route_fns) != 37:
    err(f"路由数 {len(route_fns)} != 37")
else:
    ok("路由数 = 37")
if len(names) != 37 or len(set(names)) != 37:
    err(f"函数清单 {len(names)} 个（去重 {len(set(names))}）!= 37")
else:
    ok("函数清单 = 37（无重复）")
if len(route_fns) != len(set(route_fns)):
    dup = {n for n in route_fns if route_fns.count(n) > 1}
    err(f"有函数承接多条路由：{sorted(dup)}")
else:
    ok("每个函数只承接 1 条路由")
if set(route_fns) != set(names):
    err(f"路由引用与函数清单不一致：差集 {sorted(set(route_fns) ^ set(names))}")
else:
    ok("路由引用与函数清单一致")
sys.exit(fail)
PY

if [[ "$FAIL" -ne 0 ]]; then
  echo "verify_routes_structure: FAILED" >&2
  exit 1
fi
echo "verify_routes_structure: PASSED"
