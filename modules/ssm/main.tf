# SSM 参数总线
# 前缀 /cloudjian/<key>，单环境无 env 段；Standard 类型（免费、非机密）。
# 单一写方：本模块写 12 条 infra 参数 + release/archive 占位；
# release/backend、release/frontend 由各仓 CI 写，infra 不得创建。

locals {
  # 参数全表（infra 写入方）
  bus = {
    bucket               = var.bucket
    cdn-domain           = var.cdn_domain
    cdn-arn              = var.cdn_arn
    api-url              = var.api_url
    user-pool-id         = var.user_pool_id
    client-id            = var.client_id
    region               = var.region
    lambda-exec-role-arn = var.lambda_exec_role_arn
    lambda-alias         = var.lambda_alias
    api-id               = var.api_id
    jwt-authorizer-id    = var.jwt_authorizer_id
    maintenance-role-arn = var.maintenance_role_arn
  }
}

resource "aws_ssm_parameter" "bus" {
  for_each = local.bus

  name  = "/${var.project}/${each.key}"
  type  = "String"
  value = each.value

  description = "云笺参数总线（infra 单一写方）：${each.key}"

  # 覆盖策略：apply 幂等；禁止其他角色改这些 key（见 IAM 角色矩阵）
  overwrite = true

  tags = {
    ManagedBy = "terraform"
    Project   = var.project
    Component = "ssm"
  }
}

# release/archive：「infra 唯一写入」。
# TF 保证键存在（首 apply 即入表）；main 归档流水线覆盖 value，
# ignore_changes 避免归档写入后每次 plan 报漂移。
resource "aws_ssm_parameter" "release_archive" {
  name = "/${var.project}/release/archive"
  type = "String"
  value = jsonencode({
    state   = "initialized"
    by      = "terraform"
    message = "main 归档流水线将覆盖本值"
  })

  description = "发布归档（仅 infra 仓写入；frontend/backend 角色无此 key 的 Put）"
  overwrite   = true

  lifecycle {
    ignore_changes = [value]
  }

  tags = {
    ManagedBy = "terraform"
    Project   = var.project
    Component = "ssm"
  }
}
