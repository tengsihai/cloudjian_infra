#!/usr/bin/env bash
# P-09 INF-10 结构门禁（9.1–9.8 静态审查）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WF="$ROOT/.github/workflows"
FAIL=0
err() { echo "FAIL: $*" >&2; FAIL=1; }
ok()  { echo "  ok: $*"; }

[[ -d "$WF" ]] || { err "缺少 .github/workflows"; exit 1; }

# 必备 workflow
for f in ci.yml deploy.yml release.yml drift.yml state-backup.yml; do
  [[ -f "$WF/$f" ]] && ok "workflow ${f}" || err "缺 workflow ${f}"
done

# —— 9.6 禁 pull_request_target；Action 按 SHA 锁 ——
# 只拦真实触发键（`on:` 段或顶层键），忽略注释里的「禁 pull_request_target」说明
if grep -RhE '^\s*(pull_request_target|on:.*pull_request_target)' "$WF" >/dev/null 2>&1 \
  || grep -RhE '^\s+pull_request_target\s*:' "$WF" >/dev/null 2>&1; then
  err "出现 pull_request_target 触发（公开仓红线）"
else
  ok "无 pull_request_target 触发"
fi

# 所有 uses: 必须是 owner/repo@40hex（忽略本地 action）
BAD_USES=$(grep -RhE '^\s+uses:' "$WF" | grep -vE 'uses:\s+\./' | grep -vE 'uses:\s+[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+@[0-9a-f]{40}\s*(#.*)?$' || true)
if [[ -n "$BAD_USES" ]]; then
  err "Action 未按 40 位 SHA 锁：$BAD_USES"
else
  ok "全部 uses 按 commit SHA 锁"
fi

# —— 9.7 凭证 job 必须 environment: dev；纯 lint 不得强制 ——
# 带 configure-aws-credentials 的 job 所在 job 块需含 environment: dev
python - <<'PY' "$WF" || FAIL=1
import re, sys, pathlib
wf = pathlib.Path(sys.argv[1])
fail = 0
def err(m):
    global fail
    print("FAIL:", m, file=sys.stderr)
    fail = 1
def ok(m):
    print("  ok:", m)

for path in sorted(wf.glob("*.yml")):
    text = path.read_text(encoding="utf-8")
    # 按 job: 顶层键切分（缩进 2 的 job 名）
    # 简化：若文件含 configure-aws-credentials，则每个含该 step 的 job 块必须有 environment: dev
    if "configure-aws-credentials" not in text:
        continue
    # 拆 jobs 段
    m = re.search(r"^jobs:\n(.*)$", text, re.M | re.S)
    if not m:
        continue
    jobs_blob = m.group(1)
    # job 定义：行首两空格 + name:
    parts = re.split(r"(?m)^(?=  [A-Za-z0-9_-]+:\s*$)", jobs_blob)
    for part in parts:
        if not part.strip():
            continue
        jm = re.match(r"  ([A-Za-z0-9_-]+):", part)
        if not jm:
            continue
        job = jm.group(1)
        if "configure-aws-credentials" in part:
            if re.search(r"(?m)^\s+environment:\s*dev\s*$", part):
                ok(f"{path.name}:{job} environment: dev")
            else:
                err(f"{path.name}:{job} 带 AWS 凭证但未声明 environment: dev")
        else:
            # 纯 lint 不应有 environment（可选，不强制失败）
            pass
sys.exit(fail)
PY

# —— 9.2 deploy：merged PR 二次校验 ——
if grep -q 'gh pr list' "$WF/deploy.yml" && grep -q 'merged' "$WF/deploy.yml"; then
  ok "deploy 含 merged-PR 二次校验"
else
  err "deploy 缺 gh pr list --state merged"
fi
if grep -q 'terraform apply' "$WF/deploy.yml"; then
  ok "deploy 执行 apply"
else
  err "deploy 无 apply"
fi

# —— 9.3 release 零部署 ——
# 只看真正执行的 run 行，忽略自检 grep 字符串
if grep -E '^\s+run:.*terraform (apply|destroy)' "$WF/release.yml" >/dev/null 2>&1; then
  err "release.yml 含 apply/destroy 执行步骤"
else
  ok "release.yml 零部署"
fi
if grep -q '/cloudjian/release/archive' "$WF/release.yml"; then
  ok "release 写 release/archive"
else
  err "release 未写 release/archive"
fi

# —— 9.4 每周漂移（cron 周一，不是每日）——
if grep -q 'cron:' "$WF/drift.yml"; then
  CRON=$(grep -oE 'cron:\s*"[^"]+"' "$WF/drift.yml" | head -1)
  # 每周形态：日字段为 * 或数字，月 * ；且不能是每日 * * * * *
  if echo "$CRON" | grep -qE 'cron:\s*"0 3 \* \* 1"'; then
    ok "drift 每周一 03:00 UTC"
  else
    err "drift cron 非每周（${CRON}）"
  fi
else
  err "drift 无 schedule"
fi
if grep -q 'issues.create' "$WF/drift.yml" || grep -q 'createIssue\|issues.create' "$WF/drift.yml"; then
  ok "drift 有差异开 Issue"
else
  err "drift 未开 Issue"
fi

# —— 9.5 匿名穿透条件 ——
if grep -q 'verify_cdn_matrix' "$WF/deploy.yml"; then
  ok "deploy 可触发匿名穿透"
else
  err "deploy 未接 verify_cdn_matrix"
fi

# —— 9.8 状态备份月度 ——
if grep -q '0 4 1 \* \*' "$WF/state-backup.yml"; then
  ok "state-backup 每月 1 日"
else
  err "state-backup 非月度"
fi
if grep -q 'aws s3 sync' "$WF/state-backup.yml"; then
  ok "state-backup 全量 sync"
else
  err "state-backup 无 s3 sync"
fi

# —— plan 摘要脚本只出计数 ——
if [[ -f "$ROOT/scripts/plan_summary.py" ]]; then
  ok "plan_summary.py 入库"
else
  err "缺 plan_summary.py"
fi

# environment 硬约束写进 README
if grep -q 'environment: dev' "$ROOT/README.md"; then
  ok "README 记载 environment: dev"
else
  err "README 缺 environment: dev 约束"
fi

if [[ "$FAIL" -ne 0 ]]; then
  echo "verify_ci_structure: FAILED" >&2
  exit 1
fi
echo "verify_ci_structure: PASSED"
