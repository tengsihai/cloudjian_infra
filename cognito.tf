# 认证装配（Cognito 用户池与 App Client）

module "cognito" {
  source = "./modules/cognito"

  project = var.project
}
