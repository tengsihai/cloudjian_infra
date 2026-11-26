#!/usr/bin/env bash
# P-08 INF-08 结构门禁：3 条调度、可推导目标 ARN、无函数资源。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF="$ROOT/modules/scheduler/main.tf"
ROOT_SCHED="$ROOT/scheduler.tf"
IAM="$ROOT/modules/iam/main.tf"
FAIL=0
err() { echo "FAIL: $*" >&2; FAIL=1; }
ok()  { echo "  ok: $*"; }

[[ -f "$TF" ]] || { err "缺少 $TF"; exit 1; }

# 8.1 三条调度名
for name in cloudjian-daily-reconcile cloudjian-weekly-contract cloudjian-daily-index-check; do
  if grep -q "$name" "$TF"; then
    ok "调度 ${name}"
  else
    err "缺调度 ${name}"
  fi
done

# 8.2 目标 ARN 可推导字符串，不建函数
if grep -q 'function:cloudjian-maintenance-api:live' "$TF"; then
  ok "目标 ARN → maintenance:live"
else
  err "目标 ARN 未指向 cloudjian-maintenance-api:live"
fi
if grep -qE 'resource\s+"aws_lambda_' "$TF" "$ROOT_SCHED" 2>/dev/null; then
  err "scheduler 模块出现 aws_lambda_*（红线5）"
else
  ok "无 aws_lambda_*"
fi
if grep -q 'function_exists\|data "aws_lambda_function"' "$TF" 2>/dev/null; then
  err "不应 data 查函数存在（不校验存在）"
else
  ok "不校验函数存在"
fi

# 调度组名匹配 IAM SourceArn cloudjian-*
if grep -q 'schedule-group/${var.project}-\*' "$IAM" || grep -q 'schedule-group/cloudjian-\*' "$IAM"; then
  ok "IAM SourceArn 限 cloudjian-* 调度组"
else
  err "IAM 调度组 SourceArn 未收窄"
fi

# 8.3 权限仅 Invoke maintenance:live（P-05 已断言，此处交叉确认）
if grep -q 'function:${local.maintenance_function}:${local.lambda_alias}' "$IAM" \
  || grep -q 'cloudjian-maintenance-api:live' "$IAM"; then
  ok "scheduler 角色 Invoke 限 maintenance:live"
else
  err "scheduler 角色 Invoke 资源未锁定"
fi

# 根装配
if grep -q 'module "scheduler"' "$ROOT_SCHED"; then
  ok "根配置装配 module scheduler"
else
  err "根配置缺 module scheduler"
fi

if [[ "$FAIL" -ne 0 ]]; then
  echo "verify_scheduler_structure: FAILED" >&2
  exit 1
fi
echo "verify_scheduler_structure: PASSED"
