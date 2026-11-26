#!/usr/bin/env bash
# P-02 门禁：桶策略只允许两条 Resource，且带 SourceArn 条件；无 bucket/* 通配。
# 优先读 Terraform plan JSON / state；也支持拉取线上策略：
#   ./scripts/verify_bucket_policy.sh              # 从 aws cli 拉线上
#   ./scripts/verify_bucket_policy.sh plan.json    # 从 plan 拉
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUCKET="${BUCKET:-cloudjian-data-tokyo}"
FAIL=0
err() { echo "FAIL: $*" >&2; FAIL=1; }
ok()  { echo "  ok: $*"; }

if [[ "${1:-}" == *.json ]]; then
  POLICY_JSON=$(python - "$1" <<'PY'
import json,sys
plan=json.load(open(sys.argv[1]))
# plan 中找 aws_s3_bucket_policy 的 policy 值
def walk(o):
    if isinstance(o, dict):
        if o.get("address","").startswith("aws_s3_bucket_policy") or \
           (isinstance(o.get("address"),str) and "aws_s3_bucket_policy" in o["address"]):
            v=o.get("values",{}).get("policy")
            if v: return v
        for v in o.values():
            r=walk(v)
            if r: return r
    elif isinstance(o, list):
        for v in o:
            r=walk(v)
            if r: return r
    return None
p=walk(plan)
print(p or "")
PY
)
else
  POLICY_JSON=$(aws s3api get-bucket-policy --bucket "$BUCKET" --query Policy --output text)
fi

[[ -n "$POLICY_JSON" && "$POLICY_JSON" != "None" ]] || { err "取不到桶策略"; exit 1; }

echo "$POLICY_JSON" | python -c '
import json,sys
policy=json.load(sys.stdin)
stmts=policy.get("Statement",[])
if not isinstance(stmts,list): stmts=[stmts]
fail=0
def ok(m): print("  ok:",m)
def err(m):
    global fail
    print("FAIL:",m,file=sys.stderr); fail=1

# 必须恰好 2 条 Allow
allows=[s for s in stmts if s.get("Effect")=="Allow"]
if len(allows)!=2:
    err(f"Allow 语句应为 2 条，实际 {len(allows)}")
else:
    ok("Allow 语句 = 2 条")

resources=[]
for s in allows:
    r=s.get("Resource",[])
    if isinstance(r,str): r=[r]
    resources.extend(r)
    # 必须有 SourceArn 条件
    cond=s.get("Condition",{})
    if "StringEquals" not in cond or "AWS:SourceArn" not in cond["StringEquals"]:
        err("语句缺少 Condition.StringEquals.AWS:SourceArn")
    else:
        ok("SourceArn 条件存在（且非字面账户拼接——值应为分发 ARN）")
    # Principal 必须是 cloudfront
    p=s.get("Principal",{})
    if p.get("Service")!="cloudfront.amazonaws.com":
        err(f"Principal 不是 cloudfront.amazonaws.com: {p}")
    else:
        ok("Principal = cloudfront.amazonaws.com")

# Resource 白名单
allowed_suffixes=("/web/*","/users/*/assets/public/*")
for r in resources:
    if r.endswith("/*") and not any(r.endswith(a) for a in allowed_suffixes):
        # 允许 users/*/assets/public/* 与 web/*
        if "/assets/public/" not in r and not r.endswith("/web/*"):
            err(f"越权 Resource: {r}")
    if r.endswith(":bucket") or r.endswith("/*") and r.count("*")==1 and r.endswith("bucket/*"):
        err(f"禁止 bucket/* 通配: {r}")
    if r.endswith("/*") and "/web/" not in r and "/assets/public/" not in r:
        err(f"Resource 不在两条白名单内: {r}")

if len(resources)==2:
    ok(f"Resource 恰好两条: {resources}")
elif len(resources)!=2:
    err(f"Resource 应为 2 条，实际 {len(resources)}: {resources}")

# 明确拒绝 bucket/* 与 users/* 整段
blob=json.dumps(policy)
if "\"arn:aws:s3:::' + '" in blob: pass
import re
for bad in [r"arn:aws:s3:::[^/]+/\*$", r"arn:aws:s3:::[^/]+/users/\*$"]:
    if re.search(bad, blob):
        err(f"命中禁止模式 {bad}")

sys.exit(fail)
'

rc=$?
if [[ $rc -ne 0 ]]; then FAIL=1; fi

if [[ "$FAIL" -ne 0 ]]; then
  echo "verify_bucket_policy: FAILED" >&2
  exit 1
fi
echo "verify_bucket_policy: PASSED"
