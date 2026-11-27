# 网关装配（API、Stage、JWT 授权器、CORS、访问日志组）

module "apigw" {
  source = "./modules/apigw"

  project              = var.project
  region               = var.region
  cdn_domain           = module.cdn.domain_name
  cognito_user_pool_id = module.cognito.user_pool_id
  cognito_client_id    = module.cognito.client_id
  access_log_group_arn = aws_cloudwatch_log_group.api_access.arn
}
