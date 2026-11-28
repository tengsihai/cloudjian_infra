#!/usr/bin/env bash
# 静态校验：可本地复跑，不依赖控制台。
#  账户 ID 不得出现在 TF 字面量（12 位数字）
#  硬性约束 5 Terraform 中不得出现 aws_lambda_function / aws_lambda_layer_version
#  硬性约束 3 生命周期不得使用 prefix 通配（字面匹配陷阱）
#  不得出现任何 VPC/子网/NAT 资源（network 为空模块）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL=0

err() { echo "FAIL: $*" >&2; FAIL=1; }
ok()  { echo "  ok: $*"; }

# —— 0.6 账户 ID（12 位连续数字）出现在 tf 文件 ——
# 排除注释行与常见误伤（版本号 11 位、时间戳 13 位不匹配 \b\d{12}\b 的 12 位边界）
if grep -RInE --include='*.tf' '[^0-9][0-9]{12}[^0-9]' "$ROOT" \
  | grep -vE '^\s*#' ; then
  err "TF 字面量中出现 12 位数字（账户 ID）；一律用 data.aws_caller_identity 推导"
else
  ok "无 12 位账户 ID 字面量"
fi

# —— 硬性约束 5 Lambda 资源 ——
if grep -RInE --include='*.tf' 'aws_lambda_(function|layer_version|alias|permission)\b' "$ROOT"; then
  err "TF 中出现 Lambda 资源；Lambda 全生命周期归 cloudjian_backend"
else
  ok "无 aws_lambda_* 资源（add-permission 亦归 backend）"
fi

# —— 硬性约束 3 生命周期不得使用任何 prefix（trash/、exports/ 等同样禁止）——
# 只看 lifecycle 配置块；当前无 S3 桶 logging（不建日志桶）
LIFECYCLE_HITS=""
while IFS= read -r f; do
  if awk '/aws_s3_bucket_lifecycle_configuration/,/^}/' "$f" | grep -nE '\bprefix\s*='; then
    LIFECYCLE_HITS="$LIFECYCLE_HITS $f"
  fi
done < <(grep -Rl --include='*.tf' 'aws_s3_bucket_lifecycle_configuration' "$ROOT")
if [[ -n "$LIFECYCLE_HITS" ]]; then
  err "生命周期使用 prefix 过滤：$LIFECYCLE_HITS；一律 cj:retention 标签过滤"
else
  ok "生命周期无 prefix 过滤"
fi

# —— 12.6 无 VPC 资源（只匹配 resource/data 声明，忽略注释） ——
if grep -RInE --include='*.tf' '^(resource|data)\s+"aws_(vpc|subnet|nat_gateway|internet_gateway|route_table|route|vpc_endpoint|default_network_acl|default_security_group)"' "$ROOT"; then
  err "出现 VPC 类资源声明；当前决策为不建 VPC"
else
  ok "无 VPC 类资源声明"
fi

# —— 网络模块必须保持空（除变量与 check） ——
if grep -RInE --include='*.tf' 'resource\s+"' "$ROOT/modules/network"; then
  err "modules/network 出现 resource 块；当前为空模块"
else
  ok "modules/network 为空"
fi

if [[ "$FAIL" -ne 0 ]]; then
  echo "verify_static: FAILED" >&2
  exit 1
fi
echo "verify_static: PASSED"
