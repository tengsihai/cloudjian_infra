#!/usr/bin/env bash
# 桶策略校验：两条 GetObject（web/公开图）+ 一条前缀受限 ListBucket（缺失对象回 404）；均带 SourceArn 条件。
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
import json,sys,re
policy=json.load(sys.stdin)
stmts=policy.get("Statement",[])
if not isinstance(stmts,list): stmts=[stmts]
fail=0
def ok(m): print("  ok:",m)
def err(m):
    global fail
    print("FAIL:",m,file=sys.stderr); fail=1

def acts(s):
    a=s.get("Action")
    return a if isinstance(a,list) else [a]
def res(s):
    r=s.get("Resource",[])
    return r if isinstance(r,list) else [r]

allows=[s for s in stmts if s.get("Effect")=="Allow"]
get_stmts=[s for s in allows if "s3:GetObject" in acts(s)]
list_stmts=[s for s in allows if "s3:ListBucket" in acts(s)]
other=[s for s in allows if s not in get_stmts and s not in list_stmts]

if len(get_stmts)!=2:
    err(f"GetObject 语句应为 2 条，实际 {len(get_stmts)}")
else:
    ok("GetObject 语句 = 2 条")
if len(list_stmts)!=1:
    err(f"ListBucket 语句应为 1 条，实际 {len(list_stmts)}")
if other:
    err(f"出现多余 Allow 语句: {[s.get(chr(83)+chr(105)+chr(100)) for s in other]}")

resources=[]
for s in get_stmts:
    resources.extend(res(s))
    cond=s.get("Condition",{})
    if "StringEquals" not in cond or "AWS:SourceArn" not in cond["StringEquals"]:
        err("语句缺少 Condition.StringEquals.AWS:SourceArn")
    else:
        src=cond["StringEquals"]["AWS:SourceArn"]
        srcs=src if isinstance(src,list) else [src]
        for v in srcs:
            if "*" in v or "?" in v:
                err(f"SourceArn 含通配: {v}")
            elif not re.match(r"^arn:aws:cloudfront::\d{12}:distribution/[A-Za-z0-9]+$", v):
                err(f"SourceArn 不是分发 ARN: {v}")
            else:
                ok(f"SourceArn = 分发 {v.rsplit(chr(47),1)[-1]}")
    for a in acts(s):
        if a not in ("s3:GetObject","s3:GetObject*"):
            err(f"越权 Action: {a}（只允许 s3:GetObject）")
    p=s.get("Principal",{})
    if p.get("Service")!="cloudfront.amazonaws.com":
        err(f"Principal 不是 cloudfront.amazonaws.com: {p}")
    else:
        ok("Principal = cloudfront.amazonaws.com")

# ListBucket：只用于缺失对象回 404，Resource 只能是桶本身，前缀限定白名单
for s in list_stmts:
    r=res(s)
    if len(r)!=1 or re.search(r"/\*$", r[0]):
        err(f"ListBucket Resource 只能是桶本身: {r}")
    cond=s.get("Condition",{})
    if "StringEquals" not in cond or "AWS:SourceArn" not in cond.get("StringEquals",{}):
        err("ListBucket 缺少 SourceArn 条件")
    prefixes=cond.get("StringLike",{}).get("s3:prefix",[])
    if isinstance(prefixes,str): prefixes=[prefixes]
    if sorted(prefixes)!=sorted(["web/*","users/*/assets/public/*"]):
        err(f"ListBucket 前缀不在白名单内: {prefixes}")
    else:
        ok("ListBucket 前缀 = web/* + users/*/assets/public/*")

# Resource 白名单（GetObject 部分）
allowed_suffixes=("/web/*","/users/*/assets/public/*")
for r in resources:
    if not any(r.endswith(a) for a in allowed_suffixes):
        err(f"Resource 不在两条白名单内: {r}")

if len(resources)==2:
    ok(f"GetObject Resource 恰好两条: {resources}")
else:
    err(f"GetObject Resource 应为 2 条，实际 {len(resources)}: {resources}")

blob=json.dumps(policy)
for bad in [r"arn:aws:s3:::[^/]+/\*$", r"arn:aws:s3:::[^/]+/users/\*$", r"s3:\*", "s3:ListBucketVersions", "s3:DeleteObject"]:
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
