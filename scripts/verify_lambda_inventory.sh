#!/usr/bin/env bash
# 一条路由一个函数（契约 §2.6 / 架构 10.4）的清单一致性门禁。
# 期望：37 个接口函数 + 1 个 maintenance；apigw / IAM / 可观测 / 契约四处清单必须一致。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0
err() { echo "FAIL: $*" >&2; FAIL=1; }
ok()  { echo "  ok: $*"; }

python - "$ROOT" <<'PY' || FAIL=1
import pathlib, re, sys

root = pathlib.Path(sys.argv[1])
fail = 0
def err(m):
    global fail
    print("FAIL:", m, file=sys.stderr)
    fail = 1
def ok(m):
    print("  ok:", m)

def names_between(text, start, end):
    block = text.split(start, 1)[1].split(end, 1)[0]
    return re.findall(r"cloudjian-[a-z0-9-]+-api", block)

apigw = (root / "modules/apigw/main.tf").read_text(encoding="utf-8")
iam = (root / "modules/iam/main.tf").read_text(encoding="utf-8")
obs = (root / "modules/observability/variables.tf").read_text(encoding="utf-8")
contract = (root / "docs/云笺-ALL-契约-接口契约-v0.1.md").read_text(encoding="utf-8")

set_apigw = set(names_between(apigw, "function_names = [", "\n  ]"))
set_iam = set(names_between(iam, "lambda_function_names = [", "\n  ]"))
set_obs = set(names_between(obs, "default = [", "\n  ]"))
set_contract = set(names_between(contract, "### 2.6 路由 → 函数", "\n## 3. "))

if len(set_apigw) != 37:
    err(f"apigw 接口函数 {len(set_apigw)} 个 != 37")
else:
    ok("apigw 接口函数 = 37")
for label, got in (("IAM", set_iam), ("可观测", set_obs)):
    if len(got) != 38:
        err(f"{label} 函数 {len(got)} 个 != 38（37 接口 + maintenance）")
    else:
        ok(f"{label} 函数 = 38")
if len(set_contract) != 38:
    err(f"契约 §2.6 函数 {len(set_contract)} 个 != 38")
else:
    ok("契约 §2.6 函数 = 38")

expect_all = set_apigw | {"cloudjian-maintenance-api"}
for label, got in (("IAM", set_iam), ("可观测", set_obs), ("契约", set_contract)):
    if got != expect_all:
        err(f"{label} 与 apigw+maintenance 不一致：{sorted(got ^ expect_all)}")
    else:
        ok(f"{label} 与 apigw+maintenance 一致")
sys.exit(fail)
PY

if [[ "$FAIL" -ne 0 ]]; then
  echo "verify_lambda_inventory: FAILED" >&2
  exit 1
fi
echo "verify_lambda_inventory: PASSED"
