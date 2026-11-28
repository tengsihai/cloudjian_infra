#!/usr/bin/env bash
# 实测校验（apply 后、需 AWS 凭证）：
#   造 4 类对象 → get-object-tagging 校验标签 → list-objects-v2 校验规则命中 >0。
# 长周期项（8 天非当前 ≤3、31 天清空）不在本脚本内，靠人工记录实测日志。
#
# 用法：
#   BUCKET=cloudjian-data-tokyo ./scripts/verify_lifecycle_live.sh
set -euo pipefail

REGION="${AWS_REGION:-ap-northeast-1}"
BUCKET="${BUCKET:-cloudjian-data-tokyo}"
PREFIX="${PREFIX:-users/_lifecycle_probe/}"   # 探针前缀，验收后可清理
EXPORTS_KEY="${EXPORTS_KEY:-exports/job-probe.zip}"   # 导出包在桶根，不在用户目录下
FAIL=0

err() { echo "FAIL: $*" >&2; FAIL=1; }
ok()  { echo "  ok: $*"; }

need() { command -v "$1" >/dev/null || { echo "missing tool: $1" >&2; exit 1; }; }
need aws
need python3 || need python

py() { python3 "$@" 2>/dev/null || python "$@"; }

put_probe() { # $1=key $2=tag_value(optional)
  local key="$1" tag="${2:-}"
  if [[ -n "$tag" ]]; then
    aws s3api put-object --bucket "$BUCKET" --key "$key" \
      --body <(echo "probe") \
      --tagging "TagSet=[{Key=cj:retention,Value=${tag}}]" \
      --region "$REGION" >/dev/null
  else
    aws s3api put-object --bucket "$BUCKET" --key "$key" \
      --body <(echo "probe") --region "$REGION" >/dev/null
  fi
}

assert_tag() { # $1=key $2=expected
  local key="$1" want="$2"
  local got
  got=$(aws s3api get-object-tagging --bucket "$BUCKET" --key "$key" \
    --region "$REGION" --query 'TagSet[?Key==`cj:retention`].Value' --output text)
  if [[ "$got" == "$want" ]]; then
    ok "tag $key = $got"
  else
    err "tag $key = '$got' (want '$want')"
  fi
}

echo "==> lifecycle live probe on s3://$BUCKET (prefix=$PREFIX)"

# —— 4 类造数（生命周期验收口径）——
# 1. 标签 30d：模拟 trash 移入（写入侧由 backend 打标；此处直接造带标签对象）
put_probe "${PREFIX}trash/probe.md" "30d"
# 2. 标签 30d：versions
put_probe "${PREFIX}versions/01ARZ3NDEKTSV4RRFFQ69G5FAV/probe.md" "30d"
# 3. 标签 1d：exports
put_probe "$EXPORTS_KEY" "1d"
# 4. 无标签：普通笔记（走桶级兜底）
put_probe "${PREFIX}notes/probe.md"

assert_tag "${PREFIX}trash/probe.md" "30d"
assert_tag "${PREFIX}versions/01ARZ3NDEKTSV4RRFFQ69G5FAV/probe.md" "30d"
assert_tag "$EXPORTS_KEY" "1d"

# —— list-objects-v2 按标签计数（规则命中 >0）——
count_tag() { # $1=tag_value
  aws s3api list-objects-v2 --bucket "$BUCKET" \
    --query "length(Contents[?Tags[?Key=='cj:retention' && Value=='$1']])" \
    --output text --region "$REGION"
}

for v in 30d 1d; do
  n=$(count_tag "$v")
  if [[ "$n" =~ ^[0-9]+$ ]] && [[ "$n" -gt 0 ]]; then
    ok "cj:retention=$v 命中对象数 = $n (>0)"
  else
    err "cj:retention=$v 命中对象数 = '$n'（须 >0；确认生命周期标签由写入侧打上）"
  fi
done

# —— 探针清理（不依赖生命周期等 30 天）——
echo "==> cleanup probes"
aws s3api delete-objects --bucket "$BUCKET" --region "$REGION" --delete "$(py - <<PY
import json,sys
prefix="${PREFIX}"
exports_key="${EXPORTS_KEY}"
keys=[{"Key":prefix+"trash/probe.md"},
      {"Key":prefix+"versions/01ARZ3NDEKTSV4RRFFQ69G5FAV/probe.md"},
      {"Key":exports_key},
      {"Key":prefix+"notes/probe.md"}]
print(json.dumps({"Objects":keys}))
PY
)" >/dev/null 2>&1 || true

if [[ "$FAIL" -ne 0 ]]; then
  echo "verify_lifecycle_live: FAILED" >&2
  exit 1
fi
echo "verify_lifecycle_live: PASSED"
echo "NOTE: 8 天非当前 ≤3 / 31 天清空为长周期项，需另记实测日志。"
