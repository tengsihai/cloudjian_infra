# INF-05 装配（P-06）

module "apigw" {
  source = "./modules/apigw"

  project              = var.project
  region               = var.region
  cdn_domain           = module.cdn.domain_name
  cognito_user_pool_id = module.cognito.user_pool_id
  cognito_client_id    = module.cognito.client_id
}
