#!/usr/bin/env bash
# INF-05 结构门禁：infra 只建 API 壳（API / Stage / JWT 授权器 / CORS），
# 路由与集成归 backend；infra 不得出现任何路由、集成或函数名清单。
# 路由红线（无 $default、仅 N8 匿名、M4 不挂载）由 backend CI 校验（契约 §2.6）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF="$ROOT/modules/apigw/main.tf"
FAIL=0
err() { echo "FAIL: $*" >&2; FAIL=1; }
ok()  { echo "  ok: $*"; }

[[ -f "$TF" ]] || { err "缺少 $TF"; exit 1; }

# 1) infra 不建路由/集成（新增接口只改 backend）
if grep -qE 'resource\s+"aws_apigatewayv2_(route|integration)"' "$TF"; then
  err "infra 出现 route/integration（应归 backend）"
else
  ok "无 route / integration（归 backend）"
fi

# 2) infra 不枚举函数名 / 不拼函数 ARN
if grep -qE 'function_names|function:cloudjian-|cloudjian-[a-z0-9-]+-api' "$TF"; then
  err "infra 枚举了函数名或函数 ARN"
else
  ok "不枚举函数名 / 函数 ARN"
fi

# 3) 不得出现 $default
if grep -q '$default' "$TF"; then
  # 注释里允许出现「不存在 $default」的说明
  if grep -E 'route_key\s*=\s*"\$default"' "$TF" | grep -qv '^\s*#'; then
    err "出现 \$default 路由"
  else
    ok "无 \$default 路由"
  fi
else
  ok "无 \$default 路由"
fi

# 4) 壳必须齐：API / Stage / JWT 授权器
for r in aws_apigatewayv2_api aws_apigatewayv2_stage aws_apigatewayv2_authorizer; do
  if grep -qE "resource\s+\"$r\"" "$TF"; then
    ok "存在 $r"
  else
    err "缺 $r"
  fi
done

# 5) CORS 与授权器配置
grep -q 'if-match' "$TF" && ok "AllowHeaders 含 if-match" || err "缺 if-match"
grep -q 'etag' "$TF" && ok "ExposeHeaders 含 etag" || err "缺 etag expose"
grep -q 'audience = \[var.cognito_client_id\]' "$TF" && ok "Audience=client_id" || err "Audience 不是 client_id"
grep -q 'cognito-idp' "$TF" && ok "Issuer 指向用户池" || err "Issuer 缺失"

# 6) 访问日志 30 天（root apigw_logs.tf）
if grep -q 'retention_in_days = 30' "$ROOT/apigw_logs.tf"; then
  ok "API 访问日志保留 30 天"
else
  err "访问日志保留期不是 30"
fi

# 7) 红线：infra TF 不得建 Lambda
if grep -qE 'resource\s+"aws_lambda_' "$TF"; then
  err "apigw 模块出现 aws_lambda_*"
else
  ok "无 aws_lambda_*"
fi

if [[ "$FAIL" -ne 0 ]]; then
  echo "verify_apigw_shell: FAILED" >&2
  exit 1
fi
echo "verify_apigw_shell: PASSED"
