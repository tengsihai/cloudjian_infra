#!/usr/bin/env bash
# 结构校验：生命周期必须是「标签过滤」，禁止 prefix 字面匹配。
# 造数命中（get-object-tagging / list-objects-v2）在 apply 后由
# scripts/verify_lifecycle_live.sh 执行（需要 AWS 凭证）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0
err() { echo "FAIL: $*" >&2; FAIL=1; }
ok()  { echo "  ok: $*"; }

LIFECYCLE_TF="$ROOT/modules/storage/main.tf"

[[ -f "$LIFECYCLE_TF" ]] || { err "缺少 $LIFECYCLE_TF"; exit 1; }

# 1) 生命周期规则内不得出现 prefix 过滤
if awk '/aws_s3_bucket_lifecycle_configuration/,/^}/' "$LIFECYCLE_TF" \
  | grep -nE '(^|[^_])prefix\s*='; then
  err "生命周期使用 prefix 过滤；必须用 cj:retention 标签"
else
  ok "无 prefix 过滤"
fi

# 2) 必须有 30d / 1d 两个标签档
for v in 30d 1d; do
  if grep -q "value\s*=\s*\"$v\"" "$LIFECYCLE_TF"; then
    ok "存在 cj:retention=$v 规则"
  else
    err "缺少 cj:retention=$v 规则"
  fi
done

# 3) 标签键必须是 cj:retention
if grep -q 'key\s*=\s*"cj:retention"' "$LIFECYCLE_TF"; then
  ok "标签键为 cj:retention"
else
  err "标签键不是 cj:retention"
fi

# 4) 桶级兜底必须含非当前版本清理 + 删除标记过期 + 分片中止
grep -q 'newer_noncurrent_versions' "$LIFECYCLE_TF" \
  && ok "非当前版本保留份数已配置" || err "缺少 newer_noncurrent_versions"
grep -q 'expired_object_delete_marker' "$LIFECYCLE_TF" \
  && ok "ExpiredObjectDeleteMarker 已配置" || err "缺少 expired_object_delete_marker"
grep -q 'abort_incomplete_multipart_upload' "$LIFECYCLE_TF" \
  && ok "未完成分片中止已配置" || err "缺少 abort_incomplete_multipart_upload"

# 5) BPA + Versioning + 加密（无日志桶/无桶 logging——成本取舍）
for res in aws_s3_bucket_public_access_block aws_s3_bucket_versioning \
           aws_s3_bucket_server_side_encryption_configuration; do
  grep -q "resource \"$res\"" "$LIFECYCLE_TF" \
    && ok "$res 存在" || err "缺少 $res"
done

# 6) 不得出现日志桶或桶 logging（成本取舍，见 docs/infra/03）
if grep -qE 'aws_s3_bucket" "logs"|aws_s3_bucket_logging|s3-logs-tokyo' "$LIFECYCLE_TF"; then
  err "出现日志桶或 aws_s3_bucket_logging；当前口径为不建日志桶"
else
  ok "无日志桶/无桶 logging"
fi

# 7) 数据桶名与文档一致
grep -q 'data-tokyo' "$LIFECYCLE_TF" \
  && ok "数据桶名 cloudjian-data-tokyo" || err "数据桶名不符"

if [[ "$FAIL" -ne 0 ]]; then
  echo "verify_lifecycle_structure: FAILED" >&2
  exit 1
fi
echo "verify_lifecycle_structure: PASSED"
