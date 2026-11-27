#!/usr/bin/env bash
# 结构校验：3 条调度、可推导目标 ARN、无函数资源。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF="$ROOT/modules/scheduler/main.tf"
ROOT_SCHED="$ROOT/scheduler.tf"
IAM="$ROOT/modules/iam/main.tf"
FAIL=0
err() { echo "FAIL: $*" >&2; FAIL=1; }
ok()  { echo "  ok: $*"; }

[[ -f "$TF" ]] || { err "缺少 $TF"; exit 1; }

# 三条调度名
for name in cloudjian-daily-reconcile cloudjian-weekly-contract cloudjian-daily-index-check; do
  if grep -q "$name" "$TF"; then
    ok "调度 ${name}"
  else
    err "缺调度 ${name}"
  fi
done

# 目标 ARN 可推导字符串，不建函数
if grep -q 'function:cloudjian-maintenance-api:live' "$TF"; then
  ok "目标 ARN → maintenance:live"
else
  err "目标 ARN 未指向 cloudjian-maintenance-api:live"
fi
if grep -qE 'resource\s+"aws_lambda_' "$TF" "$ROOT_SCHED" 2>/dev/null; then
  err "scheduler 模块出现 aws_lambda_*（硬性约束 5）"
else
  ok "无 aws_lambda_*"
fi
if grep -q 'function_exists\|data "aws_lambda_function"' "$TF" 2>/dev/null; then
  err "不应 data 查函数存在（不校验存在）"
else
  ok "不校验函数存在"
fi

# 每条 cron 合法：day-of-month 与 day-of-week 只能有一个为 *，另一个必须 ?
#     （EventBridge 同时指定两个会被拒，且周任务必须落在 MON）
while IFS= read -r expr; do
  [[ -z "$expr" ]] && continue
  inner="${expr#cron(}"; inner="${inner%)}"
  # 字段：min hour dom month dow year
  dom=$(echo "$inner" | awk '{print $3}')
  dow=$(echo "$inner" | awk '{print $5}')
  if [[ "$dom" != "?" && "$dow" != "?" ]]; then
    err "cron 非法（dom 与 dow 不能同时指定）: $expr"
  else
    ok "cron 合法: $expr"
  fi
done < <(grep -oE 'cron\([^)]*\)' "$TF")

if grep -q 'cron(0 4 ? \* MON \*)' "$TF"; then
  ok "周契约校验 = 周一 04:00"
else
  err "周契约校验不是 周一 04:00（cron(0 4 ? * MON *)）"
fi

# retry 2 次 / 事件 1 小时；弹性窗口默认 60；时区东京
grep -q 'maximum_retry_attempts\s*=\s*2' "$TF" \
  && ok "retry = 2" || err "maximum_retry_attempts 不是 2"
grep -q 'maximum_event_age_in_seconds\s*=\s*3600' "$TF" \
  && ok "事件有效期 = 3600s" || err "maximum_event_age_in_seconds 不是 3600"
grep -q 'default\s*=\s*60' "$ROOT/modules/scheduler/variables.tf" \
  && ok "弹性窗口默认 60 分钟" || err "flexible_window_minutes 默认不是 60"
grep -q '"Asia/Tokyo"' "$ROOT/modules/scheduler/variables.tf" \
  && ok "时区 Asia/Tokyo" || err "schedule_timezone 默认不是 Asia/Tokyo"

# input 三字段
for k in source task schedule; do
  grep -q "^\s*$k\s*=" "$TF" || err "input 缺字段 $k"
done
grep -q 'source   = "eventbridge-scheduler"' "$TF" \
  && ok "input 含 source/task/schedule" || err "input.source 不是 eventbridge-scheduler"

# 调度组名匹配 IAM SourceArn cloudjian-*
if grep -q 'schedule-group/${var.project}-\*' "$IAM" || grep -q 'schedule-group/cloudjian-\*' "$IAM"; then
  ok "IAM SourceArn 限 cloudjian-* 调度组"
else
  err "IAM 调度组 SourceArn 未收窄"
fi

# 权限仅 Invoke maintenance:live（IAM 脚本已校验，此处交叉确认）
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
