#!/usr/bin/env bash
# P-08 INF-09 结构门禁：平台告警面、独立业务指标、Budgets、成本标签。
# 函数日志组与保留期归 backend；infra 不枚举函数名（新增接口不改 infra）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF="$ROOT/modules/observability/main.tf"
ROOT_OBS="$ROOT/observability.tf"
IAM="$ROOT/modules/iam/main.tf"
FAIL=0
err() { echo "FAIL: $*" >&2; FAIL=1; }
ok()  { echo "  ok: $*"; }

[[ -f "$TF" ]] || { err "缺少 $TF"; exit 1; }

# 8.5 不枚举函数；不建函数日志组（由 backend 部署时设 30 天）
if grep -q 'lambda_function_names\|log_groups' "$TF"; then
  err "observability 枚举了函数名"
else
  ok "不枚举函数名"
fi
if grep -qE 'resource\s+"aws_cloudwatch_log_group"' "$TF"; then
  err "observability 建了函数日志组（应归 backend）"
else
  ok "无函数日志组"
fi
if grep -q 'lambda_errors' "$TF"; then
  err "仍有每函数 Errors 告警（应归 backend 或聚合）"
else
  ok "无每函数 Errors 告警"
fi
filter_count=$(grep -cE 'resource\s+"aws_cloudwatch_log_metric_filter"' "$TF" || true)
if [[ "$filter_count" -eq 1 ]] && grep -q 'resource "aws_cloudwatch_log_metric_filter" "conflict_412"' "$TF"; then
  ok "仅保留 412 访问日志过滤器"
else
  err "日志过滤器数量 $filter_count（应只剩 412）"
fi

# 8.6 告警面
for a in api_5xx cdn_5xx conflict_412 job_running share_revoked publish_failed; do
  if grep -q "aws_cloudwatch_metric_alarm\" \"$a\"" "$TF"; then
    ok "告警 ${a}"
  else
    err "缺告警 ${a}"
  fi
done

# 8.7 独立指标：JOB_RUNNING / SHARE_REVOKED 走 backend EMF 指标
if grep -q 'JobRunning' "$TF" && grep -q 'ShareRevoked' "$TF"; then
  ok "JobRunning / ShareRevoked 独立计数"
else
  err "缺独立业务指标"
fi
if grep -q 'metric_name         = "5xx"' "$TF" && grep -q 'NoteConflict412' "$TF"; then
  ok "412 与 5xx 分离"
else
  err "412 未独立"
fi
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

# 访问日志组 30 天（412 过滤器依赖）
if grep -q 'retention_in_days = 30' "$ROOT/apigw_logs.tf"; then
  ok "API 访问日志保留 30 天"
else
  err "访问日志保留期不是 30"
fi

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
