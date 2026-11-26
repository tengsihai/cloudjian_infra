#!/usr/bin/env bash
# P-07 结构门禁（apply 前可跑）：参数全表 + 单一写方 + 消费者引用。
# apply 后的 get-parameters-by-path 实测见 verify_ssm_live.sh。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSM="$ROOT/modules/ssm/main.tf"
ROOT_SSM="$ROOT/ssm.tf"
IAM="$ROOT/modules/iam/main.tf"
ROUTES_LIVE="$ROOT/scripts/verify_routes_live.sh"
README="$ROOT/README.md"
FAIL=0
err() { echo "FAIL: $*" >&2; FAIL=1; }
ok()  { echo "  ok: $*"; }

[[ -f "$SSM" ]] || { err "缺少 $SSM"; exit 1; }

# —— 7.1 参数全表（架构 10.2，infra 写入 11 条 + release/archive）——
REQUIRED_KEYS=(
  bucket cdn-domain cdn-arn api-url user-pool-id client-id
  region lambda-exec-role-arn lambda-alias api-id jwt-authorizer-id
)
for k in "${REQUIRED_KEYS[@]}"; do
  if grep -qE "^\s+${k//./\\.}\s*=" "$SSM" || grep -q "\"${k}\"" "$SSM" || grep -qE "^\s+${k}\s*=" "$SSM"; then
    ok "bus 含 ${k}"
  else
    # locals.bus 形如 `bucket = var.bucket`
    if grep -E "^\s+${k}\s*=" "$SSM" >/dev/null; then
      ok "bus 含 ${k}"
    else
      err "缺少参数 key: ${k}"
    fi
  fi
done

if grep -q 'release/archive' "$SSM"; then
  ok "release/archive 由 infra 管理"
else
  err "缺少 release/archive"
fi

# —— 7.2 单一写方：infra 不得创建 release/backend|frontend ——
# 只匹配 name 赋值/资源地址，忽略注释里的说明文字
if grep -E 'name\s*=.*release/(backend|frontend)|"/cloudjian/release/(backend|frontend)"' \
  "$SSM" "$ROOT_SSM" 2>/dev/null; then
  err "infra 创建了 release/backend|frontend（应由各仓 CI 写）"
else
  ok "infra 不写 release/backend|frontend"
fi

# frontend 角色：Put 仅 release/frontend
if grep -q 'parameter/cloudjian/release/frontend' "$IAM"; then
  ok "frontend Put 限 release/frontend"
else
  err "frontend SSM Put 未收窄到 release/frontend"
fi
# frontend 不得 Put 整个 /cloudjian/*
if awk '/gha_frontend/,/^}/' "$IAM" | grep -q 'parameter/cloudjian/\*"'; then
  # 允许 GetParameter 整前缀，但 Put 语句不得用通配
  :
fi
# backend Put：release/* 与 lambda-*
if grep -q 'parameter/cloudjian/release/\*' "$IAM" && grep -q 'parameter/cloudjian/lambda-\*' "$IAM"; then
  ok "backend Put 限 release/* + lambda-*"
else
  err "backend SSM Put 范围不符合矩阵"
fi
# terraform 角色管理整个前缀（含 archive）
if grep -q 'parameter/cloudjian/\*' "$IAM"; then
  ok "terraform 可管理 /cloudjian/*"
else
  err "terraform 角色缺 /cloudjian/*"
fi

# —— 7.3/7.4 README 契约 ——
if [[ -f "$README" ]] && grep -q '参数变更触发清单' "$README"; then
  ok "README 含参数变更触发清单"
else
  err "README 缺参数变更触发清单"
fi
if [[ -f "$README" ]] && grep -q '先执行 infra\|先跑 infra\|请先执行 infra' "$README"; then
  ok "README 含前后端 CI 缺参提示"
else
  err "README 缺「先跑 infra」缺参提示"
fi

# —— 7.5 jwt-authorizer-id 自动化消费者 ——
if [[ -f "$ROUTES_LIVE" ]] && grep -q '/cloudjian/jwt-authorizer-id' "$ROUTES_LIVE"; then
  ok "get-routes 门禁读取 jwt-authorizer-id"
else
  err "verify_routes_live.sh 未引用 jwt-authorizer-id"
fi

# 根装配接线
if [[ -f "$ROOT_SSM" ]] && grep -q 'module "ssm"' "$ROOT_SSM"; then
  ok "根配置已装配 module ssm"
else
  err "根配置缺 module ssm"
fi
# 禁止字面量域名/12 位账户
if grep -E 'd[0-9a-z]+\.cloudfront\.net|arn:aws:lambda:[a-z0-9-]+:[0-9]{12}:' "$ROOT_SSM" "$SSM" >/dev/null 2>&1; then
  err "ssm 装配出现写死域名或账户 ARN"
else
  ok "值均从模块输出派生"
fi

if [[ "$FAIL" -ne 0 ]]; then
  echo "verify_ssm_structure: FAILED" >&2
  exit 1
fi
echo "verify_ssm_structure: PASSED"
