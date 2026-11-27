# SSM 参数总线装配
# 全部值从既有模块输出派生，禁止写字面量域名/ARN（单一写方）。

module "ssm" {
  source = "./modules/ssm"

  project              = var.project
  region               = var.region
  bucket               = module.storage.data_bucket_id
  cdn_domain           = module.cdn.domain_name
  cdn_arn              = module.cdn.distribution_arn
  api_url              = module.apigw.api_endpoint
  user_pool_id         = module.cognito.user_pool_id
  client_id            = module.cognito.client_id
  lambda_exec_role_arn = module.iam.lambda_role_arn
  lambda_alias         = "live"
  api_id               = module.apigw.api_id
  jwt_authorizer_id    = module.apigw.authorizer_id
}
