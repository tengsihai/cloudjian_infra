#!/usr/bin/env bash
# 状态桶一次性 bootstrap（唯一允许本地写 AWS 的入口；之后一律走 deploy.yml apply）。
# 创建 cloudjian-tfstate-tokyo（Versioning + BPA + 加密），幂等可重跑。
set -euo pipefail

REGION="${AWS_REGION:-ap-northeast-1}"
STATE_BUCKET="${STATE_BUCKET:-cloudjian-tfstate-tokyo}"

echo "==> ensure state bucket: ${STATE_BUCKET} (${REGION})"

if ! aws s3api head-bucket --bucket "${STATE_BUCKET}" --region "${REGION}" 2>/dev/null; then
  aws s3api create-bucket \
    --bucket "${STATE_BUCKET}" \
    --region "${REGION}" \
    --create-bucket-configuration "LocationConstraint=${REGION}"
  echo "    created"
else
  echo "    already exists"
fi

aws s3api put-bucket-versioning \
  --bucket "${STATE_BUCKET}" \
  --region "${REGION}" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "${STATE_BUCKET}" \
  --region "${REGION}" \
  --server-side-encryption-configuration '{
    "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
  }'

aws s3api put-public-access-block \
  --bucket "${STATE_BUCKET}" \
  --region "${REGION}" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

cat <<EOF

==> bootstrap done.
    1) terraform init   # 使用 backend.tf 中的 s3 配置
    2) terraform workspace new tokyo   # 若尚无 workspace（幂等：已存在则跳过）
    3) terraform plan
    4) 提 PR → 合并 release，由 deploy.yml 执行 apply（含首次）

    禁止本地 terraform apply / import。状态桶与业务桶物理分离；
    本脚本是唯一允许本地写 AWS 的入口（只建状态桶）。
EOF
