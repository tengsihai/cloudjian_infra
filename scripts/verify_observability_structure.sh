#!/usr/bin/env bash
# P-08 INF-09 结构门禁：38 日志组 30 天、告警面、独立指标、Budgets、成本标签。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF="$ROOT/modules/observability/main.tf"
ROOT_OBS="$ROOT/observability.tf"
IAM="$ROOT/modules/iam/main.tf"
FAIL=0
err() { echo "FAIL: $*" >&2; FAIL=1; }
ok()  { echo "  ok: $*"; }

[[ -f "$TF" ]] || { err "缺少 $TF"; exit 1; }

# 8.5 38 个函数日志组 + 30 天（名字在 variables 默认表，日志组名 = 函数名）
VARS="$ROOT/modules/observability/variables.tf"
fn_count=$(grep -cE '^    "cloudjian-[a-z0-9-]+-api",$' "$VARS" || true)
if [[ "$fn_count" -eq 38 ]]; then
  ok "函数表 = 38 个（37 接口 + maintenance）"
else
  err "函数表数量 $fn_count != 38"
fi
if grep -q 'log_groups = { for fn in var.lambda_function_names : fn => fn }' "$TF"; then
  ok "日志组名 = 函数名"
else
  err "日志组命名规则缺失"
fi
if grep -q 'retention_in_days = 30' "$TF"; then
  ok "保留 30 天"
else
  err "日志保留不是 30"
fi

# 8.6 告警面
for a in api_5xx cdn_5xx conflict_412 publish_failed; do
  if grep -q "aws_cloudwatch_metric_alarm\" \"$a\"" "$TF" || grep -q "metric_alarm\" \"$a\"" "$TF"; then
    ok "告警 ${a}"
  else
    err "缺告警 ${a}"
  fi
done
# Lambda 错误率：for_each 六函数
if grep -q 'lambda_errors' "$TF" && grep -q 'for_each = toset(var.lambda_function_names)' "$TF"; then
  ok "Lambda 错误率按函数"
else
  err "缺 Lambda 错误率告警"
fi

# 8.7 独立指标：JOB_RUNNING / SHARE_REVOKED 存在且非 5xx 命名空间
if grep -q 'JOB_RUNNING' "$TF" && grep -q 'ShareRevoked' "$TF" && grep -q 'JobRunning' "$TF"; then
  ok "JOB_RUNNING / SHARE_REVOKED 独立计数"
else
  err "缺独立业务指标"
fi
if grep -q 'metric_name         = "5xx"' "$TF" && grep -q 'NoteConflict412' "$TF"; then
  ok "412 与 5xx 分离"
else
  err "412 未独立"
fi
# 5xx 告警不得引用 412/JOB 指标
if awk '/metric_alarm" "api_5xx"/,/^}/' "$TF" | grep -qE 'NoteConflict412|JobRunning|ShareRevoked'; then
  err "api_5xx 告警混入业务计数"
else
  ok "api_5xx 只盯 AWS/ApiGateway 5xx"
fi

# 8.8 Budgets $5 + 80/100 + 成本标签四键
if grep -q 'budget_monthly_usd' "$TF" && grep -q '\[80, 100\]' "$TF"; then
  ok "Budgets 80%/100% 动态通知"
else
  err "Budgets 阈值通知缺失"
fi
for tag in Project Component Environment ManagedBy; do
  if grep -q "tag_key  = \"$tag\"" "$TF" || grep -q "tag_key = \"$tag\"" "$TF"; then
    ok "成本标签 ${tag}"
  else
    err "缺成本标签 ${tag}"
  fi
done

# 根装配 + 变量接线
if grep -q 'module "observability"' "$ROOT_OBS"; then
  ok "根配置装配 module observability"
else
  err "根配置缺 module observability"
fi

# terraform 角色具备云预算/告警/调度权限（P-05 后补）
for sid in ManageAlarms ManageAlarmTopics ManageBudgets ManageScheduler CostTags; do
  if grep -q "$sid" "$IAM"; then
    ok "IAM ${sid}"
  else
    err "IAM 缺 ${sid}"
  fi
done

# 无 lambda 资源
if grep -qE 'resource\s+"aws_lambda_' "$TF" "$ROOT_OBS" 2>/dev/null; then
  err "observability 出现 aws_lambda_*"
else
  ok "无 aws_lambda_*"
fi

if [[ "$FAIL" -ne 0 ]]; then
  echo "verify_observability_structure: FAILED" >&2
  exit 1
fi
echo "verify_observability_structure: PASSED"
