#!/usr/bin/env bash
# P-08 实测门禁（apply 后）：调度、日志组保留、告警、预算、成本标签。
#
# 用法：./scripts/verify_p08_live.sh
set -euo pipefail

REGION="${AWS_REGION:-ap-northeast-1}"
PROJECT="${CJ_PROJECT:-cloudjian}"

echo "==> scheduler / logs / alarms / budget @ ${REGION}"

GROUPS_JSON=$(aws scheduler list-schedule-groups --region "$REGION" --output json)
SCHEDULES_JSON=$(aws scheduler list-schedules --region "$REGION" --output json)
ALARMS_JSON=$(aws cloudwatch describe-alarms \
  --alarm-name-prefix "${PROJECT}-" \
  --region "$REGION" --output json)
LOGS_JSON=$(aws logs describe-log-groups \
  --log-group-name-prefix "${PROJECT}-" \
  --region "$REGION" --output json)
BUDGET_JSON=$(aws budgets describe-budgets \
  --account-id "$(aws sts get-caller-identity --query Account --output text)" \
  --region "$REGION" --output json 2>/dev/null || echo '{"Budgets":[]}')
TAGS_JSON=$(aws ce list-cost-allocation-tags --region us-east-1 --output json 2>/dev/null \
  || aws ce list-cost-allocation-tags --output json)

python - "$GROUPS_JSON" "$SCHEDULES_JSON" "$ALARMS_JSON" "$LOGS_JSON" "$BUDGET_JSON" "$TAGS_JSON" <<'PY'
import json, sys

groups = json.loads(sys.argv[1])
schedules = json.loads(sys.argv[2])
alarms = json.loads(sys.argv[3])
logs = json.loads(sys.argv[4])
budgets = json.loads(sys.argv[5])
tags = json.loads(sys.argv[6])

fail = 0
def ok(m): print("  ok:", m)
def err(m):
    global fail
    print("FAIL:", m, file=sys.stderr)
    fail = 1

# 调度组
gnames = [g.get("Name") for g in groups.get("ScheduleGroups", [])]
if any(n and n.startswith("cloudjian-") for n in gnames):
    ok(f"调度组含 cloudjian-*: {gnames}")
else:
    err(f"缺 cloudjian-* 调度组: {gnames}")

# 三条调度
snames = {s.get("Name") for s in schedules.get("Schedules", [])}
for name in (
    "cloudjian-daily-reconcile",
    "cloudjian-weekly-contract",
    "cloudjian-daily-index-check",
):
    if name in snames:
        ok(f"调度存在 {name}")
    else:
        err(f"缺调度 {name}")

# 目标 ARN（若 get-schedule 可拿到）
# list 不含 Target，逐条 get
import subprocess, os
region = os.environ.get("AWS_REGION", "ap-northeast-1")
for name in sorted(snames):
    if not name.startswith("cloudjian-"):
        continue
    out = subprocess.check_output(
        ["aws", "scheduler", "get-schedule", "--name", name,
         "--group-name", next(g for g in gnames if g and g.startswith("cloudjian-")),
         "--region", region, "--output", "json"],
        text=True,
    )
    sch = json.loads(out)
    arn = sch.get("Target", {}).get("Arn", "")
    if arn.endswith(":function:cloudjian-maintenance-api:live"):
        ok(f"{name} → maintenance:live")
    else:
        err(f"{name} 目标 ARN={arn}")

# 日志组 6 + 30 天
expected_lg = [
    "cloudjian-notes-api-api",
    "cloudjian-share-api-api",
    "cloudjian-asset-api-api",
    "cloudjian-admin-api-api",
    "cloudjian-export-api-api",
    "cloudjian-maintenance-api-api",
]
by_lg = {lg["logGroupName"]: lg for lg in logs.get("logGroups", [])}
for name in expected_lg:
    lg = by_lg.get(name)
    if not lg:
        err(f"缺日志组 {name}")
    elif lg.get("retentionInDays") != 30:
        err(f"{name} retention={lg.get('retentionInDays')} (want 30)")
    else:
        ok(f"{name} retention=30")

# 告警
anames = {a["AlarmName"] for a in alarms.get("MetricAlarms", [])}
for a in (
    "cloudjian-api-5xx",
    "cloudjian-cdn-5xx",
    "cloudjian-conflict-412",
    "cloudjian-job-running",
    "cloudjian-share-revoked",
    "cloudjian-publish-failed",
):
    if a in anames:
        ok(f"告警 {a}")
    else:
        err(f"缺告警 {a}")
# lambda errors ×6
err_alarms = [n for n in anames if n.endswith("-errors")]
if len(err_alarms) >= 6:
    ok(f"Lambda 错误率告警 {len(err_alarms)} 条")
else:
    err(f"Lambda 错误率告警仅 {len(err_alarms)} 条")

# 预算
bl = budgets.get("Budgets", [])
bj = next((b for b in bl if b.get("BudgetName") == "cloudjian"), None)
if not bj:
    err("缺预算 cloudjian")
else:
    amt = float(bj["BudgetLimit"]["Amount"])
    if amt != 5.0:
        err(f"预算限额 {amt} != 5")
    else:
        ok("预算 $5/月")
    notifs = bj.get("Notifications", [])
    # 有邮箱时 80/100；无邮箱时可能 0 条
    if notifs:
        th = sorted({int(n["Threshold"]) for n in notifs})
        if th == [80, 100]:
            ok("预算通知 80%/100%")
        else:
            err(f"预算阈值 {th}")
    else:
        ok("预算无邮件订阅（变量为空，控制台可补）")

# 成本标签 Active
active = {
    t["TagKey"] for t in tags.get("CostAllocationTags", [])
    if t.get("Status") == "Active"
}
for k in ("Project", "Component", "Environment", "ManagedBy"):
    if k in active:
        ok(f"成本标签 {k} Active")
    else:
        err(f"成本标签 {k} 未激活")

sys.exit(fail)
PY
