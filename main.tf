# 云笺基础设施 — 单环境根配置（dev 即线上，方案 12.4）
# workspace 固定为 tokyo；资源无 <env> 后缀（方案 12.11 单环境）。

locals {
  workspace = terraform.workspace
  name      = var.project # cloudjian
}

# workspace 门禁：只允许 tokyo，防止误在 default 上 apply
check "workspace_is_tokyo" {
  assert {
    condition     = local.workspace == "tokyo"
    error_message = "terraform workspace 必须为 tokyo（单环境），当前为 '${local.workspace}'。"
  }
}

# —— 模块装配区（按 INF 包逐个接入，P-01 起填充）——
# module "storage" { ... }      # INF-01/02
# module "cdn" { ... }          # INF-03
# module "cognito" { ... }      # INF-04
# module "apigw" { ... }        # INF-05
# module "iam" { ... }          # INF-06
# module "ssm" { ... }          # INF-07
# module "scheduler" { ... }    # INF-08
# module "observability" { ... }# INF-09

module "network" {
  source = "./modules/network"

  enable_vpc = var.enable_vpc
  project    = var.project
}
