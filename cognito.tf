# INF-04 装配（P-04）

module "cognito" {
  source = "./modules/cognito"

  project = var.project
}
