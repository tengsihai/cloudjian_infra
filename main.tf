# 云笺基础设施 — 单环境根配置（release 即线上）
# workspace 固定为 tokyo；资源无 <env> 后缀。

locals {
  workspace = terraform.workspace
  name      = var.project # cloudjian
}

# workspace 校验：只允许 tokyo，防止误在 default 上 apply
check "workspace_is_tokyo" {
  assert {
    condition     = local.workspace == "tokyo"
    error_message = "terraform workspace 必须为 tokyo（单环境），当前为 '${local.workspace}'。"
  }
}

# —— 模块装配区 ——
# module "storage" { ... }      # 桶、生命周期、策略
# module "cdn" { ... }          # CloudFront + Function
# module "cognito" { ... }      # 用户池与 App Client
# module "apigw" { ... }        # HTTP API
# module "iam" { ... }          # 角色与策略
# module "ssm" 在 ssm.tf 装配
# module "scheduler" 在 scheduler.tf 装配
# module "observability" 在 observability.tf 装配

module "network" {
  source = "./modules/network"

  enable_vpc = var.enable_vpc
  project    = var.project
}
